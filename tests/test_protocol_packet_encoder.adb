with Ada.Command_Line;
with Ada.Streams;
with Ada.Text_IO;
with Interfaces;
with Adacraft.Protocol;
with Adacraft.Protocol.Frame;
with Adacraft.Protocol.Packet_Encoder;
with Adacraft.Protocol.Varnum;

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

   --  T1 packet-ID vectors (VarInt encodings) run in the single
   --  statement part at the end of this procedure.
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

   --  T3: VarInt byte-equality vs direct Varnum.Encode (0/-1/max/min).
   declare
      procedure Check_VarInt (V : Interfaces.Integer_32; Name : String) is
         use type Varnum.Status_Type;
         E       : PE.Encoder;
         Buf     : PE.Byte_Array (1 .. 16) := (others => 16#AA#);
         Staging : Octets (1 .. Max_Varint_Bytes) := (others => 0);
         Written : Natural := 0;
         Vs      : Varnum.Status_Type;
         Last    : Natural := 0;
         S       : PE.Status;
      begin
         Varnum.Encode (V, Staging, Staging'First, Written, Vs);
         Check (Vs = Varnum.Ok, Name & " varnum ok");
         PE.Start (E);
         PE.Write_Packet_Id (E, Buf, 0);
         PE.Write_VarInt (E, Buf, V);
         Check (PE.Status_Of (E) = PE.Ok, Name & " status");
         Check (PE.Body_Length (E) = 1 + Written, Name & " length");
         PE.Finish (E, Buf, Last, S);
         Check (S = PE.Ok, Name & " finish");
         if S = PE.Ok then
            Check (Buf (Buf'First) = 16#00#, Name & " id byte");
            for I in 0 .. Written - 1 loop
               if Buf (Buf'First + 1 + I) /= Staging (Staging'First + I) then
                  Check (False, Name & " byte");
               end if;
            end loop;
         end if;
      end Check_VarInt;

      procedure Check_VarLong (V : Interfaces.Integer_64; Name : String) is
         use type Varnum.Status_Type;
         E       : PE.Encoder;
         Buf     : PE.Byte_Array (1 .. 16) := (others => 16#AA#);
         Staging : Octets (1 .. Max_Varlong_Bytes) := (others => 0);
         Written : Natural := 0;
         Vs      : Varnum.Status_Type;
         Last    : Natural := 0;
         S       : PE.Status;
      begin
         Varnum.Encode_Varlong (V, Staging, Staging'First, Written, Vs);
         Check (Vs = Varnum.Ok, Name & " varnum ok");
         PE.Start (E);
         PE.Write_Packet_Id (E, Buf, 0);
         PE.Write_VarLong (E, Buf, V);
         Check (PE.Status_Of (E) = PE.Ok, Name & " status");
         Check (PE.Body_Length (E) = 1 + Written, Name & " length");
         PE.Finish (E, Buf, Last, S);
         Check (S = PE.Ok, Name & " finish");
         if S = PE.Ok then
            Check (Buf (Buf'First) = 16#00#, Name & " id byte");
            for I in 0 .. Written - 1 loop
               if Buf (Buf'First + 1 + I) /= Staging (Staging'First + I) then
                  Check (False, Name & " byte");
               end if;
            end loop;
         end if;
      end Check_VarLong;
   begin
      Check_VarInt (0, "T3 varint 0");
      Check_VarInt (-1, "T3 varint -1");
      Check_VarInt (2_147_483_647, "T3 varint max");
      Check_VarInt (-2_147_483_648, "T3 varint min");
      Check_VarLong (0, "T3 varlong 0");
      Check_VarLong (-1, "T3 varlong -1");
      Check_VarLong (9_223_372_036_854_775_807, "T3 varlong max");
      Check_VarLong (-9_223_372_036_854_775_808, "T3 varlong min");
   end;

   --  T3b: Write_Bytes copies payload verbatim after ID.
   declare
      E        : PE.Encoder;
      Buf      : PE.Byte_Array (1 .. 16) := (others => 16#AA#);
      Payload  : PE.Byte_Array'(16#DE#, 16#AD#, 16#BE#, 16#EF#);
      Last     : Natural := 0;
      S        : PE.Status;
   begin
      PE.Start (E);
      PE.Write_Packet_Id (E, Buf, 0);
      PE.Write_Bytes (E, Buf, Payload);
      Check (PE.Status_Of (E) = PE.Ok, "T3 bytes status");
      Check (PE.Body_Length (E) = 5, "T3 bytes length");
      PE.Finish (E, Buf, Last, S);
      Check (S = PE.Ok, "T3 bytes finish");
      if S = PE.Ok then
         Check
           (Equal (Buf (Buf'First .. Last),
                   PE.Byte_Array'(16#00#, 16#DE#, 16#AD#, 16#BE#, 16#EF#)),
            "T3 bytes content");
      end if;
   end;

   --  T4: handshake-shaped body
   --  ID 0, VarInt 777 (16#89#, 16#06#), string placeholder bytes for
   --  length-prefixed "localhost" (09 + 9 bytes), UShort 25565 (63 DD),
   --  VarInt 1 (next state), vs hand-computed vector.
   declare
      E        : PE.Encoder;
      Buf      : PE.Byte_Array (1 .. 32) := (others => 16#AA#);
      Str_Body : PE.Byte_Array'(
        16#09#,
        16#6C#, 16#6F#, 16#63#, 16#61#, 16#6C#,
        16#68#, 16#6F#, 16#73#, 16#74#);
      Expected : PE.Byte_Array'(
        16#00#,
        16#89#, 16#06#,
        16#09#,
        16#6C#, 16#6F#, 16#63#, 16#61#, 16#6C#,
        16#68#, 16#6F#, 16#73#, 16#74#,
        16#63#, 16#DD#,
        16#01#);
      Last : Natural := 0;
      S    : PE.Status;
   begin
      PE.Start (E);
      PE.Write_Packet_Id (E, Buf, 0);
      PE.Write_VarInt (E, Buf, 777);
      PE.Write_Bytes (E, Buf, Str_Body);
      PE.Write_UShort (E, Buf, 25565);
      PE.Write_VarInt (E, Buf, 1);
      Check (PE.Status_Of (E) = PE.Ok, "T4 handshake status");
      Check (PE.Body_Length (E) = Expected'Length, "T4 handshake length");
      PE.Finish (E, Buf, Last, S);
      Check (S = PE.Ok, "T4 handshake finish");
      if S = PE.Ok then
         Check (Equal (Buf (Buf'First .. Last), Expected), "T4 handshake bytes");
      end if;
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

   --  T5: exact-fill then one more write -> Overflow, prior bytes unchanged.
   declare
      E   : PE.Encoder;
      Buf : PE.Byte_Array (1 .. 4) := (others => 16#AA#);
   begin
      PE.Start (E);
      PE.Write_Packet_Id (E, Buf, 0);
      PE.Write_Bytes (E, Buf, PE.Byte_Array'(16#11#, 16#22#, 16#33#));
      Check (PE.Status_Of (E) = PE.Ok, "T5 exact-fill status");
      Check (PE.Body_Length (E) = 4, "T5 exact-fill length");
      Check
        (Equal (Buf, PE.Byte_Array'(16#00#, 16#11#, 16#22#, 16#33#)),
         "T5 exact-fill bytes");
      PE.Write_Boolean (E, Buf, True);
      Check (PE.Status_Of (E) = PE.Overflow, "T5 overflow status");
      Check (PE.Body_Length (E) = 4, "T5 overflow length");
      Check
        (Equal (Buf, PE.Byte_Array'(16#00#, 16#11#, 16#22#, 16#33#)),
         "T5 overflow unchanged");
   end;

   --  T5: straddling write stores nothing atomically.
   declare
      E   : PE.Encoder;
      Buf : PE.Byte_Array (1 .. 3) := (others => 16#AA#);
   begin
      PE.Start (E);
      PE.Write_Packet_Id (E, Buf, 0);
      PE.Write_Int (E, Buf, 16#01020304#);
      Check (PE.Status_Of (E) = PE.Overflow, "T5 straddle status");
      Check (PE.Body_Length (E) = 1, "T5 straddle length");
      Check (Buf (1) = 16#00#, "T5 straddle first kept");
      Check (Buf (2) = 16#AA#, "T5 straddle no partial 1");
      Check (Buf (3) = 16#AA#, "T5 straddle no partial 2");
   end;

   --  T6: sticky error preserves first status, length, bytes.
   declare
      E   : PE.Encoder;
      Buf : PE.Byte_Array (1 .. 2) := (others => 16#AA#);
   begin
      PE.Start (E);
      PE.Write_Packet_Id (E, Buf, 0);
      PE.Write_UShort (E, Buf, 16#1234#);
      Check (PE.Status_Of (E) = PE.Overflow, "T6 first status");
      Check (PE.Body_Length (E) = 1, "T6 first length");
      PE.Write_Boolean (E, Buf, True);
      PE.Write_Byte (E, Buf, 7);
      PE.Write_Bytes (E, Buf, PE.Byte_Array'(1 => 16#FF#));
      Check (PE.Status_Of (E) = PE.Overflow, "T6 sticky status");
      Check (PE.Body_Length (E) = 1, "T6 sticky length");
      Check (Buf (1) = 16#00#, "T6 sticky byte kept");
      Check (Buf (2) = 16#AA#, "T6 sticky no write");
   end;

   --  T7: string over max -> String_Too_Long, nothing stored.
   declare
      E   : PE.Encoder;
      Buf : PE.Byte_Array (1 .. 16) := (others => 16#AA#);
   begin
      PE.Start (E);
      PE.Write_Packet_Id (E, Buf, 0);
      PE.Write_String (E, Buf, PE.Byte_Array'(16#41#, 16#42#, 16#43#, 16#44#, 16#45#), 3);
      Check (PE.Status_Of (E) = PE.String_Too_Long, "T7 over status");
      Check (PE.Body_Length (E) = 1, "T7 over length");
      Check (Buf (1) = 16#00#, "T7 over first kept");
      Check (Buf (2) = 16#AA#, "T7 over atomic");
   end;

   --  T7: string at exactly max is accepted (prefix + payload).
   declare
      E    : PE.Encoder;
      Buf  : PE.Byte_Array (1 .. 16) := (others => 16#AA#);
      Last : Natural := 0;
      S    : PE.Status;
   begin
      PE.Start (E);
      PE.Write_Packet_Id (E, Buf, 0);
      PE.Write_String (E, Buf, PE.Byte_Array'(16#41#, 16#42#, 16#43#), 3);
      Check (PE.Status_Of (E) = PE.Ok, "T7 exact status");
      Check (PE.Body_Length (E) = 5, "T7 exact length");
      PE.Finish (E, Buf, Last, S);
      Check (S = PE.Ok, "T7 exact finish");
      if S = PE.Ok then
         Check
           (Equal (Buf (Buf'First .. Last),
                   PE.Byte_Array'(16#00#, 16#03#, 16#41#, 16#42#, 16#43#)),
            "T7 exact bytes");
      end if;
   end;

   --  T7: empty string after ID writes single 0x00 prefix.
   declare
      E    : PE.Encoder;
      Buf  : PE.Byte_Array (1 .. 8) := (others => 16#AA#);
      Last : Natural := 0;
      S    : PE.Status;
   begin
      PE.Start (E);
      PE.Write_Packet_Id (E, Buf, 0);
      PE.Write_String (E, Buf, Buf (2 .. 1), 10);
      Check (PE.Status_Of (E) = PE.Ok, "T7 empty status");
      Check (PE.Body_Length (E) = 2, "T7 empty length");
      PE.Finish (E, Buf, Last, S);
      Check (S = PE.Ok, "T7 empty finish");
      if S = PE.Ok then
         Check
           (Equal (Buf (Buf'First .. Last), PE.Byte_Array'(16#00#, 16#00#)),
            "T7 empty bytes");
      end if;
   end;

   --  A6: zero-length ordering checks.
   declare
      E   : PE.Encoder;
      Buf : PE.Byte_Array (1 .. 8) := (others => 16#AA#);
   begin
      PE.Start (E);
      PE.Write_String (E, Buf, Buf (2 .. 1), 10);
      Check (PE.Status_Of (E) = PE.Invalid_Sequence, "A6 empty-str-before-id");
      Check (PE.Body_Length (E) = 0, "A6 empty-str-before-id length");
      Check (Buf = PE.Byte_Array'(1 .. 8 => 16#AA#), "A6 empty-str-before-id bytes");
   end;

   --  T8: body exactly Max_Frame_Body_Length accepted via chunked writes.
   declare
      use Adacraft.Protocol.Frame;
      Total : constant Natural := Max_Frame_Body_Length;
      E     : PE.Encoder;
      Buf   : PE.Byte_Array (1 .. Max_Frame_Body_Length + 1) :=
        (others => 16#AA#);
      Chunk : PE.Byte_Array (1 .. 65_536) := (others => 16#55#);
      Remaining : Natural;
   begin
      PE.Start (E);
      PE.Write_Packet_Id (E, Buf, 0);
      Check (PE.Status_Of (E) = PE.Ok, "T8 setup status");
      Remaining := Total - PE.Body_Length (E);
      while Remaining > 0 loop
         declare
            N : constant Natural := Natural'Min (Remaining, Chunk'Length);
         begin
            PE.Write_Bytes (E, Buf, Chunk (Chunk'First .. Chunk'First + N - 1));
            exit when PE.Status_Of (E) /= PE.Ok;
            Remaining := Total - PE.Body_Length (E);
         end;
      end loop;
      Check (PE.Status_Of (E) = PE.Ok, "T8 exact status");
      Check (PE.Body_Length (E) = Total, "T8 exact length");
      PE.Write_Boolean (E, Buf, False);
      Check (PE.Status_Of (E) = PE.Body_Too_Long, "T8 plus1 status");
      Check (PE.Body_Length (E) = Total, "T8 plus1 length");
   end;

   --  T9: Frame wrapper equals Frame.Encode for 1-byte body.
   declare
      use type Adacraft.Protocol.Frame.Encode_Status;
      E        : PE.Encoder;
      Buf      : PE.Byte_Array (1 .. 8) := (others => 16#AA#);
      Out_Buf  : PE.Byte_Array (1 .. 8) := (others => 16#AA#);
      Out_Last : Natural := 0;
      S        : PE.Status;
      Payload  : Ada.Streams.Stream_Element_Array (1 .. 1);
      Expected : Ada.Streams.Stream_Element_Array (1 .. 8) :=
        (others => 0);
      Exp_Last : Ada.Streams.Stream_Element_Offset;
      Exp_St   : Adacraft.Protocol.Frame.Encode_Status;
   begin
      PE.Start (E);
      PE.Write_Packet_Id (E, Buf, 0);
      Check (PE.Status_Of (E) = PE.Ok, "T9 1byte setup");
      Payload (1) := Ada.Streams.Stream_Element (Buf (Buf'First));
      Adacraft.Protocol.Frame.Encode
        (Payload => Payload, Output => Expected,
         Last => Exp_Last, Status => Exp_St);
      Check (Exp_St = Adacraft.Protocol.Frame.Ok, "T9 1byte ref ok");
      PE.Frame (E, Buf, Out_Buf, Out_Last, S);
      Check (S = PE.Ok, "T9 1byte status");
      if S = PE.Ok then
         Check
           (Out_Last = Out_Buf'First + Natural (Exp_Last) - 1,
            "T9 1byte last");
         for I in 0 .. Natural (Exp_Last) - 1 loop
            if Out_Buf (Out_Buf'First + I) /=
              Interfaces.Unsigned_8 (Expected (Expected'First + I))
            then
               Check (False, "T9 1byte byte");
            end if;
         end loop;
      end if;
   end;

   --  T9: Frame wrapper equals Frame.Encode for body needing 3-byte prefix.
   declare
      use type Adacraft.Protocol.Frame.Encode_Status;
      Body_Len : constant Natural := 16_384;
      E        : PE.Encoder;
      Buf      : PE.Byte_Array (1 .. 16_384) := (others => 16#55#);
      Out_Buf  : PE.Byte_Array (1 .. 16_384 + 3) := (others => 16#AA#);
      Out_Last : Natural := 0;
      S        : PE.Status;
      Payload  : Ada.Streams.Stream_Element_Array
        (1 .. Ada.Streams.Stream_Element_Offset (Body_Len));
      Expected : Ada.Streams.Stream_Element_Array
        (1 .. Ada.Streams.Stream_Element_Offset (Body_Len + 3)) :=
        (others => 0);
      Exp_Last : Ada.Streams.Stream_Element_Offset;
      Exp_St   : Adacraft.Protocol.Frame.Encode_Status;
   begin
      PE.Start (E);
      PE.Write_Packet_Id (E, Buf, 0);
      for I in 1 .. Body_Len - 1 loop
         PE.Write_Bytes (E, Buf, PE.Byte_Array'(1 => 16#55#));
         exit when PE.Status_Of (E) /= PE.Ok;
      end loop;
      Check (PE.Status_Of (E) = PE.Ok, "T9 3byte setup");
      Check (PE.Body_Length (E) = Body_Len, "T9 3byte length");
      for I in 0 .. Body_Len - 1 loop
         Payload (Payload'First + I) :=
           Ada.Streams.Stream_Element (Buf (Buf'First + I));
      end loop;
      Adacraft.Protocol.Frame.Encode
        (Payload => Payload, Output => Expected,
         Last => Exp_Last, Status => Exp_St);
      Check (Exp_St = Adacraft.Protocol.Frame.Ok, "T9 3byte ref ok");
      Check
        (Natural (Exp_Last) = Body_Len + 3, "T9 3byte prefix len");
      PE.Frame (E, Buf, Out_Buf, Out_Last, S);
      Check (S = PE.Ok, "T9 3byte status");
      if S = PE.Ok then
         Check
           (Out_Last = Out_Buf'First + Natural (Exp_Last) - 1,
            "T9 3byte last");
         for I in 0 .. Natural (Exp_Last) - 1 loop
            if Out_Buf (Out_Buf'First + I) /=
              Interfaces.Unsigned_8 (Expected (Expected'First + I))
            then
               Check (False, "T9 3byte byte");
            end if;
         end loop;
      end if;
   end;

   --  T9: too-small frame output buffer -> non-Ok, no bytes written.
   declare
      E        : PE.Encoder;
      Buf      : PE.Byte_Array (1 .. 8) := (others => 0);
      Out_Buf  : PE.Byte_Array (1 .. 1) := (others => 16#AA#);
      Out_Last : Natural := 0;
      S        : PE.Status;
   begin
      PE.Start (E);
      PE.Write_Packet_Id (E, Buf, 0);
      PE.Frame (E, Buf, Out_Buf, Out_Last, S);
      Check (S /= PE.Ok, "T9 small status");
      Check (Out_Last = Out_Buf'First - 1, "T9 small last");
      Check (Out_Buf = PE.Byte_Array'(1 => 16#AA#), "T9 small unchanged");
   end;

   --  T9 closure: finish/frame with no ID -> Invalid_Sequence.
   declare
      E        : PE.Encoder;
      Buf      : PE.Byte_Array (1 .. 8) := (others => 0);
      Out_Buf  : PE.Byte_Array (1 .. 8) := (others => 16#AA#);
      Last     : Natural := 0;
      Out_Last : Natural := 0;
      S        : PE.Status;
   begin
      PE.Start (E);
      PE.Finish (E, Buf, Last, S);
      Check (S = PE.Invalid_Sequence, "T9 finish-no-id");
      PE.Frame (E, Buf, Out_Buf, Out_Last, S);
      Check (S = PE.Invalid_Sequence, "T9 frame-no-id");
      Check (Out_Last = Out_Buf'First - 1, "T9 frame-no-id last");
      Check
        (Out_Buf = PE.Byte_Array'(1 .. 8 => 16#AA#),
         "T9 frame-no-id unchanged");
   end;

   if Failures = 0 then
      Ada.Text_IO.Put_Line ("packet encoder tests passed");
   else
      Ada.Text_IO.Put_Line ("packet encoder tests failed:" & Failures'Image);
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
   end if;
end Test_Protocol_Packet_Encoder;
