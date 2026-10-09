with Ada.Unchecked_Deallocation;
with Interfaces.C;
with Interfaces.C.Strings;
with System;

with Adacraft.Protocol.Varnum;
with Adacraft.Protocol.Zlib;

package body Adacraft.Protocol.Compression is

   use type Interfaces.C.int;
   use type Interfaces.C.unsigned;
   use type Interfaces.C.unsigned_long;
   use type Interfaces.Integer_32;
   use type Adacraft.Protocol.Varnum.Status_Type;

   procedure Free_Access is new Ada.Unchecked_Deallocation
     (Object => Octets, Name => Byte_Array_Access);

   procedure Free (X : in out Byte_Array_Access) is
   begin
      if X /= null then
         Free_Access (X);
      end if;
      X := null;
   end Free;

   procedure Free (R : in out Encode_Result) is
   begin
      if R.Ok and then R.Data /= null then
         Free_Access (R.Data);
      end if;
      R := (Ok => False, Reason => None);
   end Free;

   procedure Free (R : in out Decode_Result) is
   begin
      if R.Ok and then R.Data /= null then
         Free_Access (R.Data);
      end if;
      R := (Ok => False, Reason => None);
   end Free;

   function To_C_Unsigned (N : Natural) return Interfaces.C.unsigned is
     (Interfaces.C.unsigned (N));

   procedure Encode
     (Threshold    : Threshold_Type;
      Uncompressed : Octets;
      R            : out Encode_Result)
   is
      package V renames Adacraft.Protocol.Varnum;
      package Z renames Adacraft.Protocol.Zlib;
   begin
      R := (Ok => False, Reason => None);

      if Uncompressed'Length > Max_Decompressed_Size then
         R := (Ok => False, Reason => Oversize);
         return;
      end if;

      if Uncompressed'Length < Threshold then
         declare
            Out_Len : constant Natural := Uncompressed'Length + 1;
            Out_Ptr : Byte_Array_Access;
            Idx     : Positive;
         begin
            Out_Ptr := new Octets (1 .. Out_Len);
            Out_Ptr (1) := 0;
            Idx := 2;
            for I in Uncompressed'Range loop
               Out_Ptr (Idx) := Uncompressed (I);
               Idx := Idx + 1;
            end loop;
            R := (Ok => True, Data => Out_Ptr);
            return;
         end;
      end if;

      --  Compressed path: VarInt(Uncompressed'Length) + deflate bytes.
      declare
         Prefix_Buf : Octets (1 .. 5) := [others => 0];
         Written    : Natural := 0;
         St         : V.Status_Type := V.Buffer_Too_Small;
         Len32      : constant Interfaces.Integer_32 :=
           Interfaces.Integer_32 (Uncompressed'Length);
      begin
         V.Encode (Len32, Prefix_Buf, 1, Written, St);
         if St /= V.Ok or else Written not in 1 .. 5 then
            R := (Ok => False, Reason => Corrupt_Data);
            return;
         end if;

         declare
            Bound_UL : constant Interfaces.C.unsigned_long :=
              Z.Compress_Bound
                (Interfaces.C.unsigned_long (Uncompressed'Length));
            Bound_Nat : Natural;
            Comp_Ptr  : Byte_Array_Access := null;
            Ver       : Interfaces.C.Strings.chars_ptr;
            Stream    : aliased Z.Z_Stream;
            Rc        : Interfaces.C.int;
            Produced  : Natural := 0;
         begin
            if Bound_UL > Interfaces.C.unsigned_long (Natural'Last) then
               R := (Ok => False, Reason => Oversize);
               return;
            end if;
            Bound_Nat := Natural (Bound_UL);
            --  Guarantee non-null allocation even for empty input.
            Comp_Ptr := new Octets (1 .. Natural'Max (Bound_Nat, 1));

            Ver := Interfaces.C.Strings.New_String (Z.Zlib_Version);
            Z.Init_Stream (Stream);
            if Uncompressed'Length = 0 then
               Z.Set_Input (Stream, System.Null_Address, 0);
            else
               Z.Set_Input
                 (Stream, Uncompressed (Uncompressed'First)'Address,
                  To_C_Unsigned (Uncompressed'Length));
            end if;
            Z.Set_Output
              (Stream, Comp_Ptr (1)'Address, To_C_Unsigned (Bound_Nat));
            Rc := Z.Deflate_Init
              (Stream'Unchecked_Access, Z.Z_Default_Compression, Ver,
               Z.Stream_Size);
            if Rc /= Z.Z_Ok then
               Interfaces.C.Strings.Free (Ver);
               Rc := Z.Deflate_End (Stream'Unchecked_Access);
               Free (Comp_Ptr);
               R := (Ok => False, Reason => Corrupt_Data);
               return;
            end if;
            Rc := Z.Deflate (Stream'Unchecked_Access, Z.Z_Finish);
            if Rc /= Z.Z_Stream_End then
               Interfaces.C.Strings.Free (Ver);
               Rc := Z.Deflate_End (Stream'Unchecked_Access);
               Free (Comp_Ptr);
               R := (Ok => False, Reason => Corrupt_Data);
               return;
            end if;
            if Z.Total_Out (Stream) >
              Interfaces.C.unsigned_long (Natural'Last)
            then
               Interfaces.C.Strings.Free (Ver);
               Rc := Z.Deflate_End (Stream'Unchecked_Access);
               Free (Comp_Ptr);
               R := (Ok => False, Reason => Corrupt_Data);
               return;
            end if;
            Produced := Natural (Z.Total_Out (Stream));
            Rc := Z.Deflate_End (Stream'Unchecked_Access);
            Interfaces.C.Strings.Free (Ver);
            if Rc /= Z.Z_Ok then
               Free (Comp_Ptr);
               R := (Ok => False, Reason => Corrupt_Data);
               return;
            end if;

            declare
               Out_Ptr : Byte_Array_Access;
               Idx     : Positive;
            begin
               Out_Ptr := new Octets (1 .. Written + Produced);
               for I in 1 .. Written loop
                  Out_Ptr (I) := Prefix_Buf (I);
               end loop;
               Idx := Written + 1;
               for I in 1 .. Produced loop
                  Out_Ptr (Idx) := Comp_Ptr (I);
                  Idx := Idx + 1;
               end loop;
               Free (Comp_Ptr);
               R := (Ok => True, Data => Out_Ptr);
               return;
            end;
         end;
      end;
   end Encode;

   procedure Decode
     (Threshold : Threshold_Type;
      Input     : Octets;
      R         : out Decode_Result)
   is
      package V renames Adacraft.Protocol.Varnum;
      package Z renames Adacraft.Protocol.Zlib;
   begin
      R := (Ok => False, Reason => None);

      if Input'Length = 0 then
         R := (Ok => False, Reason => Empty_Body);
         return;
      end if;

      declare
         Value    : Interfaces.Integer_32 := 0;
         Consumed : Natural := 0;
         St       : V.Status_Type := V.Truncated;
         Data_Len : Natural := 0;
      begin
         V.Decode (Input, Input'First, Value, Consumed, St);
         if St /= V.Ok then
            R := (Ok => False, Reason => Bad_Data_Length);
            return;
         end if;
         if Value < 0 then
            R := (Ok => False, Reason => Bad_Data_Length);
            return;
         end if;
         if Consumed not in 1 .. 5
           or else Consumed > Input'Length
         then
            R := (Ok => False, Reason => Bad_Data_Length);
            return;
         end if;
         Data_Len := Natural (Value);

         if Data_Len = 0 then
            declare
               Rest_Len : constant Natural := Input'Length - Consumed;
               Out_Ptr  : Byte_Array_Access;
               Idx      : Positive;
               Src      : Positive;
            begin
               Out_Ptr := new Octets (1 .. Rest_Len);
               Idx := 1;
               Src := Input'First + Consumed;
               for I in 1 .. Rest_Len loop
                  Out_Ptr (Idx) := Input (Src);
                  Idx := Idx + 1;
                  Src := Src + 1;
               end loop;
               R := (Ok => True, Data => Out_Ptr);
               return;
            end;
         end if;

         if Data_Len > Max_Decompressed_Size then
            R := (Ok => False, Reason => Oversize);
            return;
         end if;

         if Data_Len < Threshold then
            R := (Ok => False, Reason => Below_Threshold);
            return;
         end if;

         declare
            Suffix_Len : constant Natural := Input'Length - Consumed;
            Suffix_First : constant Positive := Input'First + Consumed;
            Out_Ptr    : Byte_Array_Access := null;
            Ver        : Interfaces.C.Strings.chars_ptr;
            Stream     : aliased Z.Z_Stream;
            Rc_Init    : Interfaces.C.int;
            Rc         : Interfaces.C.int;
            Total      : Interfaces.C.unsigned_long;
            Left_In    : Interfaces.C.unsigned;
         begin
            Out_Ptr := new Octets (1 .. Data_Len);
            Ver := Interfaces.C.Strings.New_String (Z.Zlib_Version);
            Z.Init_Stream (Stream);
            if Suffix_Len = 0 then
               Z.Set_Input (Stream, System.Null_Address, 0);
            else
               Z.Set_Input
                 (Stream, Input (Suffix_First)'Address,
                  To_C_Unsigned (Suffix_Len));
            end if;
            Z.Set_Output
              (Stream, Out_Ptr (1)'Address, To_C_Unsigned (Data_Len));
            Rc_Init := Z.Inflate_Init
              (Stream'Unchecked_Access, Ver, Z.Stream_Size);
            if Rc_Init /= Z.Z_Ok then
               Interfaces.C.Strings.Free (Ver);
               Rc := Z.Inflate_End (Stream'Unchecked_Access);
               Free (Out_Ptr);
               R := (Ok => False, Reason => Corrupt_Data);
               return;
            end if;
            Rc := Z.Inflate (Stream'Unchecked_Access, Z.Z_Finish);
            Total := Z.Total_Out (Stream);
            Left_In := Z.Avail_In (Stream);
            if Rc = Z.Z_Stream_End then
               if Total /= Interfaces.C.unsigned_long (Data_Len) then
                  Interfaces.C.Strings.Free (Ver);
                  Rc := Z.Inflate_End (Stream'Unchecked_Access);
                  Free (Out_Ptr);
                  R := (Ok => False, Reason => Size_Mismatch);
                  return;
               end if;
               if Left_In /= 0 then
                  Interfaces.C.Strings.Free (Ver);
                  Rc := Z.Inflate_End (Stream'Unchecked_Access);
                  Free (Out_Ptr);
                  R := (Ok => False, Reason => Trailing_Bytes);
                  return;
               end if;
               Interfaces.C.Strings.Free (Ver);
               Rc := Z.Inflate_End (Stream'Unchecked_Access);
               R := (Ok => True, Data => Out_Ptr);
               return;
            elsif Rc = Z.Z_Buf_Error then
               --  No room left but stream not complete => bomb past
               --  declared size; otherwise truncated input.
               Interfaces.C.Strings.Free (Ver);
               Rc := Z.Inflate_End (Stream'Unchecked_Access);
               if Total >= Interfaces.C.unsigned_long (Data_Len) then
                  Free (Out_Ptr);
                  R := (Ok => False, Reason => Size_Mismatch);
               else
                  Free (Out_Ptr);
                  R := (Ok => False, Reason => Truncated);
               end if;
               return;
            elsif Rc = Z.Z_Ok then
               --  Output full, stream not finished => exceeds bound.
               Interfaces.C.Strings.Free (Ver);
               Rc := Z.Inflate_End (Stream'Unchecked_Access);
               Free (Out_Ptr);
               R := (Ok => False, Reason => Size_Mismatch);
               return;
            else
               Interfaces.C.Strings.Free (Ver);
               Rc := Z.Inflate_End (Stream'Unchecked_Access);
               Free (Out_Ptr);
               --  Z_Data_Error / Z_Mem_Error / Z_Need_Dict etc.
               --  Distinguish short/truncated Buf cases already handled;
               --  checksum/header problems are corrupt data.
               R := (Ok => False, Reason => Corrupt_Data);
               return;
            end if;
         end;
      end;
   end Decode;

end Adacraft.Protocol.Compression;
