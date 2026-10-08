with Ada.Command_Line;
with Ada.Text_IO;
with Ada.Unchecked_Conversion;
with Interfaces;
with Adacraft.Protocol;
with Adacraft.Protocol.Varnum;
with Adacraft.Protocol.Packet_Decoder;

procedure Test_Protocol_Packet_Decoder is
   package V renames Adacraft.Protocol.Varnum;
   package D renames Adacraft.Protocol.Packet_Decoder;
   use Adacraft.Protocol;
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

   procedure Check (Condition : Boolean; Name : String) is
   begin
      if not Condition then
         Failures := Failures + 1;
         Ada.Text_IO.Put_Line ("FAIL: " & Name);
      end if;
   end Check;

   type Field_Array_Access is access D.Field_Array;

   --  Scratch buffer for building payloads (heap to avoid stack pressure).
   type Scratch_Access is access Octets;

   procedure Append_VarInt
     (Value : Interfaces.Integer_32;
      Buf   : in out Octets;
      Pos   : in out Positive)
   is
      Tmp : Octets (1 .. 5) := [others => 0];
      W   : Natural := 0;
      S   : V.Status_Type;
   begin
      V.Encode (Value, Tmp, 1, W, S);
      if S /= V.Ok then
         Check (False, "helper Append_VarInt encode ok");
         return;
      end if;
      for I in 1 .. W loop
         Buf (Pos) := Tmp (I);
         Pos := Pos + 1;
      end loop;
   end Append_VarInt;

   procedure Append_VarLong
     (Value : Interfaces.Integer_64;
      Buf   : in out Octets;
      Pos   : in out Positive)
   is
      Tmp : Octets (1 .. 10) := [others => 0];
      W   : Natural := 0;
      S   : V.Status_Type;
   begin
      V.Encode_Varlong (Value, Tmp, 1, W, S);
      if S /= V.Ok then
         Check (False, "helper Append_VarLong encode ok");
         return;
      end if;
      for I in 1 .. W loop
         Buf (Pos) := Tmp (I);
         Pos := Pos + 1;
      end loop;
   end Append_VarLong;

   procedure Append_Byte (Buf : in out Octets; Pos : in out Positive; B : Octet) is
   begin
      Buf (Pos) := B;
      Pos := Pos + 1;
   end Append_Byte;

   procedure Append_U16BE (Buf : in out Octets; Pos : in out Positive; U : Interfaces.Unsigned_16) is
   begin
      Buf (Pos) := Octet (Interfaces.Shift_Right (U, 8) and 16#FF#);
      Buf (Pos + 1) := Octet (U and 16#FF#);
      Pos := Pos + 2;
   end Append_U16BE;

   procedure Append_U32BE (Buf : in out Octets; Pos : in out Positive; U : Interfaces.Unsigned_32) is
   begin
      for I in 0 .. 3 loop
         Buf (Pos + I) :=
           Octet (Interfaces.Shift_Right (U, (3 - I) * 8) and 16#FF#);
      end loop;
      Pos := Pos + 4;
   end Append_U32BE;

   procedure Append_U64BE (Buf : in out Octets; Pos : in out Positive; U : Interfaces.Unsigned_64) is
   begin
      for I in 0 .. 7 loop
         Buf (Pos + I) :=
           Octet (Interfaces.Shift_Right (U, (7 - I) * 8) and 16#FF#);
      end loop;
      Pos := Pos + 8;
   end Append_U64BE;

   function To_U16 (V : Interfaces.Integer_16) return Interfaces.Unsigned_16 is
      function C is new Ada.Unchecked_Conversion
        (Interfaces.Integer_16, Interfaces.Unsigned_16);
   begin
      return C (V);
   end To_U16;

   function To_U32 (V : Interfaces.Integer_32) return Interfaces.Unsigned_32 is
      function C is new Ada.Unchecked_Conversion
        (Interfaces.Integer_32, Interfaces.Unsigned_32);
   begin
      return C (V);
   end To_U32;

   function To_U64 (V : Interfaces.Integer_64) return Interfaces.Unsigned_64 is
      function C is new Ada.Unchecked_Conversion
        (Interfaces.Integer_64, Interfaces.Unsigned_64);
   begin
      return C (V);
   end To_U64;

   function To_U8 (V : Interfaces.Integer_8) return Interfaces.Unsigned_8 is
      function C is new Ada.Unchecked_Conversion
        (Interfaces.Integer_8, Interfaces.Unsigned_8);
   begin
      return C (V);
   end To_U8;

   function To_I8 (U : Interfaces.Unsigned_8) return Interfaces.Integer_8 is
      function C is new Ada.Unchecked_Conversion
        (Interfaces.Unsigned_8, Interfaces.Integer_8);
   begin
      return C (U);
   end To_I8;

   function Single_Layout (K : D.Field_Kind) return D.Layout_Type is
      L : D.Layout_Type;
   begin
      L.Count := 1;
      L.Kinds (1) := K;
      return L;
   end Single_Layout;

   procedure Check_VarInt (Value : Interfaces.Integer_32; Name : String) is
      Buf_Ptr : Scratch_Access := new Octets (1 .. 16);
      Fields_P : Field_Array_Access := new D.Field_Array;
      Pos : Positive := 1;
      Pid : Interfaces.Integer_32 := 0;
      Cnt : Natural := 0;
      St  : D.Decode_Status := D.Rejected;
   begin
      Append_VarInt (7, Buf_Ptr.all, Pos);
      Append_VarInt (Value, Buf_Ptr.all, Pos);
      D.Decode (Buf_Ptr.all (1 .. Pos - 1), Single_Layout (D.VarInt),
                Pid, Fields_P.all, Cnt, St);
      Check (St = D.Success, Name & " status");
      Check (Pid = 7, Name & " packet id");
      Check (Cnt = 1, Name & " count");
      if St = D.Success and then Cnt = 1 then
         Check (Fields_P.all (1).Kind = D.VarInt, Name & " kind");
         Check (Fields_P.all (1).VarInt_Value = Value, Name & " value");
      end if;
   end Check_VarInt;

   procedure Check_VarLong (Value : Interfaces.Integer_64; Name : String) is
      Buf_Ptr : Scratch_Access := new Octets (1 .. 32);
      Fields_P : Field_Array_Access := new D.Field_Array;
      Pos : Positive := 1;
      Pid : Interfaces.Integer_32 := 0;
      Cnt : Natural := 0;
      St  : D.Decode_Status := D.Rejected;
   begin
      Append_VarInt (7, Buf_Ptr.all, Pos);
      Append_VarLong (Value, Buf_Ptr.all, Pos);
      D.Decode (Buf_Ptr.all (1 .. Pos - 1), Single_Layout (D.VarLong),
                Pid, Fields_P.all, Cnt, St);
      Check (St = D.Success, Name & " status");
      Check (Pid = 7, Name & " packet id");
      Check (Cnt = 1, Name & " count");
      if St = D.Success and then Cnt = 1 then
         Check (Fields_P.all (1).Kind = D.VarLong, Name & " kind");
         Check (Fields_P.all (1).VarLong_Value = Value, Name & " value");
      end if;
   end Check_VarLong;

   procedure Check_Bool (Value : Boolean; Name : String) is
      Buf_Ptr : Scratch_Access := new Octets (1 .. 16);
      Fields_P : Field_Array_Access := new D.Field_Array;
      Pos : Positive := 1;
      Pid : Interfaces.Integer_32 := 0;
      Cnt : Natural := 0;
      St  : D.Decode_Status := D.Rejected;
   begin
      Append_VarInt (3, Buf_Ptr.all, Pos);
      if Value then
         Append_Byte (Buf_Ptr.all, Pos, 16#01#);
      else
         Append_Byte (Buf_Ptr.all, Pos, 16#00#);
      end if;
      D.Decode (Buf_Ptr.all (1 .. Pos - 1), Single_Layout (D.Boolean),
                Pid, Fields_P.all, Cnt, St);
      Check (St = D.Success, Name & " status");
      Check (Pid = 3, Name & " packet id");
      Check (Cnt = 1, Name & " count");
      if St = D.Success and then Cnt = 1 then
         Check (Fields_P.all (1).Kind = D.Boolean, Name & " kind");
         Check (Fields_P.all (1).Bool_Value = Value, Name & " value");
      end if;
   end Check_Bool;

   procedure Check_Byte (Value : Interfaces.Integer_8; Name : String) is
      Buf_Ptr : Scratch_Access := new Octets (1 .. 16);
      Fields_P : Field_Array_Access := new D.Field_Array;
      Pos : Positive := 1;
      Pid : Interfaces.Integer_32 := 0;
      Cnt : Natural := 0;
      St  : D.Decode_Status := D.Rejected;
      U : Interfaces.Unsigned_8;
   begin
      U := To_U8 (Value);
      Append_VarInt (11, Buf_Ptr.all, Pos);
      Append_Byte (Buf_Ptr.all, Pos, U);
      D.Decode (Buf_Ptr.all (1 .. Pos - 1), Single_Layout (D.Byte),
                Pid, Fields_P.all, Cnt, St);
      Check (St = D.Success, Name & " status");
      Check (Pid = 11, Name & " packet id");
      if St = D.Success and then Cnt = 1 then
         Check (Fields_P.all (1).Byte_Value = Value, Name & " value");
      end if;
   end Check_Byte;

   procedure Check_UByte (Value : Interfaces.Unsigned_8; Name : String) is
      Buf_Ptr : Scratch_Access := new Octets (1 .. 16);
      Fields_P : Field_Array_Access := new D.Field_Array;
      Pos : Positive := 1;
      Pid : Interfaces.Integer_32 := 0;
      Cnt : Natural := 0;
      St  : D.Decode_Status := D.Rejected;
   begin
      Append_VarInt (11, Buf_Ptr.all, Pos);
      Append_Byte (Buf_Ptr.all, Pos, Value);
      D.Decode (Buf_Ptr.all (1 .. Pos - 1), Single_Layout (D.Unsigned_Byte),
                Pid, Fields_P.all, Cnt, St);
      Check (St = D.Success, Name & " status");
      if St = D.Success and then Cnt = 1 then
         Check (Fields_P.all (1).UByte_Value = Value, Name & " value");
      end if;
   end Check_UByte;

   procedure Check_Short (Value : Interfaces.Integer_16; Name : String) is
      Buf_Ptr : Scratch_Access := new Octets (1 .. 16);
      Fields_P : Field_Array_Access := new D.Field_Array;
      Pos : Positive := 1;
      Pid : Interfaces.Integer_32 := 0;
      Cnt : Natural := 0;
      St  : D.Decode_Status := D.Rejected;
   begin
      Append_VarInt (11, Buf_Ptr.all, Pos);
      Append_U16BE (Buf_Ptr.all, Pos, To_U16 (Value));
      D.Decode (Buf_Ptr.all (1 .. Pos - 1), Single_Layout (D.Short),
                Pid, Fields_P.all, Cnt, St);
      Check (St = D.Success, Name & " status");
      if St = D.Success and then Cnt = 1 then
         Check (Fields_P.all (1).Short_Value = Value, Name & " value");
      end if;
   end Check_Short;

   procedure Check_UShort (Value : Interfaces.Unsigned_16; Name : String) is
      Buf_Ptr : Scratch_Access := new Octets (1 .. 16);
      Fields_P : Field_Array_Access := new D.Field_Array;
      Pos : Positive := 1;
      Pid : Interfaces.Integer_32 := 0;
      Cnt : Natural := 0;
      St  : D.Decode_Status := D.Rejected;
   begin
      Append_VarInt (11, Buf_Ptr.all, Pos);
      Append_U16BE (Buf_Ptr.all, Pos, Value);
      D.Decode (Buf_Ptr.all (1 .. Pos - 1), Single_Layout (D.Unsigned_Short),
                Pid, Fields_P.all, Cnt, St);
      Check (St = D.Success, Name & " status");
      if St = D.Success and then Cnt = 1 then
         Check (Fields_P.all (1).UShort_Value = Value, Name & " value");
      end if;
   end Check_UShort;

   procedure Check_Int (Value : Interfaces.Integer_32; Name : String) is
      Buf_Ptr : Scratch_Access := new Octets (1 .. 16);
      Fields_P : Field_Array_Access := new D.Field_Array;
      Pos : Positive := 1;
      Pid : Interfaces.Integer_32 := 0;
      Cnt : Natural := 0;
      St  : D.Decode_Status := D.Rejected;
   begin
      Append_VarInt (11, Buf_Ptr.all, Pos);
      Append_U32BE (Buf_Ptr.all, Pos, To_U32 (Value));
      D.Decode (Buf_Ptr.all (1 .. Pos - 1), Single_Layout (D.Int),
                Pid, Fields_P.all, Cnt, St);
      Check (St = D.Success, Name & " status");
      if St = D.Success and then Cnt = 1 then
         Check (Fields_P.all (1).Int_Value = Value, Name & " value");
      end if;
   end Check_Int;

   procedure Check_Long (Value : Interfaces.Integer_64; Name : String) is
      Buf_Ptr : Scratch_Access := new Octets (1 .. 32);
      Fields_P : Field_Array_Access := new D.Field_Array;
      Pos : Positive := 1;
      Pid : Interfaces.Integer_32 := 0;
      Cnt : Natural := 0;
      St  : D.Decode_Status := D.Rejected;
   begin
      Append_VarInt (11, Buf_Ptr.all, Pos);
      Append_U64BE (Buf_Ptr.all, Pos, To_U64 (Value));
      D.Decode (Buf_Ptr.all (1 .. Pos - 1), Single_Layout (D.Long),
                Pid, Fields_P.all, Cnt, St);
      Check (St = D.Success, Name & " status");
      if St = D.Success and then Cnt = 1 then
         Check (Fields_P.all (1).Long_Value = Value, Name & " value");
      end if;
   end Check_Long;

   procedure Check_String_Empty is
      Buf_Ptr : Scratch_Access := new Octets (1 .. 16);
      Fields_P : Field_Array_Access := new D.Field_Array;
      Pos : Positive := 1;
      Pid : Interfaces.Integer_32 := 0;
      Cnt : Natural := 0;
      St  : D.Decode_Status := D.Rejected;
   begin
      Append_VarInt (5, Buf_Ptr.all, Pos);
      Append_VarInt (0, Buf_Ptr.all, Pos);
      D.Decode (Buf_Ptr.all (1 .. Pos - 1), Single_Layout (D.String),
                Pid, Fields_P.all, Cnt, St);
      Check (St = D.Success, "string empty status");
      Check (Pid = 5, "string empty packet id");
      Check (Cnt = 1, "string empty count");
      if St = D.Success and then Cnt = 1 then
         Check (Fields_P.all (1).Kind = D.String, "string empty kind");
         Check (Fields_P.all (1).String_Len = 0, "string empty len");
      end if;
   end Check_String_Empty;

   procedure Check_String_Max is
      Total : constant Positive := 1 + 5 + D.String_Max + 8;
      Buf_Ptr : Scratch_Access := new Octets (1 .. Total);
      Fields_P : Field_Array_Access := new D.Field_Array;
      Pos : Positive := 1;
      Pid : Interfaces.Integer_32 := 0;
      Cnt : Natural := 0;
      St  : D.Decode_Status := D.Rejected;
      Same : Boolean := True;
   begin
      Append_VarInt (9, Buf_Ptr.all, Pos);
      Append_VarInt (Interfaces.Integer_32 (D.String_Max), Buf_Ptr.all, Pos);
      for I in 1 .. D.String_Max loop
         Buf_Ptr.all (Pos) := 16#41#;
         Pos := Pos + 1;
      end loop;
      D.Decode (Buf_Ptr.all (1 .. Pos - 1), Single_Layout (D.String),
                Pid, Fields_P.all, Cnt, St);
      Check (St = D.Success, "string max status");
      Check (Pid = 9, "string max packet id");
      Check (Cnt = 1, "string max count");
      if St = D.Success and then Cnt = 1 then
         Check (Fields_P.all (1).String_Len = D.String_Max, "string max len");
         for I in 1 .. D.String_Max loop
            if Fields_P.all (1).String_Data (I) /= 16#41# then
               Same := False;
               exit;
            end if;
         end loop;
         Check (Same, "string max bytes");
      end if;
   end Check_String_Max;

   procedure Check_String_Small is
      Buf_Ptr : Scratch_Access := new Octets (1 .. 32);
      Fields_P : Field_Array_Access := new D.Field_Array;
      Pos : Positive := 1;
      Pid : Interfaces.Integer_32 := 0;
      Cnt : Natural := 0;
      St  : D.Decode_Status := D.Rejected;
   begin
      Append_VarInt (5, Buf_Ptr.all, Pos);
      Append_VarInt (3, Buf_Ptr.all, Pos);
      Append_Byte (Buf_Ptr.all, Pos, 16#68#);
      Append_Byte (Buf_Ptr.all, Pos, 16#69#);
      Append_Byte (Buf_Ptr.all, Pos, 16#21#);
      D.Decode (Buf_Ptr.all (1 .. Pos - 1), Single_Layout (D.String),
                Pid, Fields_P.all, Cnt, St);
      Check (St = D.Success, "string small status");
      if St = D.Success and then Cnt = 1 then
         Check (Fields_P.all (1).String_Len = 3, "string small len");
         Check (Fields_P.all (1).String_Data (1) = 16#68#
                and then Fields_P.all (1).String_Data (2) = 16#69#
                and then Fields_P.all (1).String_Data (3) = 16#21#,
                "string small bytes");
      end if;
   end Check_String_Small;

   procedure Check_Mixed is
      Buf_Ptr : Scratch_Access := new Octets (1 .. 256);
      Fields_P : Field_Array_Access := new D.Field_Array;
      Pos : Positive := 1;
      Pid : Interfaces.Integer_32 := 0;
      Cnt : Natural := 0;
      St  : D.Decode_Status := D.Rejected;
      L : D.Layout_Type;
      Exp_I32 : Interfaces.Integer_32 := -12_345;
      Exp_I64 : Interfaces.Integer_64 := -9_876_543_210;
      Exp_B : Interfaces.Integer_8 := -12;
      Exp_UB : Interfaces.Unsigned_8 := 200;
      Exp_S : Interfaces.Integer_16 := -12_345;
      Exp_US : Interfaces.Unsigned_16 := 60_000;
      Exp_I : Interfaces.Integer_32 := -123_456_789;
      Exp_L : Interfaces.Integer_64 := -123_456_789_012_345_678;
      UB_Raw : Interfaces.Unsigned_8;
   begin
      L.Count := 10;
      L.Kinds (1) := D.VarInt;
      L.Kinds (2) := D.VarLong;
      L.Kinds (3) := D.String;
      L.Kinds (4) := D.Boolean;
      L.Kinds (5) := D.Byte;
      L.Kinds (6) := D.Unsigned_Byte;
      L.Kinds (7) := D.Short;
      L.Kinds (8) := D.Unsigned_Short;
      L.Kinds (9) := D.Int;
      L.Kinds (10) := D.Long;
      Append_VarInt (42, Buf_Ptr.all, Pos);
      Append_VarInt (Exp_I32, Buf_Ptr.all, Pos);
      Append_VarLong (Exp_I64, Buf_Ptr.all, Pos);
      Append_VarInt (2, Buf_Ptr.all, Pos);
      Append_Byte (Buf_Ptr.all, Pos, 16#41#);
      Append_Byte (Buf_Ptr.all, Pos, 16#42#);
      Append_Byte (Buf_Ptr.all, Pos, 16#01#);
      Append_Byte (Buf_Ptr.all, Pos, To_U8 (Exp_B));
      Append_Byte (Buf_Ptr.all, Pos, Exp_UB);
      Append_U16BE (Buf_Ptr.all, Pos, To_U16 (Exp_S));
      Append_U16BE (Buf_Ptr.all, Pos, Exp_US);
      Append_U32BE (Buf_Ptr.all, Pos, To_U32 (Exp_I));
      Append_U64BE (Buf_Ptr.all, Pos, To_U64 (Exp_L));
      D.Decode (Buf_Ptr.all (1 .. Pos - 1), L, Pid, Fields_P.all, Cnt, St);
      Check (St = D.Success, "mixed status");
      Check (Pid = 42, "mixed packet id");
      Check (Cnt = 10, "mixed count");
      if St = D.Success and then Cnt = 10 then
         Check (Fields_P.all (1).VarInt_Value = Exp_I32, "mixed varint");
         Check (Fields_P.all (2).VarLong_Value = Exp_I64, "mixed varlong");
         Check (Fields_P.all (3).String_Len = 2
                and then Fields_P.all (3).String_Data (1) = 16#41#
                and then Fields_P.all (3).String_Data (2) = 16#42#,
                "mixed string");
         Check (Fields_P.all (4).Bool_Value = True, "mixed bool");
         Check (Fields_P.all (5).Byte_Value = Exp_B, "mixed byte");
         Check (Fields_P.all (6).UByte_Value = Exp_UB, "mixed ubyte");
         Check (Fields_P.all (7).Short_Value = Exp_S, "mixed short");
         Check (Fields_P.all (8).UShort_Value = Exp_US, "mixed ushort");
         Check (Fields_P.all (9).Int_Value = Exp_I, "mixed int");
         Check (Fields_P.all (10).Long_Value = Exp_L, "mixed long");
      end if;
   end Check_Mixed;

begin
   Check_VarInt (0, "varint 0");
   Check_VarInt (-1, "varint -1");
   Check_VarInt (Interfaces.Integer_32'First, "varint first");
   Check_VarInt (Interfaces.Integer_32'Last, "varint last");
   Check_VarLong (0, "varlong 0");
   Check_VarLong (-1, "varlong -1");
   Check_VarLong (Interfaces.Integer_64'First, "varlong first");
   Check_VarLong (Interfaces.Integer_64'Last, "varlong last");
   Check_String_Empty;
   Check_String_Small;
   Check_String_Max;
   Check_Bool (False, "bool false");
   Check_Bool (True, "bool true");
   Check_Byte (0, "byte 0");
   Check_Byte (-1, "byte -1");
   Check_Byte (Interfaces.Integer_8'First, "byte first");
   Check_Byte (Interfaces.Integer_8'Last, "byte last");
   Check_UByte (0, "ubyte 0");
   Check_UByte (Interfaces.Unsigned_8'First, "ubyte first");
   Check_UByte (Interfaces.Unsigned_8'Last, "ubyte last");
   Check_Short (0, "short 0");
   Check_Short (-1, "short -1");
   Check_Short (Interfaces.Integer_16'First, "short first");
   Check_Short (Interfaces.Integer_16'Last, "short last");
   Check_UShort (0, "ushort 0");
   Check_UShort (Interfaces.Unsigned_16'First, "ushort first");
   Check_UShort (Interfaces.Unsigned_16'Last, "ushort last");
   Check_Int (0, "int 0");
   Check_Int (-1, "int -1");
   Check_Int (Interfaces.Integer_32'First, "int first");
   Check_Int (Interfaces.Integer_32'Last, "int last");
   Check_Long (0, "long 0");
   Check_Long (-1, "long -1");
   Check_Long (Interfaces.Integer_64'First, "long first");
   Check_Long (Interfaces.Integer_64'Last, "long last");
   Check_Mixed;
   if Failures = 0 then
      Ada.Text_IO.Put_Line ("test_protocol_packet_decoder PASS");
   else
      Ada.Text_IO.Put_Line ("test_protocol_packet_decoder FAIL:" &
                            Natural'Image (Failures));
      Ada.Command_Line.Set_Exit_Status (1);
   end if;
end Test_Protocol_Packet_Decoder;
