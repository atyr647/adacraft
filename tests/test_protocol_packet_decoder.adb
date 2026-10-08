with Ada.Command_Line;
with Ada.Text_IO;
with Interfaces;
with Adacraft.Protocol;
with Adacraft.Protocol.Packet_Decoder;
with Adacraft.Protocol.Varnum;

procedure Test_Protocol_Packet_Decoder is
   package D renames Adacraft.Protocol.Packet_Decoder;
   package V renames Adacraft.Protocol.Varnum;

   use type Interfaces.Integer_8;
   use type Interfaces.Integer_16;
   use type Interfaces.Integer_32;
   use type Interfaces.Integer_64;
   use type Interfaces.Unsigned_8;
   use type Interfaces.Unsigned_16;
   use type Interfaces.Unsigned_64;
   use type D.Decode_Status;
   use type D.Field_Kind;
   use type V.Status_Type;

   subtype Octets is Adacraft.Protocol.Octets;
   subtype I32 is Interfaces.Integer_32;
   subtype I64 is Interfaces.Integer_64;
   subtype U64 is Interfaces.Unsigned_64;

   Failures : Natural := 0;

   procedure Check (Condition : Boolean; Name : String) is
   begin
      if not Condition then
         Failures := Failures + 1;
         Ada.Text_IO.Put_Line ("FAIL packet decoder: " & Name);
      end if;
   end Check;

   Buffer : Octets (1 .. D.String_Max + 128) := (others => 0);
   Last   : Natural := 0;

   procedure Decode_Payload
     (Payload     : Octets;
      Layout      : D.Layout_Type;
      Status      : out D.Decode_Status;
      Packet_Id   : out I32;
      Fields      : out D.Field_Array;
      Field_Count : out Natural)
   is
      Decoder_Payload : D.Byte_Array (Payload'Range);
   begin
      for I in Payload'Range loop
         Decoder_Payload (I) := Payload (I);
      end loop;
      D.Decode
        (Decoder_Payload, Layout, Status, Packet_Id, Fields, Field_Count);
   end Decode_Payload;

   procedure Reset is
   begin
      Last := 0;
   end Reset;

   procedure Append (Value : Adacraft.Protocol.Octet) is
   begin
      Last := Last + 1;
      Buffer (Last) := Value;
   end Append;

   procedure Append_VarInt (Value : I32) is
      Written : Natural;
      Status  : V.Status_Type;
   begin
      V.Encode (Value, Buffer, Last + 1, Written, Status);
      Check (Status = V.Ok, "VarInt encode");
      Last := Last + Written;
   end Append_VarInt;

   procedure Append_VarLong (Value : I64) is
      Written : Natural;
      Status  : V.Status_Type;
   begin
      V.Encode_Varlong (Value, Buffer, Last + 1, Written, Status);
      Check (Status = V.Ok, "VarLong encode");
      Last := Last + Written;
   end Append_VarLong;

   procedure Append_BE (Value : U64; Width : Positive) is
   begin
      for I in reverse 0 .. Width - 1 loop
         Append (Adacraft.Protocol.Octet
           (Interfaces.Shift_Right (Value, I * 8) and 16#FF#));
      end loop;
   end Append_BE;

   procedure Start_Packet (Id : I32) is
   begin
      Reset;
      Append_VarInt (Id);
   end Start_Packet;

   procedure Decode_And_Check
     (Layout : D.Layout_Type; Id : I32; Name : String)
   is
      Status : D.Decode_Status;
      Packet_Id : I32;
      Fields : D.Field_Array (1 .. D.Max_Fields);
      Count : Natural;
   begin
      D.Decode (D.Byte_Array (Buffer (1 .. Last)), Layout, Status, Packet_Id, Fields, Count);
      Check (Status = D.Success, Name & " status");
      Check (Packet_Id = Id, Name & " packet id");
      Check (Count = Layout'Length, Name & " field count");
      for I in 1 .. Layout'Length loop
         Check (Fields (I).Kind = Layout (Layout'First + I - 1),
                Name & " field kind" & Integer'Image (I));
      end loop;
   end Decode_And_Check;

   procedure Verify_VarInt (Value : I32; Name : String) is
      Layout : constant D.Layout_Type (1 .. 1) := (1 => D.VarInt);
      Status : D.Decode_Status;
      Id : I32;
      Fields : D.Field_Array (1 .. D.Max_Fields);
      Count : Natural;
   begin
      Start_Packet (0);
      Append_VarInt (Value);
      Decode_Payload (Buffer (1 .. Last), Layout, Status, Id, Fields, Count);
      Check (Status = D.Success and then Id = 0 and then Count = 1
             and then Fields (1).Kind = D.VarInt
             and then Fields (1).VarInt_Value = Value, Name);
   end Verify_VarInt;

   procedure Verify_VarLong (Value : I64; Name : String) is
      Layout : constant D.Layout_Type (1 .. 1) := (1 => D.VarLong);
      Status : D.Decode_Status;
      Id : I32;
      Fields : D.Field_Array (1 .. D.Max_Fields);
      Count : Natural;
   begin
      Start_Packet (0);
      Append_VarLong (Value);
      Decode_Payload (Buffer (1 .. Last), Layout, Status, Id, Fields, Count);
      Check (Status = D.Success and then Id = 0 and then Count = 1
             and then Fields (1).Kind = D.VarLong
             and then Fields (1).VarLong_Value = Value, Name);
   end Verify_VarLong;

   procedure Verify_Fixed
     (Kind : D.Field_Kind; Value : I64; Width : Positive; Name : String)
   is
      Layout : constant D.Layout_Type (1 .. 1) := (1 => Kind);
      Status : D.Decode_Status;
      Id : I32;
      Fields : D.Field_Array (1 .. D.Max_Fields);
      Count : Natural;
      Bits : U64;
   begin
      Start_Packet (0);
      if Value < 0 then
         Bits := U64'Last - U64 (-(Value + 1));
      else
         Bits := U64 (Value);
      end if;
      Append_BE (Bits, Width);
      Decode_Payload (Buffer (1 .. Last), Layout, Status, Id, Fields, Count);
      Check (Status = D.Success and then Id = 0 and then Count = 1,
             Name & " result");
      if Status = D.Success and then Count = 1 then
         Check (Fields (1).Kind = Kind, Name & " kind");
         case Kind is
            when D.Byte =>
               Check (I64 (Fields (1).Byte_Value) = Value, Name & " value");
            when D.Short =>
               Check (I64 (Fields (1).Short_Value) = Value, Name & " value");
            when D.Int =>
               Check (I64 (Fields (1).Int_Value) = Value, Name & " value");
            when D.Long =>
               Check (Fields (1).Long_Value = Value, Name & " value");
            when others =>
               Check (False, Name & " invalid signed kind");
         end case;
      end if;
   end Verify_Fixed;

   procedure Verify_Unsigned
     (Kind : D.Field_Kind; Value : U64; Width : Positive; Name : String)
   is
      Layout : constant D.Layout_Type (1 .. 1) := (1 => Kind);
      Status : D.Decode_Status;
      Id : I32;
      Fields : D.Field_Array (1 .. D.Max_Fields);
      Count : Natural;
   begin
      Start_Packet (0);
      Append_BE (Value, Width);
      Decode_Payload (Buffer (1 .. Last), Layout, Status, Id, Fields, Count);
      Check (Status = D.Success and then Id = 0 and then Count = 1,
             Name & " result");
      if Status = D.Success and then Count = 1 then
         Check (Fields (1).Kind = Kind, Name & " kind");
         case Kind is
            when D.Unsigned_Byte =>
               Check (U64 (Fields (1).UByte_Value) = Value, Name & " value");
            when D.Unsigned_Short =>
               Check (U64 (Fields (1).UShort_Value) = Value, Name & " value");
            when others =>
               Check (False, Name & " invalid unsigned kind");
         end case;
      end if;
   end Verify_Unsigned;

   procedure Verify_Boolean
     (Value : Boolean; Wire : Adacraft.Protocol.Octet; Name : String)
   is
      Layout : constant D.Layout_Type (1 .. 1) := (1 => D.Boolean_Field);
      Status : D.Decode_Status;
      Id : I32;
      Fields : D.Field_Array (1 .. D.Max_Fields);
      Count : Natural;
   begin
      Start_Packet (0);
      Append (Wire);
      Decode_Payload (Buffer (1 .. Last), Layout, Status, Id, Fields, Count);
      Check (Status = D.Success and then Id = 0 and then Count = 1
             and then Fields (1).Kind = D.Boolean_Field
             and then Fields (1).Bool_Value = Value, Name);
   end Verify_Boolean;

   procedure Verify_String (Length : Natural; Name : String) is
      Layout : constant D.Layout_Type (1 .. 1) := (1 => D.String_Field);
      Status : D.Decode_Status;
      Id : I32;
      Fields : D.Field_Array (1 .. D.Max_Fields);
   begin
      Start_Packet (0);
      Append_VarInt (I32 (Length));
      if Length > 0 then
         for I in 0 .. Length - 1 loop
            Append (Adacraft.Protocol.Octet (I mod 256));
         end loop;
      end if;
      declare
         Count : Natural;
      begin
         Decode_Payload (Buffer (1 .. Last), Layout, Status, Id, Fields, Count);
         Check (Status = D.Success and then Id = 0 and then Count = 1
                and then Fields (1).Kind = D.String_Field
                and then Fields (1).Str_Len = Length, Name & " result");
         if Status = D.Success and then Count = 1 then
            if Length > 0 then
               for I in 0 .. Length - 1 loop
                  Check (Fields (1).Str_Data (I) =
                           Adacraft.Protocol.Octet (I mod 256),
                         Name & " byte" & Integer'Image (I));
               end loop;
            end if;
         end if;
      end;
   end Verify_String;

begin
   Verify_VarInt (0, "VarInt zero");
   Verify_VarInt (-1, "VarInt minus one");
   Verify_VarInt (I32'First, "VarInt first");
   Verify_VarInt (I32'Last, "VarInt last");

   Verify_VarLong (0, "VarLong zero");
   Verify_VarLong (-1, "VarLong minus one");
   Verify_VarLong (I64'First, "VarLong first");
   Verify_VarLong (I64'Last, "VarLong last");

   Verify_Fixed (D.Byte, 0, 1, "Byte zero");
   Verify_Fixed (D.Byte, -1, 1, "Byte minus one");
   Verify_Fixed (D.Byte, -128, 1, "Byte minimum");
   Verify_Fixed (D.Byte, 127, 1, "Byte maximum");
   Verify_Fixed (D.Short, 0, 2, "Short zero");
   Verify_Fixed (D.Short, -1, 2, "Short minus one");
   Verify_Fixed (D.Short, -32_768, 2, "Short minimum");
   Verify_Fixed (D.Short, 32_767, 2, "Short maximum");
   Verify_Fixed (D.Int, 0, 4, "Int zero");
   Verify_Fixed (D.Int, -1, 4, "Int minus one");
   Verify_Fixed (D.Int, I64 (I32'First), 4, "Int minimum");
   Verify_Fixed (D.Int, I64 (I32'Last), 4, "Int maximum");
   Verify_Fixed (D.Long, 0, 8, "Long zero");
   Verify_Fixed (D.Long, -1, 8, "Long minus one");
   Verify_Fixed (D.Long, I64'First, 8, "Long minimum");
   Verify_Fixed (D.Long, I64'Last, 8, "Long maximum");

   Verify_Unsigned (D.Unsigned_Byte, 0, 1, "Unsigned byte zero");
   Verify_Unsigned (D.Unsigned_Byte, 255, 1, "Unsigned byte maximum");
   Verify_Unsigned (D.Unsigned_Short, 0, 2, "Unsigned short zero");
   Verify_Unsigned (D.Unsigned_Short, 65_535, 2, "Unsigned short maximum");

   Verify_String (0, "empty string");
   Verify_String (D.String_Max, "maximum string");

   Verify_Boolean (False, 16#00#, "Boolean false");
   Verify_Boolean (True, 16#01#, "Boolean true");

   declare
      Layout : constant D.Layout_Type (1 .. 10) :=
        (D.VarInt, D.VarLong, D.String_Field, D.Boolean_Field, D.Byte,
         D.Unsigned_Byte, D.Short, D.Unsigned_Short, D.Int, D.Long);
      Status : D.Decode_Status;
      Id : I32;
      Fields : D.Field_Array (1 .. D.Max_Fields);
      Count : Natural;
   begin
      Start_Packet (16#25#);
      Append_VarInt (-1);
      Append_VarLong (I64'First);
      Append_VarInt (3);
      Append (16#41#);
      Append (16#00#);
      Append (16#01#);
      Append (16#01#);
      Append (16#00#);
      Append (16#01#);
      Append_BE (65_534, 2);
      Append_BE (65_535, 2);
      Append_BE (U64'Last - 1, 4);
      Append_BE (U64'Last - 1, 8);
      Decode_Payload (Buffer (1 .. Last), Layout, Status, Id, Fields, Count);
      Check (Status = D.Success and then Id = 16#25# and then Count = 10,
             "mixed packet result");
      if Status = D.Success and then Count = 10 then
         for I in Layout'Range loop
            Check (Fields (I).Kind = Layout (I),
                   "mixed kind" & Integer'Image (I));
         end loop;
         Check (Fields (1).VarInt_Value = -1, "mixed VarInt");
         Check (Fields (2).VarLong_Value = I64'First, "mixed VarLong");
         Check (Fields (3).Str_Len = 3, "mixed string length");
         Check (Fields (3).Str_Data (0) = 16#41#
                and then Fields (3).Str_Data (1) = 16#00#
                and then Fields (3).Str_Data (2) = 16#01#,
                "mixed string bytes");
         Check (Fields (4).Bool_Value, "mixed Boolean");
         Check (Fields (5).Byte_Value = 0, "mixed Byte");
         Check (Fields (6).UByte_Value = 1, "mixed Unsigned_Byte");
         Check (Fields (7).Short_Value = -2, "mixed Short");
         Check (Fields (8).UShort_Value = 65_535, "mixed Unsigned_Short");
         Check (Fields (9).Int_Value = -2, "mixed Int");
         Check (Fields (10).Long_Value = -2, "mixed Long");
      end if;
   end;

   if Failures = 0 then
      Ada.Text_IO.Put_Line ("test_protocol_packet_decoder: PASS");
   else
      Ada.Text_IO.Put_Line ("test_protocol_packet_decoder: FAIL");
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
   end if;
end Test_Protocol_Packet_Decoder;
