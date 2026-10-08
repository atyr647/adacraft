with Interfaces;
with Adacraft.Protocol.Frame;
with Adacraft.Protocol.Varnum;

package body Adacraft.Protocol.Packet_Encoder is

   --  Internal capacity helper for field writers.
   --  Precedence: sticky error first, then ordering, then Overflow,
   --  then Body_Too_Long. Sets E.St on failure, Ready = False.
   procedure Reserve
     (E     : in out Encoder;
      Buf   : Byte_Array;
      Count : Natural;
      Ready : out Boolean)
   is
      Cap : Natural;
   begin
      Ready := False;
      if E.St /= Ok then
         return;
      end if;
      if not E.Id_Written then
         E.St := Invalid_Sequence;
         return;
      end if;
      Cap := Buf'Length;
      if Count > Cap - E.Len then
         E.St := Overflow;
         return;
      end if;
      if E.Len + Count > Adacraft.Protocol.Frame.Max_Frame_Body_Length then
         E.St := Body_Too_Long;
         return;
      end if;
      Ready := True;
   end Reserve;

   procedure Start (E : out Encoder) is
   begin
      E.Len := 0;
      E.St := Ok;
      E.Id_Written := False;
   end Start;

   procedure Write_Packet_Id
     (E   : in out Encoder;
      Buf : in out Byte_Array;
      Id  : Interfaces.Integer_32)
   is
      use type Interfaces.Integer_32;
      use type Varnum.Status_Type;
      Staging : Adacraft.Protocol.Octets (1 .. Max_Varint_Bytes) := (others => 0);
      Written : Natural := 0;
      Vs      : Varnum.Status_Type;
      Ready   : Boolean := False;
      Cap     : Natural;
   begin
      if E.St /= Ok then
         return;
      end if;
      if E.Id_Written then
         E.St := Invalid_Sequence;
         return;
      end if;
      if Id < 0 then
         E.St := Invalid_Packet_Id;
         return;
      end if;
      Varnum.Encode (Id, Staging, Staging'First, Written, Vs);
      if Vs /= Varnum.Ok then
         E.St := Overflow;
         return;
      end if;
      Cap := Buf'Length;
      if Written > Cap - E.Len then
         E.St := Overflow;
         return;
      end if;
      if E.Len + Written > Adacraft.Protocol.Frame.Max_Frame_Body_Length then
         E.St := Body_Too_Long;
         return;
      end if;
      Ready := True;
      if Ready then
         for I in 0 .. Written - 1 loop
            Buf (Buf'First + E.Len + I) := Staging (Staging'First + I);
         end loop;
         E.Len := E.Len + Written;
         E.Id_Written := True;
      end if;
   end Write_Packet_Id;

   procedure Write_Boolean
     (E   : in out Encoder;
      Buf : in out Byte_Array;
      V   : Boolean)
   is
      Ready : Boolean := False;
   begin
      Reserve (E, Buf, 1, Ready);
      if not Ready then
         return;
      end if;
      if V then
         Buf (Buf'First + E.Len) := 16#01#;
      else
         Buf (Buf'First + E.Len) := 16#00#;
      end if;
      E.Len := E.Len + 1;
   end Write_Boolean;

   procedure Write_Byte
     (E   : in out Encoder;
      Buf : in out Byte_Array;
      V   : Interfaces.Integer_8)
   is
      Ready : Boolean := False;
      U     : Interfaces.Unsigned_8;
   begin
      Reserve (E, Buf, 1, Ready);
      if not Ready then
         return;
      end if;
      U := Interfaces.Unsigned_8 (V);
      Buf (Buf'First + E.Len) := U;
      E.Len := E.Len + 1;
   end Write_Byte;

   procedure Write_UByte
     (E   : in out Encoder;
      Buf : in out Byte_Array;
      V   : Interfaces.Unsigned_8)
   is
      Ready : Boolean := False;
   begin
      Reserve (E, Buf, 1, Ready);
      if not Ready then
         return;
      end if;
      Buf (Buf'First + E.Len) := V;
      E.Len := E.Len + 1;
   end Write_UByte;

   procedure Write_Short
     (E   : in out Encoder;
      Buf : in out Byte_Array;
      V   : Interfaces.Integer_16)
   is
      use type Interfaces.Unsigned_16;
      Ready : Boolean := False;
      U     : Interfaces.Unsigned_16;
   begin
      Reserve (E, Buf, 2, Ready);
      if not Ready then
         return;
      end if;
      U := Interfaces.Unsigned_16 (V);
      Buf (Buf'First + E.Len) :=
        Interfaces.Unsigned_8 (Interfaces.Shift_Right (U, 8));
      Buf (Buf'First + E.Len + 1) :=
        Interfaces.Unsigned_8 (U and 16#FF#);
      E.Len := E.Len + 2;
   end Write_Short;

   procedure Write_UShort
     (E   : in out Encoder;
      Buf : in out Byte_Array;
      V   : Interfaces.Unsigned_16)
   is
      use type Interfaces.Unsigned_16;
      Ready : Boolean := False;
   begin
      Reserve (E, Buf, 2, Ready);
      if not Ready then
         return;
      end if;
      Buf (Buf'First + E.Len) :=
        Interfaces.Unsigned_8 (Interfaces.Shift_Right (V, 8));
      Buf (Buf'First + E.Len + 1) :=
        Interfaces.Unsigned_8 (V and 16#FF#);
      E.Len := E.Len + 2;
      null;
   end Write_UShort;

   procedure Write_Int
     (E   : in out Encoder;
      Buf : in out Byte_Array;
      V   : Interfaces.Integer_32)
   is
      use type Interfaces.Unsigned_32;
      Ready : Boolean := False;
      U     : Interfaces.Unsigned_32;
   begin
      Reserve (E, Buf, 4, Ready);
      if not Ready then
         return;
      end if;
      U := Interfaces.Unsigned_32 (V);
      Buf (Buf'First + E.Len) :=
        Interfaces.Unsigned_8 (Interfaces.Shift_Right (U, 24));
      Buf (Buf'First + E.Len + 1) :=
        Interfaces.Unsigned_8
          ((Interfaces.Shift_Right (U, 16)) and 16#FF#);
      Buf (Buf'First + E.Len + 2) :=
        Interfaces.Unsigned_8
          ((Interfaces.Shift_Right (U, 8)) and 16#FF#);
      Buf (Buf'First + E.Len + 3) :=
        Interfaces.Unsigned_8 (U and 16#FF#);
      E.Len := E.Len + 4;
   end Write_Int;

   procedure Write_Long
     (E   : in out Encoder;
      Buf : in out Byte_Array;
      V   : Interfaces.Integer_64)
   is
      use type Interfaces.Unsigned_64;
      Ready : Boolean := False;
      U     : Interfaces.Unsigned_64;
   begin
      Reserve (E, Buf, 8, Ready);
      if not Ready then
         return;
      end if;
      U := Interfaces.Unsigned_64 (V);
      Buf (Buf'First + E.Len) :=
        Interfaces.Unsigned_8 (Interfaces.Shift_Right (U, 56));
      Buf (Buf'First + E.Len + 1) :=
        Interfaces.Unsigned_8
          ((Interfaces.Shift_Right (U, 48)) and 16#FF#);
      Buf (Buf'First + E.Len + 2) :=
        Interfaces.Unsigned_8
          ((Interfaces.Shift_Right (U, 40)) and 16#FF#);
      Buf (Buf'First + E.Len + 3) :=
        Interfaces.Unsigned_8
          ((Interfaces.Shift_Right (U, 32)) and 16#FF#);
      Buf (Buf'First + E.Len + 4) :=
        Interfaces.Unsigned_8
          ((Interfaces.Shift_Right (U, 24)) and 16#FF#);
      Buf (Buf'First + E.Len + 5) :=
        Interfaces.Unsigned_8
          ((Interfaces.Shift_Right (U, 16)) and 16#FF#);
      Buf (Buf'First + E.Len + 6) :=
        Interfaces.Unsigned_8
          ((Interfaces.Shift_Right (U, 8)) and 16#FF#);
      Buf (Buf'First + E.Len + 7) :=
        Interfaces.Unsigned_8 (U and 16#FF#);
      E.Len := E.Len + 8;
   end Write_Long;

   procedure Write_VarInt
     (E   : in out Encoder;
      Buf : in out Byte_Array;
      V   : Interfaces.Integer_32)
   is
      pragma Unreferenced (Buf);
      pragma Unreferenced (V);
   begin
      if E.St /= Ok then
         return;
      end if;
      if not E.Id_Written then
         E.St := Invalid_Sequence;
         return;
      end if;
      null;
   end Write_VarInt;

   procedure Write_VarLong
     (E   : in out Encoder;
      Buf : in out Byte_Array;
      V   : Interfaces.Integer_64)
   is
      use type Varnum.Status_Type;
      Staging : Adacraft.Protocol.Octets (1 .. Max_Varlong_Bytes) := (others => 0);
      Written : Natural := 0;
      Vs      : Varnum.Status_Type;
      Ready   : Boolean := False;
   begin
      if E.St /= Ok then
         return;
      end if;
      if not E.Id_Written then
         E.St := Invalid_Sequence;
         return;
      end if;
      Varnum.Encode_Varlong (V, Staging, Staging'First, Written, Vs);
      if Vs /= Varnum.Ok then
         E.St := Overflow;
         return;
      end if;
      Reserve (E, Buf, Written, Ready);
      if not Ready then
         return;
      end if;
      for I in 0 .. Written - 1 loop
         Buf (Buf'First + E.Len + I) := Staging (Staging'First + I);
      end loop;
      E.Len := E.Len + Written;
   end Write_VarLong;

   procedure Write_String
     (E         : in out Encoder;
      Buf       : in out Byte_Array;
      Bytes     : Byte_Array;
      Max_Bytes : Natural)
   is
      pragma Unreferenced (Buf);
      pragma Unreferenced (Bytes);
      pragma Unreferenced (Max_Bytes);
   begin
      if E.St /= Ok then
         return;
      end if;
      if not E.Id_Written then
         E.St := Invalid_Sequence;
         return;
      end if;
      null;
   end Write_String;

   procedure Write_Bytes
     (E   : in out Encoder;
      Buf : in out Byte_Array;
      B   : Byte_Array)
   is
      Ready : Boolean := False;
   begin
      if E.St /= Ok then
         return;
      end if;
      if not E.Id_Written then
         E.St := Invalid_Sequence;
         return;
      end if;
      Reserve (E, Buf, B'Length, Ready);
      if not Ready then
         return;
      end if;
      for I in 0 .. B'Length - 1 loop
         Buf (Buf'First + E.Len + I) := B (B'First + I);
      end loop;
      E.Len := E.Len + B'Length;
   end Write_Bytes;

   function Body_Length (E : Encoder) return Natural is
   begin
      return E.Len;
   end Body_Length;

   function Status_Of (E : Encoder) return Status is
   begin
      return E.St;
   end Status_Of;

   procedure Finish
     (E         : in     Encoder;
      Buf       : in     Byte_Array;
      Body_Last :    out Natural;
      S         :    out Status)
   is
   begin
      Body_Last := Buf'First - 1;
      if E.St /= Ok then
         S := E.St;
         return;
      end if;
      if not E.Id_Written then
         S := Invalid_Sequence;
         return;
      end if;
      if E.Len = 0 then
         S := Invalid_Sequence;
         return;
      end if;
      if E.Len > Buf'Length then
         S := Overflow;
         return;
      end if;
      Body_Last := Buf'First + E.Len - 1;
      S := Ok;
   end Finish;

   procedure Frame
     (E       : in     Encoder;
      Buf     : in     Byte_Array;
      Out_Buf :    out Byte_Array;
      Out_Last :   out Natural;
      S       :    out Status)
   is
      use type Ada.Streams.Stream_Element_Offset;
      Need : Natural;
   begin
      Out_Last := Out_Buf'First - 1;
      if E.St /= Ok then
         S := E.St;
         return;
      end if;
      if not E.Id_Written then
         S := Invalid_Sequence;
         return;
      end if;
      if E.Len = 0 then
         S := Invalid_Sequence;
         return;
      end if;
      if E.Len > Buf'Length then
         S := Overflow;
         return;
      end if;
      Need := E.Len + Adacraft.Protocol.Frame.Max_Frame_Prefix_Bytes;
      if Out_Buf'Length < Need then
         S := Overflow;
         return;
      end if;
      declare
         Len_Off : constant Ada.Streams.Stream_Element_Offset :=
           Ada.Streams.Stream_Element_Offset (E.Len);
         Out_Len : constant Ada.Streams.Stream_Element_Offset :=
           Ada.Streams.Stream_Element_Offset (Out_Buf'Length);
         Payload : Ada.Streams.Stream_Element_Array (1 .. Len_Off);
         Output  : Ada.Streams.Stream_Element_Array (1 .. Out_Len);
         Enc_Last : Ada.Streams.Stream_Element_Offset;
         Enc_St   : Adacraft.Protocol.Frame.Encode_Status;
      begin
         for I in 0 .. E.Len - 1 loop
            Payload
              (Ada.Streams.Stream_Element_Offset (I + 1)) :=
              Ada.Streams.Stream_Element
                (Buf (Buf'First + I));
         end loop;
         Adacraft.Protocol.Frame.Encode
           (Payload => Payload,
            Output  => Output,
            Last    => Enc_Last,
            Status  => Enc_St);
         case Enc_St is
            when Adacraft.Protocol.Frame.Ok =>
               for I in 1 .. Enc_Last loop
                  Out_Buf
                    (Out_Buf'First + Natural (I - 1)) :=
                    Interfaces.Unsigned_8 (Output (I));
               end loop;
               Out_Last :=
                 Out_Buf'First + Natural (Enc_Last) - 1;
               S := Ok;
            when Adacraft.Protocol.Frame.Body_Too_Long =>
               S := Body_Too_Long;
            when Adacraft.Protocol.Frame.Output_Too_Small =>
               S := Overflow;
         end case;
      end;
   end Frame;

end Adacraft.Protocol.Packet_Encoder;
