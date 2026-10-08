with Ada.Command_Line;
with Ada.Text_IO;
with Interfaces;
with Adacraft.Protocol;
with Adacraft.Protocol.Packet_Encoder;

procedure Test_Protocol_Packet_Encoder is
   package PE renames Adacraft.Protocol.Packet_Encoder;
   use Adacraft.Protocol;
   use type Interfaces.Integer_32;
   use type Interfaces.Unsigned_8;
   use type PE.Byte_Array;
   use type PE.Status;

   Failures : Natural := 0;

   procedure Check (Condition : Boolean; Name : String) is
   begin
      if not Condition then
         Failures := Failures + 1;
         Ada.Text_IO.Put_Line ("FAIL: " & Name);
      end if;
   end Check;

   function Equal (A, B : PE.Byte_Array) return Boolean is
   begin
      if A'Length /= B'Length then
         return False;
      end if;
      for I in 0 .. A'Length - 1 loop
         if A (A'First + I) /= B (B'First + I) then
            return False;
         end if;
      end loop;
      return True;
   end Equal;

   --  T1: encode Id into a fresh buffer, compare body bytes.
   procedure Check_Id (Id : Interfaces.Integer_32; Expected : PE.Byte_Array; Name : String) is
      E    : PE.Encoder;
      Buf  : PE.Byte_Array (1 .. 8) := (others => 0);
      Last : Natural := 0;
      S    : PE.Status;
   begin
      PE.Start (E);
      PE.Write_Packet_Id (E, Buf, Id);
      Check (PE.Status_Of (E) = PE.Ok, Name & " status");
      Check (PE.Body_Length (E) = Expected'Length, Name & " length");
      PE.Finish (E, Buf, Last, S);
      Check (S = PE.Ok, Name & " finish");
      if S = PE.Ok then
         Check (Last = Buf'First + Expected'Length - 1, Name & " last");
         Check (Equal (Buf (Buf'First .. Last), Expected), Name & " bytes");
      end if;
   end Check_Id;

begin
   --  T1 packet-ID vectors (VarInt encodings).
   Check_Id (0, PE.Byte_Array'(1 => 16#00#), "T1 id 0");
   Check_Id (127, PE.Byte_Array'(1 => 16#7F#), "T1 id 127");
   Check_Id (128, PE.Byte_Array'(16#80#, 16#01#), "T1 id 128");
   Check_Id (255, PE.Byte_Array'(16#FF#, 16#01#), "T1 id 255");
   Check_Id
     (2_147_483_647,
      PE.Byte_Array'(16#FF#, 16#FF#, 16#FF#, 16#FF#, 16#07#),
      "T1 id max");

   --  T1 negative ID -> Invalid_Packet_Id, zero bytes.
   declare
      E   : PE.Encoder;
      Buf : PE.Byte_Array (1 .. 8) := (others => 16#AA#);
   begin
      PE.Start (E);
      PE.Write_Packet_Id (E, Buf, -1);
      Check (PE.Status_Of (E) = PE.Invalid_Packet_Id, "T1 id -1 status");
      Check (PE.Body_Length (E) = 0, "T1 id -1 length");
      Check (Buf = PE.Byte_Array'(1 .. 8 => 16#AA#), "T1 id -1 no bytes");
   end;

   --  T2: fixed-width big-endian field writers vs hand-computed bytes.
   --  Each case writes packet ID 0 (16#00#) then one field.
   declare
      procedure Check_Body
        (Name     : String;
         Expected : PE.Byte_Array)
      is
         pragma Unreferenced (Name);
         pragma Unreferenced (Expected);
      begin
         null;
      end Check_Body;
   begin
      null;
   end;

   procedure Check_Bool (V : Boolean; Second : Interfaces.Unsigned_8; Name : String) is
      E    : PE.Encoder;
      Buf  : PE.Byte_Array (1 .. 8) := (others => 16#AA#);
      Last : Natural := 0;
      S    : PE.Status;
   begin
      PE.Start (E);
      PE.Write_Packet_Id (E, Buf, 0);
      PE.Write_Boolean (E, Buf, V);
      Check (PE.Status_Of (E) = PE.Ok, Name & " status");
      PE.Finish (E, Buf, Last, S);
      Check (S = PE.Ok, Name & " finish");
      if S = PE.Ok then
         Check (Equal (Buf (Buf'First .. Last), PE.Byte_Array'(16#00#, Second)), Name & " bytes");
      end if;
   end Check_Bool;

   procedure Check_Byte (V : Interfaces.Integer_8; Second : Interfaces.Unsigned_8; Name : String) is
      E    : PE.Encoder;
      Buf  : PE.Byte_Array (1 .. 8) := (others => 16#AA#);
      Last : Natural := 0;
      S    : PE.Status;
   begin
      PE.Start (E);
      PE.Write_Packet_Id (E, Buf, 0);
      PE.Write_Byte (E, Buf, V);
      Check (PE.Status_Of (E) = PE.Ok, Name & " status");
      PE.Finish (E, Buf, Last, S);
      Check (S = PE.Ok, Name & " finish");
      if S = PE.Ok then
         Check (Equal (Buf (Buf'First .. Last), PE.Byte_Array'(16#00#, Second)), Name & " bytes");
      end if;
   end Check_Byte;

   procedure Check_UByte (V : Interfaces.Unsigned_8; Name : String) is
      E    : PE.Encoder;
      Buf  : PE.Byte_Array (1 .. 8) := (others => 16#AA#);
      Last : Natural := 0;
      S    : PE.Status;
   begin
      PE.Start (E);
      PE.Write_Packet_Id (E, Buf, 0);
      PE.Write_UByte (E, Buf, V);
      Check (PE.Status_Of (E) = PE.Ok, Name & " status");
      PE.Finish (E, Buf, Last, S);
      Check (S = PE.Ok, Name & " finish");
      if S = PE.Ok then
         Check (Equal (Buf (Buf'First .. Last), PE.Byte_Array'(16#00#, V)), Name & " bytes");
      end if;
   end Check_UByte;

   procedure Check_Short (V : Interfaces.Integer_16; Hi, Lo : Interfaces.Unsigned_8; Name : String) is
      E    : PE.Encoder;
      Buf  : PE.Byte_Array (1 .. 8) := (others => 16#AA#);
      Last : Natural := 0;
      S    : PE.Status;
   begin
      PE.Start (E);
      PE.Write_Packet_Id (E, Buf, 0);
      PE.Write_Short (E, Buf, V);
      Check (PE.Status_Of (E) = PE.Ok, Name & " status");
      PE.Finish (E, Buf, Last, S);
      Check (S = PE.Ok, Name & " finish");
      if S = PE.Ok then
         Check (Equal (Buf (Buf'First .. Last), PE.Byte_Array'(16#00#, Hi, Lo)), Name & " bytes");
      end if;
   end Check_Short;

   procedure Check_UShort (V : Interfaces.Unsigned_16; Hi, Lo : Interfaces.Unsigned_8; Name : String) is
      E    : PE.Encoder;
      Buf  : PE.Byte_Array (1 .. 8) := (others => 16#AA#);
      Last : Natural := 0;
      S    : PE.Status;
   begin
      PE.Start (E);
      PE.Write_Packet_Id (E, Buf, 0);
      PE.Write_UShort (E, Buf, V);
      Check (PE.Status_Of (E) = PE.Ok, Name & " status");
      PE.Finish (E, Buf, Last, S);
      Check (S = PE.Ok, Name & " finish");
      if S = PE.Ok then
         Check (Equal (Buf (Buf'First .. Last), PE.Byte_Array'(16#00#, Hi, Lo)), Name & " bytes");
      end if;
   end Check_UShort;

   procedure Check_Int (V : Interfaces.Integer_32; B0, B1, B2, B3 : Interfaces.Unsigned_8; Name : String) is
      E    : PE.Encoder;
      Buf  : PE.Byte_Array (1 .. 16) := (others => 16#AA#);
      Last : Natural := 0;
      S    : PE.Status;
   begin
      PE.Start (E);
      PE.Write_Packet_Id (E, Buf, 0);
      PE.Write_Int (E, Buf, V);
      Check (PE.Status_Of (E) = PE.Ok, Name & " status");
      PE.Finish (E, Buf, Last, S);
      Check (S = PE.Ok, Name & " finish");
      if S = PE.Ok then
         Check (Equal (Buf (Buf'First .. Last), PE.Byte_Array'(16#00#, B0, B1, B2, B3)), Name & " bytes");
      end if;
   end Check_Int;

   procedure Check_Long
     (V : Interfaces.Integer_64;
      B0, B1, B2, B3, B4, B5, B6, B7 : Interfaces.Unsigned_8;
      Name : String) is
      E    : PE.Encoder;
      Buf  : PE.Byte_Array (1 .. 16) := (others => 16#AA#);
      Last : Natural := 0;
      S    : PE.Status;
   begin
      PE.Start (E);
      PE.Write_Packet_Id (E, Buf, 0);
      PE.Write_Long (E, Buf, V);
      Check (PE.Status_Of (E) = PE.Ok, Name & " status");
      PE.Finish (E, Buf, Last, S);
      Check (S = PE.Ok, Name & " finish");
      if S = PE.Ok then
         Check
           (Equal (Buf (Buf'First .. Last),
                   PE.Byte_Array'(16#00#, B0, B1, B2, B3, B4, B5, B6, B7)),
            Name & " bytes");
      end if;
   end Check_Long;

begin
   Check_Bool (True, 16#01#, "T2 bool true");
   Check_Bool (False, 16#00#, "T2 bool false");
   Check_Byte (127, 16#7F#, "T2 byte 127");
   Check_Byte (-128, 16#80#, "T2 byte -128");
   Check_Byte (-1, 16#FF#, "T2 byte -1");
   Check_UByte (0, "T2 ubyte 0");
   Check_UByte (255, "T2 ubyte 255");
   Check_Short (32767, 16#7F#, 16#FF#, "T2 short max");
   Check_Short (-32768, 16#80#, 16#00#, "T2 short min");
   Check_Short (-1, 16#FF#, 16#FF#, "T2 short -1");
   Check_Short (0, 16#00#, 16#00#, "T2 short 0");
   Check_UShort (0, 16#00#, 16#00#, "T2 ushort 0");
   Check_UShort (65535, 16#FF#, 16#FF#, "T2 ushort max");
   Check_UShort (16#1234#, 16#12#, 16#34#, "T2 ushort 1234");
   Check_Int (2_147_483_647, 16#7F#, 16#FF#, 16#FF#, 16#FF#, "T2 int max");
   Check_Int (-2_147_483_648, 16#80#, 16#00#, 16#00#, 16#00#, "T2 int min");
   Check_Int (-1, 16#FF#, 16#FF#, 16#FF#, 16#FF#, "T2 int -1");
   Check_Int (0, 16#00#, 16#00#, 16#00#, 16#00#, "T2 int 0");
   Check_Long
     (9_223_372_036_854_775_807,
      16#7F#, 16#FF#, 16#FF#, 16#FF#, 16#FF#, 16#FF#, 16#FF#, 16#FF#,
      "T2 long max");
   Check_Long
     (-9_223_372_036_854_775_808,
      16#80#, 16#00#, 16#00#, 16#00#, 16#00#, 16#00#, 16#00#, 16#00#,
      "T2 long min");
   Check_Long
     (-1, 16#FF#, 16#FF#, 16#FF#, 16#FF#, 16#FF#, 16#FF#, 16#FF#, 16#FF#,
      "T2 long -1");
   Check_Long
     (0, 16#00#, 16#00#, 16#00#, 16#00#, 16#00#, 16#00#, 16#00#, 16#00#,
      "T2 long 0");

   --  T2 empty behaviors: zero-length raw write after ID writes nothing, stays Ok.
   declare
      E   : PE.Encoder;
      Buf : PE.Byte_Array (1 .. 8) := (others => 16#AA#);
   begin
      PE.Start (E);
      PE.Write_Packet_Id (E, Buf, 0);
      PE.Write_Bytes (E, Buf, Buf (2 .. 1));
      Check (PE.Status_Of (E) = PE.Ok, "T2 empty bytes status");
      Check (PE.Body_Length (E) = 1, "T2 empty bytes length");
      Check (Buf (1) = 16#00#, "T2 empty bytes kept");
   end;

   --  T2 empty behaviors: zero-length raw write before ID is an ordering error.
   declare
      E   : PE.Encoder;
      Buf : PE.Byte_Array (1 .. 8) := (others => 16#AA#);
   begin
      PE.Start (E);
      PE.Write_Bytes (E, Buf, Buf (2 .. 1));
      Check (PE.Status_Of (E) = PE.Invalid_Sequence, "T2 empty-before-id status");
      Check (PE.Body_Length (E) = 0, "T2 empty-before-id length");
   end;

   --  T10: field before ID -> Invalid_Sequence, zero bytes.
   declare
      E   : PE.Encoder;
      Buf : PE.Byte_Array (1 .. 8) := (others => 16#AA#);
   begin
      PE.Start (E);
      PE.Write_Boolean (E, Buf, True);
      Check (PE.Status_Of (E) = PE.Invalid_Sequence, "T10 field-before-id");
      Check (PE.Body_Length (E) = 0, "T10 field-before-id length");
      Check (Buf = PE.Byte_Array'(1 .. 8 => 16#AA#), "T10 field-before-id bytes");
   end;

   --  T10: double ID -> Invalid_Sequence, first bytes kept.
   declare
      E   : PE.Encoder;
      Buf : PE.Byte_Array (1 .. 8) := (others => 16#AA#);
      Len : Natural;
   begin
      PE.Start (E);
      PE.Write_Packet_Id (E, Buf, 5);
      Len := PE.Body_Length (E);
      PE.Write_Packet_Id (E, Buf, 6);
      Check (PE.Status_Of (E) = PE.Invalid_Sequence, "T10 double-id");
      Check (PE.Body_Length (E) = Len, "T10 double-id length");
      Check (Buf (1) = 5, "T10 double-id byte kept");
   end;

   --  T10: finish/frame with no ID -> Invalid_Sequence.
   declare
      E        : PE.Encoder;
      Buf      : PE.Byte_Array (1 .. 8) := (others => 0);
      Last     : Natural := 0;
      S        : PE.Status;
      Out_Buf  : PE.Byte_Array (1 .. 16) := (others => 0);
      Out_Last : Natural := 0;
   begin
      PE.Start (E);
      PE.Finish (E, Buf, Last, S);
      Check (S = PE.Invalid_Sequence, "T10 finish-no-id");
      PE.Frame (E, Buf, Out_Buf, Out_Last, S);
      Check (S = PE.Invalid_Sequence, "T10 frame-no-id");
   end;

   if Failures = 0 then
      Ada.Text_IO.Put_Line ("packet encoder tests passed");
   else
      Ada.Text_IO.Put_Line ("packet encoder tests failed:" & Failures'Image);
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
   end if;
end Test_Protocol_Packet_Encoder;
