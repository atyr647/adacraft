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
   use type Interfaces.Unsigned_64;

   subtype Bytes is P.Octets;

   procedure Pass (Name : String) is
   begin
      Ada.Text_IO.Put_Line ("PASS test_protocol_packet_decoder: " & Name);
   end Pass;

   procedure Require (Condition : Boolean; Name : String) is
   begin
      if not Condition then
         Ada.Text_IO.Put_Line ("FAIL test_protocol_packet_decoder: " & Name);
         Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
         raise Program_Error with Name;
      end if;
   end Require;

   function Append (Left, Right : Bytes) return Bytes is
   begin
      return Left & Right;
   end Append;

   function Append_VarInt
     (Data : Bytes; Value : Interfaces.Integer_32) return Bytes
   is
      Buffer  : Bytes (1 .. 5) := (others => 0);
      Written : Natural := 0;
      Status  : V.Status_Type := V.Buffer_Too_Small;
   begin
      V.Encode (Value, Buffer, Buffer'First, Written, Status);
      Require (Status = V.Ok, "VarInt test encoding");
      return Data & Buffer (1 .. Written);
   end Append_VarInt;

   function Append_VarLong
     (Data : Bytes; Value : Interfaces.Integer_64) return Bytes
   is
      Buffer  : Bytes (1 .. 10) := (others => 0);
      Written : Natural := 0;
      Status  : V.Status_Type := V.Buffer_Too_Small;
   begin
      V.Encode_Varlong (Value, Buffer, Buffer'First, Written, Status);
      Require (Status = V.Ok, "VarLong test encoding");
      return Data & Buffer (1 .. Written);
   end Append_VarLong;

   function Packet (Field_Bytes : Bytes) return Bytes is
   begin
      return Append_VarInt (Bytes'(1 .. 0 => 0), 0) & Field_Bytes;
   end Packet;

   procedure Expect_Reject (Data : Bytes; Kinds : D.Kind_Array; Count : Natural;
                            Name : String) is
      Layout : constant D.Layout := (Count => Count, Kinds => Kinds);
      Result : D.Decode_Result;
   begin
      D.Decode (Data, Layout, Result);
      Require (not Result.Success, Name);
      Pass (Name);
   end Expect_Reject;

   procedure Check_VarInt (Value : Interfaces.Integer_32; Name : String) is
      Data   : constant Bytes := Append_VarInt
        (Append_VarInt (Bytes'(1 .. 0 => 0), 0), Value);
      Layout : constant D.Layout :=
        (Count => 1, Kinds => (1 => D.Kind_VarInt, others => D.Kind_VarInt));
      Result : D.Decode_Result;
   begin
      D.Decode (Data, Layout, Result);
      Require (Result.Success and then Result.Packet_Id = 0
               and then Result.Field_Count = 1
               and then Result.Fields (1).Kind = D.Kind_VarInt
               and then Result.Fields (1).Value_32 = Value, Name);
      Pass (Name);
   end Check_VarInt;

   procedure Check_VarLong (Value : Interfaces.Integer_64; Name : String) is
      Data   : constant Bytes := Append_VarLong
        (Append_VarInt (Bytes'(1 .. 0 => 0), 0), Value);
      Layout : constant D.Layout :=
        (Count => 1, Kinds => (1 => D.Kind_VarLong, others => D.Kind_VarInt));
      Result : D.Decode_Result;
   begin
      D.Decode (Data, Layout, Result);
      Require (Result.Success and then Result.Packet_Id = 0
               and then Result.Fields (1).Kind = D.Kind_VarLong
               and then Result.Fields (1).Value_64 = Value, Name);
      Pass (Name);
   end Check_VarLong;

   procedure Check_Fixed
     (Kind : D.Field_Kind; Value : Interfaces.Integer_64; Name : String)
   is
      Field_Bytes : Bytes (1 .. 8) := (others => 0);
      Width       : Natural := 0;
      Encoded     : Interfaces.Unsigned_64 := Interfaces.Unsigned_64 (Value);
      Layout      : D.Layout :=
        (Count => 1, Kinds => (others => D.Kind_VarInt));
      Result      : D.Decode_Result;
      Data        : Bytes (1 .. 1);
   begin
      case Kind is
         when D.Kind_I8  => Width := 1;
         when D.Kind_I16 => Width := 2;
         when D.Kind_I32 => Width := 4;
         when D.Kind_I64 => Width := 8;
         when others     => Require (False, "invalid fixed-width test kind");
      end case;

      for Index in reverse 1 .. Width loop
         Field_Bytes (Index) := Interfaces.Unsigned_8 (Encoded and 16#FF#);
         Encoded := Interfaces.Shift_Right (Encoded, 8);
      end loop;

      Layout.Kinds (1) := Kind;
      Data := Append_VarInt (Bytes'(1 .. 0 => 0), 0);
      declare
         Payload : constant Bytes := Data & Field_Bytes (1 .. Width);
      begin
         D.Decode (Payload, Layout, Result);
      end;

      Require (Result.Success and then Result.Fields (1).Kind = Kind, Name);
      case Kind is
         when D.Kind_I8 =>
            Require (Interfaces.Integer_64 (Result.Fields (1).Value_8) = Value, Name);
         when D.Kind_I16 =>
            Require (Interfaces.Integer_64 (Result.Fields (1).Value_16) = Value, Name);
         when D.Kind_I32 =>
            Require (Interfaces.Integer_64 (Result.Fields (1).Value_32) = Value, Name);
         when D.Kind_I64 =>
            Require (Result.Fields (1).Value_64 = Value, Name);
         when others =>
            null;
      end case;
      Pass (Name);
   end Check_Fixed;

   procedure Check_Boolean (Value : P.Octet; Expected : Boolean; Name : String) is
      Data   : constant Bytes :=
        Append_VarInt (Bytes'(1 .. 0 => 0), 0) & Bytes'(1 => Value);
      Layout : constant D.Layout :=
        (Count => 1, Kinds => (1 => D.Kind_Boolean, others => D.Kind_VarInt));
      Result : D.Decode_Result;
   begin
      D.Decode (Data, Layout, Result);
      Require (Result.Success and then Result.Fields (1).Boolean_Value = Expected,
               Name);
      Pass (Name);
   end Check_Boolean;

   Empty_Layout : constant D.Layout :=
     (Count => 0, Kinds => (others => D.Kind_VarInt));
begin
   Check_VarInt (0, "VarInt zero");
   Check_VarInt (-1, "VarInt minus one");
   Check_VarInt (Interfaces.Integer_32'First, "VarInt minimum");
   Check_VarInt (Interfaces.Integer_32'Last, "VarInt maximum");

   Check_VarLong (0, "VarLong zero");
   Check_VarLong (-1, "VarLong minus one");
   Check_VarLong (Interfaces.Integer_64'First, "VarLong minimum");
   Check_VarLong (Interfaces.Integer_64'Last, "VarLong maximum");

   Check_Fixed (D.Kind_I8, 0, "I8 zero");
   Check_Fixed (D.Kind_I8, -1, "I8 minus one");
   Check_Fixed (D.Kind_I8, Interfaces.Integer_8'First, "I8 minimum");
   Check_Fixed (D.Kind_I8, Interfaces.Integer_8'Last, "I8 maximum");

   Check_Fixed (D.Kind_I16, 0, "I16 zero");
   Check_Fixed (D.Kind_I16, -1, "I16 minus one");
   Check_Fixed (D.Kind_I16, Interfaces.Integer_16'First, "I16 minimum");
   Check_Fixed (D.Kind_I16, Interfaces.Integer_16'Last, "I16 maximum");

   Check_Fixed (D.Kind_I32, 0, "I32 zero");
   Check_Fixed (D.Kind_I32, -1, "I32 minus one");
   Check_Fixed (D.Kind_I32, Interfaces.Integer_32'First, "I32 minimum");
   Check_Fixed (D.Kind_I32, Interfaces.Integer_32'Last, "I32 maximum");

   Check_Fixed (D.Kind_I64, 0, "I64 zero");
   Check_Fixed (D.Kind_I64, -1, "I64 minus one");
   Check_Fixed (D.Kind_I64, Interfaces.Integer_64'First, "I64 minimum");
   Check_Fixed (D.Kind_I64, Interfaces.Integer_64'Last, "I64 maximum");

   Check_Boolean (0, False, "Boolean false");
   Check_Boolean (1, True, "Boolean true");

   declare
      Data   : Bytes := Append_VarInt (Bytes'(1 .. 0 => 0), 16#2A#);
      Layout : D.Layout :=
        (Count => 4, Kinds => (others => D.Kind_VarInt));
      Result : D.Decode_Result;
   begin
      Data := Append_VarInt (Data, -17);
      Data := Append_VarInt (Data, 3);
      Data := Data & Bytes'(16#41#, 16#42#, 16#43#);
      Data := Data & Bytes'(1 => 1);
      Data := Data & Bytes'(16#FF#, 16#FE#);
      Layout.Kinds (1) := D.Kind_VarInt;
      Layout.Kinds (2) := D.Kind_String;
      Layout.Kinds (3) := D.Kind_Boolean;
      Layout.Kinds (4) := D.Kind_I16;
      D.Decode (Data, Layout, Result);
      Require (Result.Success and then Result.Packet_Id = 16#2A#
               and then Result.Fields (1).Value_32 = -17
               and then Result.Fields (2).String_Length = 3
               and then Result.Strings (Result.Fields (2).String_Offset) = 16#41#
               and then Result.Strings (Result.Fields (2).String_Offset + 1) = 16#42#
               and then Result.Strings (Result.Fields (2).String_Offset + 2) = 16#43#
               and then Result.Fields (3).Boolean_Value
               and then Result.Fields (4).Value_16 = -2,
               "mixed packet");
      Pass ("mixed packet");
   end;

   declare
      Data   : Bytes := Append_VarInt (Bytes'(1 .. 0 => 0), 0);
      Layout : D.Layout :=
        (Count => 1, Kinds => (1 => D.Kind_String, others => D.Kind_VarInt));
      Result : D.Decode_Result;
   begin
      Data := Append_VarInt (Data, 0);
      D.Decode (Data, Layout, Result);
      Require (Result.Success and then Result.Fields (1).String_Length = 0,
               "empty string");
      Pass ("empty string");
   end;

   declare
      Data   : Bytes := Append_VarInt (Bytes'(1 .. 0 => 0), 0);
      Layout : D.Layout :=
        (Count => 1, Kinds => (1 => D.Kind_String, others => D.Kind_VarInt));
      Result : D.Decode_Result;
   begin
      Data := Append_VarInt (Data, D.String_Max);
      for I in 1 .. D.String_Max loop
         Data := Data & Bytes'(1 => 16#41#);
      end loop;
      D.Decode (Data, Layout, Result);
      Require (Result.Success
               and then Result.Fields (1).String_Length = D.String_Max
               and then Result.Strings (1) = 16#41#
               and then Result.Strings (D.String_Max) = 16#41#,
               "maximum string");
      Pass ("maximum string");
   end;

   Expect_Reject (Bytes'(1 .. 0 => 0), Empty_Layout.Kinds, 0, "empty input");
   Expect_Reject (Bytes'(16#80#), Empty_Layout.Kinds, 0, "truncated packet ID");
   Expect_Reject (Bytes'(16#80#, 16#80#, 16#80#, 16#80#, 16#80#),
                  Empty_Layout.Kinds, 0, "overlong packet ID");

   declare
      Data : Bytes := Append_VarInt (Bytes'(1 .. 0 => 0), 0);
   begin
      Expect_Reject (Data & Bytes'(16#80#),
                     (1 => D.Kind_VarInt, others => D.Kind_VarInt), 1,
                     "truncated VarInt field");
      Expect_Reject (Data & Bytes'(16#80#, 16#80#, 16#80#, 16#80#, 16#80#),
                     (1 => D.Kind_VarInt, others => D.Kind_VarInt), 1,
                     "overlong VarInt field");
      Expect_Reject (Data & Bytes'(16#80#, 16#80#, 16#80#, 16#80#,
                                   16#80#, 16#80#, 16#80#, 16#80#,
                                   16#80#, 16#80#),
                     (1 => D.Kind_VarLong, others => D.Kind_VarInt), 1,
                     "overlong VarLong field");
   end;

   declare
      Data : Bytes := Append_VarInt (Bytes'(1 .. 0 => 0), 0);
   begin
      Expect_Reject (Append_VarInt (Data, -1),
                     (1 => D.Kind_String, others => D.Kind_VarInt), 1,
                     "negative string length");
      Expect_Reject (Append_VarInt (Data, D.String_Max + 1),
                     (1 => D.Kind_String, others => D.Kind_VarInt), 1,
                     "string over maximum");
      Expect_Reject (Append_VarInt (Data, 2) & Bytes'(1 => 16#41#),
                     (1 => D.Kind_String, others => D.Kind_VarInt), 1,
                     "string overruns payload");
      Expect_Reject (Data & Bytes'(1 => 2),
                     (1 => D.Kind_Boolean, others => D.Kind_VarInt), 1,
                     "invalid boolean");
      Expect_Reject (Data & Bytes'(1 => 16#AA#),
                     Empty_Layout.Kinds, 0, "trailing byte");
   end;

exception
   when others =>
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
      raise;
end Test_Protocol_Packet_Decoder;
