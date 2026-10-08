with Ada.Command_Line;
with Ada.Streams;
with Ada.Text_IO;
with Interfaces;
with Adacraft.Protocol;
with Adacraft.Protocol.Packets;
with Adacraft.Protocol.Packet_Encoder;
with Adacraft.Protocol.Varnum;

procedure Test_Protocol_Packet_Decoder is
   package Protocol renames Adacraft.Protocol;
   package Packets renames Adacraft.Protocol.Packets;
   package Enc renames Adacraft.Protocol.Packet_Encoder;
   package Varnum renames Adacraft.Protocol.Varnum;

   use type Interfaces.Integer_32;
   use type Interfaces.Integer_64;
   use type Packets.Decode_Error_Kind;
   use type Packets.Field_Kind;

   Failures : Natural := 0;

   procedure Check (Cond : Boolean; Name : String) is
   begin
      if not Cond then
         Failures := Failures + 1;
         Ada.Text_IO.Put_Line ("FAIL decoder: " & Name);
      end if;
   end Check;

   subtype SEA is Ada.Streams.Stream_Element_Array;
   subtype SEO is Ada.Streams.Stream_Element_Offset;

   --  Convert an encoder body (Stream_Element_Array) to Octets.
   function To_Octets (Data : SEA) return Protocol.Octets is
      Result : Protocol.Octets (1 .. Data'Length);
   begin
      for I in 0 .. Data'Length - 1 loop
         Result (Result'First + I) :=
           Protocol.Octet (Integer (Data (Data'First + SEO (I))));
      end loop;
      return Result;
   end To_Octets;

   function Encoder_Body (E : Enc.Encoder_Type) return Protocol.Octets is
      Buf  : SEA (1 .. 64) := (others => 0);
      Last : SEO;
   begin
      Enc.Get_Body (E, Buf, Last);
      if Last < Buf'First then
         return Protocol.Octets'(1 .. 0 => 0);
      end if;
      return To_Octets (Buf (Buf'First .. Last));
   end Encoder_Body;

   --  One-field layouts.
   L_Bool   : constant Packets.Field_Kind_Array (1 .. 1) := (1 => Packets.K_Boolean);
   L_Byte   : constant Packets.Field_Kind_Array (1 .. 1) := (1 => Packets.K_Byte);
   L_Int    : constant Packets.Field_Kind_Array (1 .. 1) := (1 => Packets.K_Int);
   L_Long   : constant Packets.Field_Kind_Array (1 .. 1) := (1 => Packets.K_Long);
   L_Varint : constant Packets.Field_Kind_Array (1 .. 1) := (1 => Packets.K_Varint);
   L_Varlon : constant Packets.Field_Kind_Array (1 .. 1) := (1 => Packets.K_Varlong);
   L_String : constant Packets.Field_Kind_Array (1 .. 1) := (1 => Packets.K_String);

   --  Build a body holding packet id 0, one VarInt field value.
   function Body_With_Varint (Id : Interfaces.Integer_32; V : Interfaces.Integer_32)
     return Protocol.Octets
   is
      Buf : Protocol.Octets (1 .. 12) := (others => 0);
      W1, W2 : Natural := 0;
      S : Varnum.Status_Type;
   begin
      Varnum.Encode (Id, Buf, 1, W1, S);
      if S /= Varnum.Ok then
         return Protocol.Octets'(1 .. 0 => 0);
      end if;
      Varnum.Encode (V, Buf, 1 + W1, W2, S);
      if S /= Varnum.Ok then
         return Protocol.Octets'(1 .. 0 => 0);
      end if;
      return Buf (1 .. W1 + W2);
   end Body_With_Varint;

   function Body_With_Varlong (Id : Interfaces.Integer_32; V : Interfaces.Integer_64)
     return Protocol.Octets
   is
      Buf : Protocol.Octets (1 .. 20) := (others => 0);
      W1, W2 : Natural := 0;
      S : Varnum.Status_Type;
   begin
      Varnum.Encode (Id, Buf, 1, W1, S);
      if S /= Varnum.Ok then
         return Protocol.Octets'(1 .. 0 => 0);
      end if;
      Varnum.Encode_Varlong (V, Buf, 1 + W1, W2, S);
      if S /= Varnum.Ok then
         return Protocol.Octets'(1 .. 0 => 0);
      end if;
      return Buf (1 .. W1 + W2);
   end Body_With_Varlong;

   function Body_With_String (Id : Interfaces.Integer_32; Text : String)
     return Protocol.Octets
   is
      Buf : Protocol.Octets (1 .. 16 + Text'Length) := (others => 0);
      W1, W2 : Natural := 0;
      S : Varnum.Status_Type;
   begin
      Varnum.Encode (Id, Buf, 1, W1, S);
      if S /= Varnum.Ok then
         return Protocol.Octets'(1 .. 0 => 0);
      end if;
      Varnum.Encode (Interfaces.Integer_32 (Text'Length), Buf, 1 + W1, W2, S);
      if S /= Varnum.Ok then
         return Protocol.Octets'(1 .. 0 => 0);
      end if;
      for I in Text'Range loop
         Buf (1 + W1 + W2 + (I - Text'First)) :=
           Protocol.Octet (Character'Pos (Text (I)));
      end loop;
      return Buf (1 .. W1 + W2 + Text'Length);
   end Body_With_String;

   type Enc_Access is access Enc.Encoder_Type;
   E : constant Enc_Access := new Enc.Encoder_Type;

   --  Null layout slice helper.
   Probe : Packets.Field_Kind_Array (1 .. 1) := (1 => Packets.K_Boolean);
begin
   --  T1: per-kind round-trip incl min/max/zero, encoder as oracle.

   --  Boolean.
   Enc.Start_Packet (E.all, 7);
   Enc.Write_Boolean (E.all, False);
   Check (not Enc.Has_Failed (E.all), "T1 bool setup");
   declare
      R : constant Packets.Decode_Result :=
        Packets.Decode (Encoder_Body (E.all), L_Bool);
   begin
      Check (R.Ok and then R.Id = 7
             and then R.Num_Fields = 1
             and then R.Fields (1).Kind = Packets.K_Boolean
             and then R.Fields (1).B = False, "T1 bool false");
   end;
   Enc.Start_Packet (E.all, 7);
   Enc.Write_Boolean (E.all, True);
   declare
      R : constant Packets.Decode_Result :=
        Packets.Decode (Encoder_Body (E.all), L_Bool);
   begin
      Check (R.Ok and then R.Id = 7
             and then R.Fields (1).Kind = Packets.K_Boolean
             and then R.Fields (1).B = True, "T1 bool true");
   end;

   --  Byte: 0, 255, 16#AB#.
   for V in 0 .. 2 loop
      declare
         B : constant Ada.Streams.Stream_Element :=
           (case V is when 0 => 16#00#, when 1 => 16#FF#, when others => 16#AB#);
      begin
         Enc.Start_Packet (E.all, 1);
         Enc.Write_Byte (E.all, B);
         declare
            R : constant Packets.Decode_Result :=
              Packets.Decode (Encoder_Body (E.all), L_Byte);
         begin
            Check (R.Ok and then R.Id = 1
                   and then R.Fields (1).Kind = Packets.K_Byte
                   and then Integer (R.Fields (1).Y) = Integer (B),
                   "T1 byte" & Integer'Image (V));
         end;
      end;
   end loop;

   --  Int: min / 0 / max / -1 / 1.
   declare
      Vals : constant array (1 .. 5) of Interfaces.Integer_32 :=
        (Interfaces.Integer_32'First, -1, 0, 1, Interfaces.Integer_32'Last);
   begin
      for I in Vals'Range loop
         Enc.Start_Packet (E.all, 2);
         Enc.Write_Int (E.all, Vals (I));
         declare
            R : constant Packets.Decode_Result :=
              Packets.Decode (Encoder_Body (E.all), L_Int);
         begin
            Check (R.Ok and then R.Id = 2
                   and then R.Fields (1).Kind = Packets.K_Int
                   and then R.Fields (1).I32 = Vals (I),
                   "T1 int" & Integer'Image (I));
         end;
      end loop;
   end;

   --  Long: min / 0 / max / -1 / 1.
   declare
      Vals : constant array (1 .. 5) of Interfaces.Integer_64 :=
        (Interfaces.Integer_64'First, -1, 0, 1, Interfaces.Integer_64'Last);
   begin
      for I in Vals'Range loop
         Enc.Start_Packet (E.all, 3);
         Enc.Write_Long (E.all, Vals (I));
         declare
            R : constant Packets.Decode_Result :=
              Packets.Decode (Encoder_Body (E.all), L_Long);
         begin
            Check (R.Ok and then R.Id = 3
                   and then R.Fields (1).Kind = Packets.K_Long
                   and then R.Fields (1).I64 = Vals (I),
                   "T1 long" & Integer'Image (I));
         end;
      end loop;
   end;

   --  VarInt: min / max / zero and edges.
   declare
      Vals : constant array (1 .. 7) of Interfaces.Integer_32 :=
        (Interfaces.Integer_32'First, -1, 0, 1, 127, 128,
         Interfaces.Integer_32'Last);
   begin
      for I in Vals'Range loop
         declare
            R : constant Packets.Decode_Result :=
              Packets.Decode (Body_With_Varint (0, Vals (I)), L_Varint);
         begin
            Check (R.Ok and then R.Id = 0
                   and then R.Fields (1).Kind = Packets.K_Varint
                   and then R.Fields (1).I32 = Vals (I),
                   "T1 varint" & Integer'Image (I));
         end;
      end loop;
   end;

   --  VarLong: min / max / zero and edges.
   declare
      Vals : constant array (1 .. 7) of Interfaces.Integer_64 :=
        (Interfaces.Integer_64'First, -1, 0, 1, 127, 128,
         Interfaces.Integer_64'Last);
   begin
      for I in Vals'Range loop
         declare
            R : constant Packets.Decode_Result :=
              Packets.Decode (Body_With_Varlong (0, Vals (I)), L_Varlon);
         begin
            Check (R.Ok and then R.Id = 0
                   and then R.Fields (1).Kind = Packets.K_Varlong
                   and then R.Fields (1).I64 = Vals (I),
                   "T1 varlong" & Integer'Image (I));
         end;
      end loop;
   end;

   --  String: empty, short, longer.
   declare
      R0 : constant Packets.Decode_Result :=
        Packets.Decode (Body_With_String (0, ""), L_String);
   begin
      Check (R0.Ok and then R0.Id = 0
             and then R0.Fields (1).Kind = Packets.K_String
             and then R0.Fields (1).S_Len = 0, "T1 string empty");
   end;
   declare
      R1 : constant Packets.Decode_Result :=
        Packets.Decode (Body_With_String (5, "hello"), L_String);
   begin
      Check (R1.Ok and then R1.Id = 5
             and then R1.Fields (1).Kind = Packets.K_String
             and then R1.Fields (1).S_Len = 5
             and then R1.Fields (1).S_Data (1 .. 5) = "hello",
             "T1 string hello");
   end;

   --  T2: mixed multi-field layout round-trip.
   declare
      Layout : constant Packets.Field_Kind_Array (1 .. 7) :=
        (Packets.K_Boolean, Packets.K_Byte, Packets.K_Int, Packets.K_Long,
         Packets.K_Varint, Packets.K_Varlong, Packets.K_String);
      Buf  : Protocol.Octets (1 .. 64) := (others => 0);
      Pos  : Natural := 1;
      W    : Natural := 0;
      S    : Varnum.Status_Type;
      procedure Put (B : Protocol.Octet) is
      begin
         Buf (Pos) := B;
         Pos := Pos + 1;
      end Put;
      procedure Put_BE32 (V : Interfaces.Integer_32) is
         use type Interfaces.Unsigned_32;
         U : constant Interfaces.Unsigned_32 :=
           (if V < 0 then Interfaces.Unsigned_32 (Interfaces.Integer_64 (V) + 2 ** 32)
            else Interfaces.Unsigned_32 (V));
      begin
         Put (Protocol.Octet (Interfaces.Shift_Right (U, 24) and 16#FF#));
         Put (Protocol.Octet (Interfaces.Shift_Right (U, 16) and 16#FF#));
         Put (Protocol.Octet (Interfaces.Shift_Right (U, 8) and 16#FF#));
         Put (Protocol.Octet (U and 16#FF#));
      end Put_BE32;
      procedure Put_BE64 (V : Interfaces.Integer_64) is
         use type Interfaces.Unsigned_64;
         U : Interfaces.Unsigned_64;
         pragma Unreferenced (U);
         Tmp : Protocol.Octets (1 .. 8) := (others => 0);
         E2  : Enc.Encoder_Type;
      begin
         --  Reuse #210 encoder as oracle for the 8-byte big-endian long.
         Enc.Start_Packet (E2, 0);
         Enc.Write_Long (E2, V);
         declare
            Full : constant Protocol.Octets := Encoder_Body (E2);
         begin
            --  Full = id byte 0x00 followed by 8 long bytes.
            for I in 2 .. Full'Length loop
               Put (Full (I));
            end loop;
         end;
         Tmp (1) := Tmp (1);
      end Put_BE64;
      R : Packets.Decode_Result (Ok => False);
   begin
      Varnum.Encode (9, Buf, Pos, W, S);
      Pos := Pos + W;
      Put (16#01#);   --  boolean true
      Put (16#7E#);   --  byte
      Put_BE32 (-12345);
      Put_BE64 (987_654_321_0);
      Varnum.Encode (300, Buf, Pos, W, S);
      Pos := Pos + W;
      Varnum.Encode_Varlong (-9_999, Buf, Pos, W, S);
      Pos := Pos + W;
      Varnum.Encode (3, Buf, Pos, W, S);
      Pos := Pos + W;
      Put (Protocol.Octet (Character'Pos ('a')));
      Put (Protocol.Octet (Character'Pos ('b')));
      Put (Protocol.Octet (Character'Pos ('c')));
      R := Packets.Decode (Buf (1 .. Pos - 1), Layout);
      Check (R.Ok and then R.Id = 9, "T2 id");
      if R.Ok then
         Check (R.Num_Fields = 7, "T2 count");
         Check (R.Fields (1).Kind = Packets.K_Boolean and then R.Fields (1).B,
                "T2 bool");
         Check (R.Fields (2).Kind = Packets.K_Byte
                and then Integer (R.Fields (2).Y) = 16#7E#, "T2 byte");
         Check (R.Fields (3).Kind = Packets.K_Int
                and then R.Fields (3).I32 = -12345, "T2 int");
         Check (R.Fields (4).Kind = Packets.K_Long
                and then R.Fields (4).I64 = 987_654_321_0, "T2 long");
         Check (R.Fields (5).Kind = Packets.K_Varint
                and then R.Fields (5).I32 = 300, "T2 varint");
         Check (R.Fields (6).Kind = Packets.K_Varlong
                and then R.Fields (6).I64 = -9_999, "T2 varlong");
         Check (R.Fields (7).Kind = Packets.K_String
                and then R.Fields (7).S_Len = 3
                and then R.Fields (7).S_Data (1 .. 3) = "abc", "T2 string");
      else
         Check (False, "T2 ok");
      end if;
   end;

   --  T3: ID edges succeed, negative ID rejected.
   declare
      Ids : constant array (1 .. 4) of Natural := (0, 127, 128, 2_147_483_647);
   begin
      for I in Ids'Range loop
         Enc.Start_Packet (E.all, Ids (I));
         Check (not Enc.Has_Failed (E.all), "T3 setup" & Integer'Image (I));
         declare
            R : constant Packets.Decode_Result :=
              Packets.Decode (Encoder_Body (E.all),
                              Probe (Probe'First .. Probe'First - 1));
         begin
            Check (R.Ok and then R.Id = Ids (I)
                   and then R.Num_Fields = 0, "T3 id" & Integer'Image (I));
         end;
      end loop;
   end;
   declare
      Neg : constant Protocol.Octets (1 .. 5) :=
        (16#FF#, 16#FF#, 16#FF#, 16#FF#, 16#0F#);
      R : constant Packets.Decode_Result :=
        Packets.Decode (Neg, Probe (Probe'First .. Probe'First - 1));
   begin
      Check (not R.Ok and then R.Err = Packets.Invalid_Packet_Id,
             "T3 negative id rejected");
   end;

   if Failures = 0 then
      Ada.Text_IO.Put_Line ("packet decoder tests passed");
   else
      Ada.Text_IO.Put_Line ("packet decoder tests failed");
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
   end if;
end Test_Protocol_Packet_Decoder;
