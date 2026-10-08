with Ada.Command_Line;
with Ada.Text_IO;
with Interfaces;
with Adacraft.Protocol;
with Adacraft.Protocol.Packet_Decoder;
with Adacraft.Protocol.Varnum;

procedure Test_Protocol_Packet_Decoder is
   package P renames Adacraft.Protocol;
   package D renames Adacraft.Protocol.Packet_Decoder;
   package V renames Adacraft.Protocol.Varnum;

   use type Interfaces.Integer_8;
   use type Interfaces.Integer_16;
   use type Interfaces.Integer_32;
   use type Interfaces.Integer_64;
   use type Interfaces.Unsigned_8;
   use type Interfaces.Unsigned_16;
   use type Interfaces.Unsigned_32;
   use type Interfaces.Unsigned_64;
   use type V.Status_Type;
   use type D.Decode_Status;
   use type D.Field_Kind;

   Failures : Natural := 0;

   procedure Check (Cond : Boolean; Name : String) is
   begin
      if Cond then
         Ada.Text_IO.Put_Line ("PASS test_protocol_packet_decoder: " & Name);
      else
         Ada.Text_IO.Put_Line ("FAIL test_protocol_packet_decoder: " & Name);
         Failures := Failures + 1;
      end if;
   end Check;

   --  Working buffer builders (avoid null-array concatenation issues).
   Buf : P.Octets (1 .. 40_000) := (others => 0);
   Len : Natural := 0;

   procedure Reset is
   begin
      Len := 0;
   end Reset;

   procedure Append_Byte (B : Interfaces.Unsigned_8) is
   begin
      Len := Len + 1;
      Buf (Len) := B;
   end Append_Byte;

   procedure Append_Bytes (Data : P.Octets) is
   begin
      for I in Data'Range loop
         Len := Len + 1;
         Buf (Len) := Data (I);
      end loop;
   end Append_Bytes;

   procedure Append_VarInt (Value : Interfaces.Integer_32) is
      Tmp     : P.Octets (1 .. 5) := (others => 0);
      Written : Natural := 0;
      St      : V.Status_Type := V.Buffer_Too_Small;
   begin
      V.Encode (Value, Tmp, Tmp'First, Written, St);
      if St /= V.Ok then
         Ada.Text_IO.Put_Line ("FAIL test_protocol_packet_decoder: varint encode");
         Failures := Failures + 1;
         return;
      end if;
      Append_Bytes (Tmp (1 .. Written));
   end Append_VarInt;

   procedure Append_VarLong (Value : Interfaces.Integer_64) is
      Tmp     : P.Octets (1 .. 10) := (others => 0);
      Written : Natural := 0;
      St      : V.Status_Type := V.Buffer_Too_Small;
   begin
      V.Encode_Varlong (Value, Tmp, Tmp'First, Written, St);
      if St /= V.Ok then
         Ada.Text_IO.Put_Line ("FAIL test_protocol_packet_decoder: varlong encode");
         Failures := Failures + 1;
         return;
      end if;
      Append_Bytes (Tmp (1 .. Written));
   end Append_VarLong;

   procedure Append_BE (U : Interfaces.Unsigned_64; N : Positive) is
      Vv : Interfaces.Unsigned_64 := U;
      T  : P.Octets (1 .. 8) := (others => 0);
   begin
      for I in reverse 1 .. N loop
         T (I) := Interfaces.Unsigned_8 (Vv mod 256);
         Vv := Vv / 256;
      end loop;
      Append_Bytes (T (1 .. N));
   end Append_BE;

   function Cur return P.Octets is
   begin
      return Buf (1 .. Len);
   end Cur;

   function Mk_Layout (K : D.Field_Kind) return D.Field_Layout is
      L : D.Field_Layout;
   begin
      L.Length := 1;
      L.Kinds (1) := K;
      return L;
   end Mk_Layout;

   procedure Check_VarInt (Value : Interfaces.Integer_32; Name : String) is
      L  : D.Field_Layout;
      Id : Interfaces.Integer_32 := -999;
      F  : D.Decoded_Fields;
      St : D.Decode_Status := D.Rejected;
   begin
      Reset;
      Append_VarInt (0);  --  packet id
      Append_VarInt (Value);
      L := Mk_Layout (D.Kind_VarInt);
      D.Decode (Cur, L, Id, F, St);
      Check (St = D.Success and then Id = 0
             and then F.Length = 1
             and then F.Values (1).Kind = D.Kind_VarInt
             and then F.Values (1).VarInt_Value = Value, Name);
   end Check_VarInt;

   procedure Check_VarLong (Value : Interfaces.Integer_64; Name : String) is
      L  : D.Field_Layout;
      Id : Interfaces.Integer_32 := -999;
      F  : D.Decoded_Fields;
      St : D.Decode_Status := D.Rejected;
   begin
      Reset;
      Append_VarInt (0);
      Append_VarLong (Value);
      L := Mk_Layout (D.Kind_VarLong);
      D.Decode (Cur, L, Id, F, St);
      Check (St = D.Success and then Id = 0
             and then F.Length = 1
             and then F.Values (1).Kind = D.Kind_VarLong
             and then F.Values (1).VarLong_Value = Value, Name);
   end Check_VarLong;

   procedure Check_Byte (Value : Interfaces.Integer_8; Name : String) is
      L  : D.Field_Layout;
      Id : Interfaces.Integer_32 := -999;
      F  : D.Decoded_Fields;
      St : D.Decode_Status := D.Rejected;
   begin
      Reset;
      Append_VarInt (0);
      Append_Byte (Interfaces.Unsigned_8 (Integer (Value) mod 256));
      L := Mk_Layout (D.Kind_Byte);
      D.Decode (Cur, L, Id, F, St);
      Check (St = D.Success and then Id = 0
             and then F.Length = 1
             and then F.Values (1).Kind = D.Kind_Byte
             and then F.Values (1).Byte_Value = Value, Name);
   end Check_Byte;

   procedure Check_Short (Value : Interfaces.Integer_16; Name : String) is
      L  : D.Field_Layout;
      Id : Interfaces.Integer_32 := -999;
      F  : D.Decoded_Fields;
      St : D.Decode_Status := D.Rejected;
      U  : constant Interfaces.Unsigned_16 :=
        Interfaces.Unsigned_16 (Integer (Value) mod 65_536);
   begin
      Reset;
      Append_VarInt (0);
      Append_BE (Interfaces.Unsigned_64 (U), 2);
      L := Mk_Layout (D.Kind_Short);
      D.Decode (Cur, L, Id, F, St);
      Check (St = D.Success and then Id = 0
             and then F.Length = 1
             and then F.Values (1).Kind = D.Kind_Short
             and then F.Values (1).Short_Value = Value, Name);
   end Check_Short;

   procedure Check_Int (Value : Interfaces.Integer_32; Name : String) is
      L  : D.Field_Layout;
      Id : Interfaces.Integer_32 := -999;
      F  : D.Decoded_Fields;
      St : D.Decode_Status := D.Rejected;
      U  : constant Interfaces.Unsigned_32 :=
        Interfaces.Unsigned_32 (Long_Long_Integer (Value) mod 4_294_967_296);
   begin
      Reset;
      Append_VarInt (0);
      Append_BE (Interfaces.Unsigned_64 (U), 4);
      L := Mk_Layout (D.Kind_Int);
      D.Decode (Cur, L, Id, F, St);
      Check (St = D.Success and then Id = 0
             and then F.Length = 1
             and then F.Values (1).Kind = D.Kind_Int
             and then F.Values (1).Int_Value = Value, Name);
   end Check_Int;

   procedure Check_Long (Value : Interfaces.Integer_64; Name : String) is
      L  : D.Field_Layout;
      Id : Interfaces.Integer_32 := -999;
      F  : D.Decoded_Fields;
      St : D.Decode_Status := D.Rejected;
      --  Wrap signed Long bits into modular without a raising conversion.
      function To_U64 (V : Interfaces.Integer_64) return Interfaces.Unsigned_64 is
         B : P.Octets (1 .. 8) := (others => 0);
         X : Interfaces.Integer_64 := V;
      begin
         for I in reverse 1 .. 8 loop
            B (I) := Interfaces.Unsigned_8 (Integer (X mod 256));
            X := X / 256;
         end loop;
         declare
            U : Interfaces.Unsigned_64 := 0;
         begin
            for J in B'Range loop
               U := U * 256 + Interfaces.Unsigned_64 (B (J));
            end loop;
            return U;
         end;
      end To_U64;
      U  : constant Interfaces.Unsigned_64 := To_U64 (Value);
   begin
      Reset;
      Append_VarInt (0);
      Append_BE (U, 8);
      L := Mk_Layout (D.Kind_Long);
      D.Decode (Cur, L, Id, F, St);
      Check (St = D.Success and then Id = 0
             and then F.Length = 1
             and then F.Values (1).Kind = D.Kind_Long
             and then F.Values (1).Long_Value = Value, Name);
   end Check_Long;

begin
   Check_VarInt (0, "VarInt 0");
   Check_VarInt (-1, "VarInt -1");
   Check_VarInt (Interfaces.Integer_32'First, "VarInt min");
   Check_VarInt (Interfaces.Integer_32'Last, "VarInt max");

   Check_VarLong (0, "VarLong 0");
   Check_VarLong (-1, "VarLong -1");
   Check_VarLong (Interfaces.Integer_64'First, "VarLong min");
   Check_VarLong (Interfaces.Integer_64'Last, "VarLong max");

   Check_Byte (0, "Byte 0");
   Check_Byte (-1, "Byte -1");
   Check_Byte (Interfaces.Integer_8'First, "Byte min");
   Check_Byte (Interfaces.Integer_8'Last, "Byte max");

   Check_Short (0, "Short 0");
   Check_Short (-1, "Short -1");
   Check_Short (Interfaces.Integer_16'First, "Short min");
   Check_Short (Interfaces.Integer_16'Last, "Short max");

   Check_Int (0, "Int 0");
   Check_Int (-1, "Int -1");
   Check_Int (Interfaces.Integer_32'First, "Int min");
   Check_Int (Interfaces.Integer_32'Last, "Int max");

   Check_Long (0, "Long 0");
   Check_Long (-1, "Long -1");
   Check_Long (Interfaces.Integer_64'First, "Long min");
   Check_Long (Interfaces.Integer_64'Last, "Long max");

   --  String empty
   declare
      L  : D.Field_Layout;
      Id : Interfaces.Integer_32 := -999;
      F  : D.Decoded_Fields;
      St : D.Decode_Status := D.Rejected;
   begin
      Reset;
      Append_VarInt (7);
      Append_VarInt (0);
      L := Mk_Layout (D.Kind_String);
      D.Decode (Cur, L, Id, F, St);
      Check (St = D.Success and then Id = 7
             and then F.Length = 1
             and then F.Values (1).Kind = D.Kind_String
             and then D.Bounded_Strings.Length (F.Values (1).String_Value) = 0,
             "String empty");
   end;

   --  String exactly String_Max bytes
   declare
      L  : D.Field_Layout;
      Id : Interfaces.Integer_32 := -999;
      F  : D.Decoded_Fields;
      St : D.Decode_Status := D.Rejected;
   begin
      Reset;
      Append_VarInt (7);
      Append_VarInt (Interfaces.Integer_32 (D.String_Max));
      for I in 1 .. D.String_Max loop
         Len := Len + 1;
         Buf (Len) := 16#41#;
      end loop;
      L := Mk_Layout (D.Kind_String);
      D.Decode (Cur, L, Id, F, St);
      Check (St = D.Success and then Id = 7
             and then F.Length = 1
             and then F.Values (1).Kind = D.Kind_String
             and then D.Bounded_Strings.Length (F.Values (1).String_Value)
               = D.String_Max
             and then D.Bounded_Strings.Element (F.Values (1).String_Value, 1) = 'A'
             and then D.Bounded_Strings.Element
               (F.Values (1).String_Value, D.String_Max) = 'A',
             "String max length");
   end;

   --  Boolean 0x00 / 0x01
   declare
      L  : D.Field_Layout;
      Id : Interfaces.Integer_32 := -999;
      F  : D.Decoded_Fields;
      St : D.Decode_Status := D.Rejected;
   begin
      Reset;
      Append_VarInt (0);
      Append_Byte (16#00#);
      L := Mk_Layout (D.Kind_Boolean);
      D.Decode (Cur, L, Id, F, St);
      Check (St = D.Success and then F.Values (1).Boolean_Value = False,
             "Boolean false");
      Reset;
      Append_VarInt (0);
      Append_Byte (16#01#);
      D.Decode (Cur, L, Id, F, St);
      Check (St = D.Success and then F.Values (1).Boolean_Value = True,
             "Boolean true");
   end;

   --  Mixed packet: packet id + several kinds
   declare
      L  : D.Field_Layout;
      Id : Interfaces.Integer_32 := -999;
      F  : D.Decoded_Fields;
      St : D.Decode_Status := D.Rejected;
   begin
      Reset;
      Append_VarInt (42);
      Append_VarInt (-123);
      Append_VarLong (-9_999_999_999);
      Append_Byte (16#FE#);  --  -2 as byte
      Append_BE (65_236, 2);  --  -300 as Short
      Append_BE (4_294_897_296, 4);  --  -70000 as Int
      Append_BE (18_446_744_073_709_551_614, 8);  --  -2 as Long
      Append_VarInt (3);
      Append_Byte (16#41#);
      Append_Byte (16#42#);
      Append_Byte (16#43#);
      Append_Byte (16#01#);
      L.Length := 8;
      L.Kinds (1) := D.Kind_VarInt;
      L.Kinds (2) := D.Kind_VarLong;
      L.Kinds (3) := D.Kind_Byte;
      L.Kinds (4) := D.Kind_Short;
      L.Kinds (5) := D.Kind_Int;
      L.Kinds (6) := D.Kind_Long;
      L.Kinds (7) := D.Kind_String;
      L.Kinds (8) := D.Kind_Boolean;
      D.Decode (Cur, L, Id, F, St);
      Check (St = D.Success and then Id = 42, "mixed packet id");
      if St = D.Success and then F.Length = 8 then
         Check (F.Values (1).VarInt_Value = -123, "mixed VarInt");
         Check (F.Values (2).VarLong_Value = -9_999_999_999, "mixed VarLong");
         Check (F.Values (3).Byte_Value = -2, "mixed Byte");
         Check (F.Values (4).Short_Value = -300, "mixed Short");
         Check (F.Values (5).Int_Value = -70000, "mixed Int");
         Check (F.Values (6).Long_Value = -2, "mixed Long");
         Check (D.Bounded_Strings.Length (F.Values (7).String_Value) = 3
                and then D.Bounded_Strings.To_String (F.Values (7).String_Value) = "ABC",
                "mixed String");
         Check (F.Values (8).Boolean_Value = True, "mixed Boolean");
      else
         Check (False, "mixed field count");
      end if;
   end;

   if Failures = 0 then
      Ada.Text_IO.Put_Line ("test_protocol_packet_decoder: PASS");
   else
      Ada.Text_IO.Put_Line ("test_protocol_packet_decoder: FAIL");
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
   end if;
end Test_Protocol_Packet_Decoder;
