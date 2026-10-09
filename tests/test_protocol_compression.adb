with Ada.Command_Line;
with Ada.Text_IO;
with Interfaces;
with Interfaces.C;
with Interfaces.C.Strings;
with System;
with Adacraft.Protocol;
with Adacraft.Protocol.Compression;
with Adacraft.Protocol.Varnum;
with Adacraft.Protocol.Zlib;

procedure Test_Protocol_Compression is
   package Z renames Adacraft.Protocol.Zlib;
   package C renames Adacraft.Protocol.Compression;
   package V renames Adacraft.Protocol.Varnum;
   use Adacraft.Protocol;
   use type Interfaces.C.int;
   use type Interfaces.C.unsigned_long;
   use type Interfaces.C.unsigned;
   use type Interfaces.Integer_32;
   use type Interfaces.Unsigned_32;
   use type Interfaces.Unsigned_8;
   use type V.Status_Type;
   use type C.Reject_Reason;

   Failures : Natural := 0;

   procedure Check (Condition : Boolean; Name : String) is
   begin
      if not Condition then
         Failures := Failures + 1;
         Ada.Text_IO.Put_Line ("FAIL: " & Name);
      end if;
   end Check;

   subtype Stream_Box is Z.Z_Stream_Access;

   procedure Round_Trip (Name : String; Input : String) is
      use Interfaces.C.Strings;
      In_Buf  : aliased Interfaces.C.char_array (0 .. 511) :=
        (others => Interfaces.C.nul);
      Out_Buf : aliased Interfaces.C.char_array (0 .. 511) :=
        (others => Interfaces.C.nul);
      Back    : aliased Interfaces.C.char_array (0 .. 511) :=
        (others => Interfaces.C.nul);
      S       : Stream_Box := new Z.Z_Stream;
      Ver     : chars_ptr := New_String (Z.Zlib_Version);
      Rc      : Interfaces.C.int;
   begin
      for I in Input'Range loop
         In_Buf (Interfaces.C.size_t (I - Input'First)) :=
           Interfaces.C.char'Val (Character'Pos (Input (I)));
      end loop;
      Z.Init_Stream (S.all);
      Z.Set_Input (S.all, In_Buf'Address,
                   Interfaces.C.unsigned (Input'Length));
      Z.Set_Output (S.all, Out_Buf'Address, 512);
      Rc := Z.Deflate_Init (S, Z.Z_Default_Compression, Ver,
                            Z.Stream_Size);
      Check (Rc = Z.Z_Ok, Name & " deflate init");
      if Rc /= Z.Z_Ok then
         Free (Ver);
         return;
      end if;
      Rc := Z.Deflate (S, Z.Z_Finish);
      Check (Rc = Z.Z_Stream_End, Name & " deflate finish");
      declare
         Produced : constant Interfaces.C.unsigned_long := Z.Total_Out (S.all);
         Rc_End   : constant Interfaces.C.int := Z.Deflate_End (S);
      begin
         Check (Rc_End = Z.Z_Ok, Name & " deflate end");
         Check ((Produced > 0) = (Input'Length > 0),
                Name & " produced bytes");
         Z.Init_Stream (S.all);
         Z.Set_Input (S.all, Out_Buf'Address,
                      Interfaces.C.unsigned (Produced));
         Z.Set_Output (S.all, Back'Address, 512);
         Rc := Z.Inflate_Init (S, Ver, Z.Stream_Size);
         Check (Rc = Z.Z_Ok, Name & " inflate init");
         if Rc = Z.Z_Ok then
            Rc := Z.Inflate (S, Z.Z_Finish);
            Check (Rc = Z.Z_Stream_End, Name & " inflate finish");
            Check (Z.Total_Out (S.all) =
                     Interfaces.C.unsigned_long (Input'Length),
                   Name & " inflate size");
            Check (Z.Avail_In (S.all) = 0, Name & " no trailing bytes");
            Rc := Z.Inflate_End (S);
            Check (Rc = Z.Z_Ok, Name & " inflate end");
         end if;
      end;
      Free (Ver);
   end Round_Trip;

   --  Fill a heap buffer with a deterministic pseudo-random pattern.
   procedure Fill_Pattern (Buf : in out Octets) is
      Acc : Interfaces.Unsigned_32 := 16#1234_5678#;
   begin
      for I in Buf'Range loop
         Acc := Acc * 16#0100_0193# + 16#57BC_7EA5#;
         Buf (I) := Octet ((Acc / 256) mod 256);
      end loop;
   end Fill_Pattern;

   function Equal_Octets (A, B : Octets) return Boolean is
   begin
      if A'Length /= B'Length then
         return False;
      end if;
      for I in 1 .. A'Length loop
         if A (A'First + I - 1) /= B (B'First + I - 1) then
            return False;
         end if;
      end loop;
      return True;
   end Equal_Octets;

   --  Decode the leading VarInt of Buf; returns value/consumed on Ok.
   procedure Leading_Varint
     (Buf      : Octets;
      Value    : out Interfaces.Integer_32;
      Consumed : out Natural;
      Ok       : out Boolean)
   is
      St : V.Status_Type;
   begin
      V.Decode (Buf, Buf'First, Value, Consumed, St);
      Ok := (St = V.Ok);
   end Leading_Varint;

   --  Raw inflate of Comp (zlib bytes) into heap output; used for T3
   --  reverse check that codec output is standard zlib.
   procedure Raw_Inflate
     (Comp      : Octets;
      Expect_Len : Natural;
      Out_Data  : out C.Byte_Array_Access;
      Ok        : out Boolean)
   is
      Ver    : Interfaces.C.Strings.chars_ptr;
      Stream : aliased Z.Z_Stream;
      Rc     : Interfaces.C.int;
   begin
      Out_Data := null;
      Ok := False;
      Out_Data := new Octets (1 .. Natural'Max (Expect_Len, 1));
      Ver := Interfaces.C.Strings.New_String (Z.Zlib_Version);
      Z.Init_Stream (Stream);
      if Comp'Length = 0 then
         Z.Set_Input (Stream, System.Null_Address, 0);
      else
         Z.Set_Input
           (Stream, Comp (Comp'First)'Address,
            Interfaces.C.unsigned (Comp'Length));
      end if;
      if Expect_Len = 0 then
         Z.Set_Output (Stream, Out_Data (1)'Address, 0);
      else
         Z.Set_Output
           (Stream, Out_Data (1)'Address,
            Interfaces.C.unsigned (Expect_Len));
      end if;
      Rc := Z.Inflate_Init (Stream'Unchecked_Access, Ver, Z.Stream_Size);
      if Rc /= Z.Z_Ok then
         Interfaces.C.Strings.Free (Ver);
         Rc := Z.Inflate_End (Stream'Unchecked_Access);
         C.Free (Out_Data);
         return;
      end if;
      Rc := Z.Inflate (Stream'Unchecked_Access, Z.Z_Finish);
      if Rc = Z.Z_Stream_End
        and then Z.Total_Out (Stream) =
          Interfaces.C.unsigned_long (Expect_Len)
        and then Z.Avail_In (Stream) = 0
      then
         Ok := True;
      else
         C.Free (Out_Data);
         Ok := False;
      end if;
      Interfaces.C.Strings.Free (Ver);
      Rc := Z.Inflate_End (Stream'Unchecked_Access);
   end Raw_Inflate;

   --  T1: one threshold-256 case for a given length.
   procedure T1_Case (Len : Natural) is
      Name    : constant String := "T1 len" & Natural'Image (Len);
      In_Ptr  : C.Byte_Array_Access := new Octets (1 .. Natural'Max (Len, 1));
      Enc     : C.Encode_Result;
      Dec     : C.Decode_Result;
      Val     : Interfaces.Integer_32 := 0;
      Cons    : Natural := 0;
      Vok     : Boolean := False;
   begin
      if Len = 0 then
         C.Free (In_Ptr);
         In_Ptr := new Octets (1 .. 0);
      else
         --  Only first Len bytes are significant; when Len > 0 the
         --  allocation is exactly Len bytes.
         if In_Ptr.all'Length /= Len then
            C.Free (In_Ptr);
            In_Ptr := new Octets (1 .. Len);
         end if;
         Fill_Pattern (In_Ptr.all);
      end if;

      C.Encode (Threshold => 256, Uncompressed => In_Ptr.all, R => Enc);
      Check (Enc.Ok, Name & " encode ok");
      if not Enc.Ok then
         Check (False, Name & " encode reason");
         C.Free (In_Ptr);
         return;
      end if;

      Leading_Varint (Enc.Data.all, Val, Cons, Vok);
      Check (Vok, Name & " data-length varint ok");

      if Len <= 255 then
         --  Pass-through: Data Length 0 + identity.
         Check (Vok and then Val = 0 and then Cons = 1,
                Name & " passthrough header");
         Check (Enc.Data.all'Length = Len + 1, Name & " passthrough size");
         if Enc.Data.all'Length = Len + 1 then
            declare
               Tail : Octets (1 .. Len);
            begin
               for I in 1 .. Len loop
                  Tail (I) := Enc.Data (I + 1);
               end loop;
               Check (Equal_Octets (Tail, In_Ptr.all),
                      Name & " passthrough identity");
            end;
         end if;
      else
         --  Compressed: Data Length = input len, standard zlib suffix.
         Check (Vok and then Val = Interfaces.Integer_32 (Len),
                Name & " compressed header");
         Check (Enc.Data.all'Length > Cons, Name & " has zlib bytes");
         if Vok and then Val = Interfaces.Integer_32 (Len) then
            declare
               Suffix_Len : constant Natural :=
                 Enc.Data.all'Length - Cons;
               Suffix : Octets (1 .. Suffix_Len);
               Back   : C.Byte_Array_Access := null;
               Rok    : Boolean := False;
            begin
               for I in 1 .. Suffix_Len loop
                  Suffix (I) := Enc.Data (Cons + I);
               end loop;
               Raw_Inflate (Suffix, Len, Back, Rok);
               Check (Rok, Name & " reverse inflate ok");
               if Rok then
                  Check (Equal_Octets (Back.all, In_Ptr.all),
                         Name & " reverse inflate bytes");
               end if;
               C.Free (Back);
            end;
         end if;
      end if;

      --  Round-trip through the codec decoder.
      C.Decode (Threshold => 256, Input => Enc.Data.all, R => Dec);
      Check (Dec.Ok, Name & " decode round-trip ok");
      if Dec.Ok then
         Check (Equal_Octets (Dec.Data.all, In_Ptr.all),
                Name & " round-trip bytes");
      else
         Check (False, Name & " decode failed");
      end if;

      C.Free (In_Ptr);
      C.Free (Enc);
      C.Free (Dec);
   end T1_Case;

   procedure T2_Threshold_Zero is
      In_Buf : Octets (1 .. 1) := (1 => 16#AB#);
      Enc    : C.Encode_Result;
      Dec    : C.Decode_Result;
      Val    : Interfaces.Integer_32 := 0;
      Cons   : Natural := 0;
      Vok    : Boolean := False;
   begin
      C.Encode (Threshold => 0, Uncompressed => In_Buf, R => Enc);
      Check (Enc.Ok, "T2 encode ok");
      if not Enc.Ok then
         return;
      end if;
      Leading_Varint (Enc.Data.all, Val, Cons, Vok);
      Check (Vok and then Val = 1, "T2 data length = 1");
      C.Decode (Threshold => 0, Input => Enc.Data.all, R => Dec);
      Check (Dec.Ok, "T2 decode ok");
      if Dec.Ok then
         Check (Dec.Data.all'Length = 1
                and then Dec.Data (1) = 16#AB#, "T2 round-trip byte");
      end if;
      C.Free (Enc);
      C.Free (Dec);
   end T2_Threshold_Zero;

   procedure T3_Known_Vector is
      --  Fixed reference zlib stream for payload "ABC" using a stored
      --  (uncompressed) deflate block, decodable by any conforming
      --  inflater: 78 01 | 01 | 03 00 | FC FF | 41 42 43 | 01 8D 00 C7.
      Zlib_ABC : constant Octets (1 .. 14) :=
        (16#78#, 16#01#, 16#01#, 16#03#, 16#00#, 16#FC#, 16#FF#,
         16#41#, 16#42#, 16#43#, 16#01#, 16#8D#, 16#00#, 16#C7#);
      Expect : constant Octets (1 .. 3) :=
        (16#41#, 16#42#, 16#43#);
      C_Body : Octets (1 .. 15);
      Dec    : C.Decode_Result;
      Back   : C.Byte_Array_Access := null;
      Rok    : Boolean := False;
   begin
      C_Body (1) := 16#03#;
      for I in Zlib_ABC'Range loop
         C_Body (I + 1) := Zlib_ABC (I);
      end loop;
      C.Decode (Threshold => 0, Input => C_Body, R => Dec);
      Check (Dec.Ok, "T3 decode ok");
      if Dec.Ok then
         Check (Equal_Octets (Dec.Data.all, Expect), "T3 decode bytes");
      end if;
      C.Free (Dec);

      --  Reverse: raw-inflate the same suffix directly via zlib.
      Raw_Inflate (Zlib_ABC, 3, Back, Rok);
      Check (Rok, "T3 raw inflate ok");
      if Rok then
         Check (Equal_Octets (Back.all, Expect), "T3 raw inflate bytes");
      end if;
      C.Free (Back);

      --  Reverse: codec-compress "ABC" then raw-inflate the suffix.
      declare
         Enc   : C.Encode_Result;
         Val   : Interfaces.Integer_32 := 0;
         Cons  : Natural := 0;
         Vok   : Boolean := False;
         Back2 : C.Byte_Array_Access := null;
         Rok2  : Boolean := False;
      begin
         C.Encode (Threshold => 0, Uncompressed => Expect, R => Enc);
         Check (Enc.Ok, "T3 encode ok");
         if Enc.Ok then
            Leading_Varint (Enc.Data.all, Val, Cons, Vok);
            Check (Vok and then Val = 3, "T3 encode header = 3");
            declare
               Suffix_Len : constant Natural :=
                 Enc.Data.all'Length - Cons;
               Suffix : Octets (1 .. Suffix_Len);
            begin
               for I in 1 .. Suffix_Len loop
                  Suffix (I) := Enc.Data (Cons + I);
               end loop;
               Raw_Inflate (Suffix, 3, Back2, Rok2);
               Check (Rok2, "T3 encode reverse inflate ok");
               if Rok2 then
                  Check (Equal_Octets (Back2.all, Expect),
                         "T3 encode reverse bytes");
               end if;
               C.Free (Back2);
            end;
         end if;
         C.Free (Enc);
      end;
   end T3_Known_Vector;

begin
   Check (Z.Stream_Size > 0, "stream size positive");
   Check (Z.Compress_Bound (0) > 0, "compress bound zero");
   Check (Z.Compress_Bound (100) >= 100, "compress bound grows");
   Round_Trip ("hello", "hello world");
   Round_Trip ("empty", "");

   T1_Case (0);
   T1_Case (1);
   T1_Case (255);
   T1_Case (256);
   T1_Case (257);
   T1_Case (1_048_576);
   T2_Threshold_Zero;
   T3_Known_Vector;

   if Failures = 0 then
      Ada.Text_IO.Put_Line ("compression tests passed");
   else
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
   end if;
end Test_Protocol_Compression;
