with Ada.Command_Line;
with Ada.Strings.Fixed;
with Ada.Text_IO;
with Interfaces;
with Adacraft.Auth;
with Adacraft.Ingress;
with Adacraft.Kernel;
with Adacraft.Protocol.Buffer;
with Adacraft.Protocol.Frame;
with Adacraft.Protocol.Ids;
with Adacraft.Protocol.Packets;
with Adacraft.Protocol.Varnum;

procedure Adacraft_Tests is
   package Protocol renames Adacraft.Protocol;
   package Kernel renames Adacraft.Kernel;
   package Auth renames Adacraft.Auth;
   package Ingress renames Adacraft.Ingress;
   use type Interfaces.Unsigned_32;
   use type Interfaces.Unsigned_16;
   use type Interfaces.Unsigned_64;
   use type Interfaces.Integer_32;
   use type Interfaces.Unsigned_8;
   use type Protocol.Status_Kind;
   use type Protocol.Protocol_State;
   use type Protocol.Octet;
   use type Kernel.Attempt;
   use type Kernel.Authority;
   use type Kernel.Stack;
   use type Kernel.Item_Id;
   use type Kernel.Residency;
   use type Kernel.Stack_Count;
   use type Protocol.Varnum.VarInt_Status;
   Failures : Natural := 0;

   procedure Check (Cond : Boolean; Name : String) is
   begin
      if not Cond then
         Ada.Text_IO.Put_Line ("FAIL " & Name);
         Failures := Failures + 1;
      end if;
   end Check;

   function Hex (D : Auth.Digest) return String is
      Map : constant String := "0123456789abcdef";
      Image : String (1 .. 32);
   begin
      for I in D'Range loop
         Image (I * 2 - 1) := Map (Natural (D (I)) / 16 + 1);
         Image (I * 2) := Map (Natural (D (I)) mod 16 + 1);
      end loop;
      return Image;
   end Hex;

   function Bytes (Text : String) return Protocol.Octets is
      Result : Protocol.Octets (1 .. Text'Length);
   begin
      for I in Text'Range loop
         Result (I - Text'First + 1) := Protocol.Octet (Character'Pos (Text (I)));
      end loop;
      return Result;
   end Bytes;
begin
   declare
      W   : Protocol.Buffer.Writer (16);
      Dec : Protocol.Varnum.Varint_Result;
   begin
      Protocol.Buffer.Put_Varint (W, 0);
      Dec := Protocol.Varnum.Decode_Varint (W.Data (1 .. W.Len), 1);
      Check (Dec.Status = Protocol.Ok and then Dec.Value = 0 and then Dec.Next = 2, "varint 0");

      Protocol.Buffer.Reset (W);
      Protocol.Buffer.Put_Varint (W, 127);
      Dec := Protocol.Varnum.Decode_Varint (W.Data (1 .. W.Len), 1);
      Check (Dec.Status = Protocol.Ok and then Dec.Value = 127, "varint 127");

      Protocol.Buffer.Reset (W);
      Protocol.Buffer.Put_Varint (W, 128);
      Dec := Protocol.Varnum.Decode_Varint (W.Data (1 .. W.Len), 1);
      Check (Dec.Status = Protocol.Ok and then Dec.Value = 128 and then W.Len = 2, "varint 128");

      Protocol.Buffer.Reset (W);
      Protocol.Buffer.Put_Varint (W, 777);
      Dec := Protocol.Varnum.Decode_Varint (W.Data (1 .. W.Len), 1);
      Check
        (Dec.Status = Protocol.Ok and then Dec.Value = 777
         and then W.Data (1) = 16#89# and then W.Data (2) = 16#06#,
         "varint 777");
   end;

   declare
      Overlong : constant Protocol.Octets := (16#80#, 16#00#);
      Dec      : constant Protocol.Varnum.Varint_Result :=
        Protocol.Varnum.Decode_Varint (Overlong, 1);
      Partial  : constant Protocol.Octets := (1 => 16#80#);
      More     : constant Protocol.Varnum.Varint_Result :=
        Protocol.Varnum.Decode_Varint (Partial, 1);
      Wide     : constant Protocol.Octets := (16#FF#, 16#FF#, 16#FF#, 16#FF#, 16#7F#);
      Bad      : constant Protocol.Varnum.Varint_Result :=
        Protocol.Varnum.Decode_Varint (Wide, 1);
   begin
      Check (Dec.Status = Protocol.Rejected, "reject overlong varint");
      Check (More.Status = Protocol.Need_More, "truncated varint");
      Check (Bad.Status = Protocol.Rejected, "reject 5-byte overflow");
   end;

   declare
      --  Try_Decode: incremental VarInt decode (wire-format seam).
      --  Covers minimal/non-minimal encodings, incomplete input,
      --  malformed overlong varints, bit-31 boundary, and exact
      --  boundary values. Verifies both Consumed and Value out
      --  parameters.

      --  Minimal encodings: 1 byte for values 0..127.
      V0    : constant Protocol.Octets := (1 => 16#00#);
      V1    : constant Protocol.Octets := (1 => 16#01#);
      V127  : constant Protocol.Octets := (1 => 16#7F#);

      --  Minimal encodings: 2 bytes for values 128..16383.
      V128   : constant Protocol.Octets := (16#80#, 16#01#);
      V255   : constant Protocol.Octets := (16#FF#, 16#01#);
      V16383 : constant Protocol.Octets := (16#FF#, 16#7F#);

      --  Non-minimal encoding of 128 (3 bytes, leading zero group).
      V128_NM : constant Protocol.Octets := (16#80#, 16#80#, 16#01#);

      --  Incomplete: continuation bit set, no terminator yet.
      Partial1 : constant Protocol.Octets (1 .. 1) := (1 => 16#80#);
      Partial2 : constant Protocol.Octets (1 .. 2) := (16#80#, 16#80#);

      --  Malformed: overlong via non-terminal zero group (value 0 in 2 bytes).
      Overlong0 : constant Protocol.Octets := (16#80#, 16#00#);

      --  Malformed: overlong (6 continuation bytes, exceeds 5-byte ceiling).
      Overlong6 : constant Protocol.Octets :=
        (16#80#, 16#80#, 16#80#, 16#80#, 16#80#, 16#80#);

      --  Malformed: 5th byte's payload exceeds 4 bits (would set bit 32+).
      FifthOverflow : constant Protocol.Octets :=
        (16#FF#, 16#FF#, 16#FF#, 16#FF#, 16#7F#);

      --  Boundary: 2^32 - 1 (max unsigned 32-bit, exact ceiling).
      VMax : constant Protocol.Octets :=
        (16#FF#, 16#FF#, 16#FF#, 16#FF#, 16#0F#);

      --  Boundary: bit 31 set (value 2^31, "negative" on signed read).
      VBit31 : constant Protocol.Octets :=
        (16#80#, 16#80#, 16#80#, 16#80#, 16#08#);

      --  Boundary: 2^32 (exceeds unsigned 32-bit, 5th byte payload = 16).
      VOverflow : constant Protocol.Octets :=
        (16#80#, 16#80#, 16#80#, 16#80#, 16#10#);

      Val : Interfaces.Unsigned_32;
      Con : Natural;
      St  : Protocol.Varnum.VarInt_Status;
   begin
      --  Minimal encodings (single byte).
      St := Protocol.Varnum.Try_Decode (V0, V0'First, Val, Con);
      Check (St = Protocol.Varnum.Ok and then Val = 0 and then Con = 1,
             "try_decode minimal 0");

      St := Protocol.Varnum.Try_Decode (V1, V1'First, Val, Con);
      Check (St = Protocol.Varnum.Ok and then Val = 1 and then Con = 1,
             "try_decode minimal 1");

      St := Protocol.Varnum.Try_Decode (V127, V127'First, Val, Con);
      Check (St = Protocol.Varnum.Ok and then Val = 127 and then Con = 1,
             "try_decode minimal 127");

      --  Minimal encodings (two bytes).
      St := Protocol.Varnum.Try_Decode (V128, V128'First, Val, Con);
      Check (St = Protocol.Varnum.Ok and then Val = 128 and then Con = 2,
             "try_decode minimal 128");

      St := Protocol.Varnum.Try_Decode (V255, V255'First, Val, Con);
      Check (St = Protocol.Varnum.Ok and then Val = 255 and then Con = 2,
             "try_decode minimal 255");

      St := Protocol.Varnum.Try_Decode (V16383, V16383'First, Val, Con);
      Check (St = Protocol.Varnum.Ok and then Val = 16383 and then Con = 2,
             "try_decode minimal 16383");

      --  Non-minimal encoding (lenient decode of 3-byte form of 128).
      St := Protocol.Varnum.Try_Decode (V128_NM, V128_NM'First, Val, Con);
      Check (St = Protocol.Varnum.Ok and then Val = 128 and then Con = 3,
             "try_decode non-minimal 128");

      --  Incomplete: continuation bit set, no terminator in buffer.
      St := Protocol.Varnum.Try_Decode (Partial1, Partial1'First, Val, Con);
      Check (St = Protocol.Varnum.Incomplete and then Con = 0,
             "try_decode incomplete 1 byte");

      St := Protocol.Varnum.Try_Decode (Partial2, Partial2'First, Val, Con);
      Check (St = Protocol.Varnum.Incomplete and then Con = 0,
             "try_decode incomplete 2 bytes");

      --  Incomplete: From is past the end of a non-empty buffer.
      declare
         One : constant Protocol.Octets := (1 => 16#05#);
      begin
         St := Protocol.Varnum.Try_Decode (One, One'Last + 1, Val, Con);
         Check (St = Protocol.Varnum.Incomplete and then Con = 0,
                "try_decode incomplete from past end");
      end;

      --  Malformed: overlong (non-terminal zero group rejects "80 00").
      St := Protocol.Varnum.Try_Decode (Overlong0, Overlong0'First, Val, Con);
      Check (St = Protocol.Varnum.Malformed and then Con = 0,
             "try_decode malformed overlong 0");

      --  Malformed: 6 continuation bytes (exceeds 5-byte ceiling).
      St := Protocol.Varnum.Try_Decode (Overlong6, Overlong6'First, Val, Con);
      Check (St = Protocol.Varnum.Malformed and then Con = 0,
             "try_decode malformed overlong 6 bytes");

      --  Malformed: 5th byte payload > 15 (would set bit 32+).
      St := Protocol.Varnum.Try_Decode
        (FifthOverflow, FifthOverflow'First, Val, Con);
      Check (St = Protocol.Varnum.Malformed and then Con = 0,
             "try_decode malformed 5th byte overflow");

      --  Boundary: 2^32 - 1 (exact max unsigned 32-bit, 5th byte payload 15).
      St := Protocol.Varnum.Try_Decode (VMax, VMax'First, Val, Con);
      Check (St = Protocol.Varnum.Ok
             and then Val = 16#FFFF_FFFF# and then Con = 5,
             "try_decode boundary max u32");

      --  Boundary: bit 31 set (value 2^31, "negative" on signed read).
      --  5th byte payload is 8, which is within the 4-bit limit, so the
      --  decoder accepts it and reports the exact unsigned value.
      St := Protocol.Varnum.Try_Decode (VBit31, VBit31'First, Val, Con);
      Check (St = Protocol.Varnum.Ok
             and then Val = 16#8000_0000# and then Con = 5,
             "try_decode boundary bit 31 set");

      --  Boundary: 2^32 (5th byte payload is 16, exceeds 4-bit limit).
      St := Protocol.Varnum.Try_Decode
        (VOverflow, VOverflow'First, Val, Con);
      Check (St = Protocol.Varnum.Malformed and then Con = 0,
             "try_decode boundary 2^32 overflow");

      --  From offset: skip a leading byte and decode the trailing varint.
      declare
         Prefixed : constant Protocol.Octets := (16#AA#, 16#00#);
      begin
         St := Protocol.Varnum.Try_Decode (Prefixed, 2, Val, Con);
         Check (St = Protocol.Varnum.Ok
                and then Val = 0 and then Con = 1,
                "try_decode from offset 2");
      end;
   end;

   declare
      Long : Protocol.Buffer.Writer (16);
      Dec  : Protocol.Varnum.Varlong_Result;
   begin
      Protocol.Buffer.Put_Varint (Long, 777);
      Dec := Protocol.Varnum.Decode_Varlong (Long.Data (1 .. Long.Len), 1);
      Check (Dec.Status = Protocol.Ok and then Dec.Value = 777, "varlong 777");
   end;

   declare
      Payload : Protocol.Buffer.Writer (64);
      Wire    : Protocol.Buffer.Writer (80);
      Dec     : Protocol.Frame.Frame_Decode;
      Hello   : Protocol.Packets.Handshake;
   begin
      Protocol.Buffer.Put_Varint
        (Payload, Interfaces.Unsigned_32 (Protocol.Ids.Protocol_Id (Protocol.Ids.Sb_Handshake_Intention)));
      Protocol.Buffer.Put_Varint (Payload, 777);
      Protocol.Buffer.Put_String (Payload, "localhost");
      Protocol.Buffer.Put_U16 (Payload, 25565);
      Protocol.Buffer.Put_Varint (Payload, 1);
      Check (Protocol.Packets.Frame (Wire, Payload), "handshake framed");
      Dec := Protocol.Frame.Decode_Frame (Wire.Data (1 .. Wire.Len), 1);
      Check
        (Dec.Status = Protocol.Ok
         and then Dec.Packet_Id = Protocol.Ids.Protocol_Id (Protocol.Ids.Sb_Handshake_Intention),
         "handshake frame id");
      Hello := Protocol.Packets.Decode_Handshake (Wire.Data (Dec.Payload_First .. Dec.Payload_Last));
      Check
        (Hello.Status = Protocol.Ok and then Hello.Version = 777
         and then Hello.Port = 25565 and then Hello.Intent = 1
         and then Hello.Address (1 .. Hello.Addr_Len) = "localhost",
         "handshake fields");
   end;

   declare
      S        : Ingress.Session;
      Payload  : Protocol.Buffer.Writer (64);
      Wire     : Protocol.Buffer.Writer (96);
      Request  : Protocol.Buffer.Writer (16);
      Framed_R : Protocol.Buffer.Writer (32);
      Incoming : Protocol.Octets (1 .. 160) := (others => 0);
      Used     : Natural := 0;
      Outgoing : Protocol.Buffer.Writer (1024);
      Consumed : Natural;
      Close_Now : Boolean;
      Text     : String (1 .. 1024) := (others => ' ');
   begin
      Protocol.Buffer.Put_Varint
        (Payload, Interfaces.Unsigned_32 (Protocol.Ids.Protocol_Id (Protocol.Ids.Sb_Handshake_Intention)));
      Protocol.Buffer.Put_Varint (Payload, 777);
      Protocol.Buffer.Put_String (Payload, "localhost");
      Protocol.Buffer.Put_U16 (Payload, 25565);
      Protocol.Buffer.Put_Varint (Payload, 1);
      Check (Protocol.Packets.Frame (Wire, Payload), "status handshake");
      Protocol.Buffer.Put_Varint
        (Request, Interfaces.Unsigned_32 (Protocol.Ids.Protocol_Id (Protocol.Ids.Sb_Status_Status_Request)));
      Check (Protocol.Packets.Frame (Framed_R, Request), "status request");
      Incoming (1 .. Wire.Len) := Wire.Data (1 .. Wire.Len);
      Incoming (Wire.Len + 1 .. Wire.Len + Framed_R.Len) := Framed_R.Data (1 .. Framed_R.Len);
      Used := Wire.Len + Framed_R.Len;
      Ingress.Ingest (S, Incoming (1 .. Used), 1, Consumed, Outgoing, Close_Now);
      Check (not Close_Now and then S.State = Protocol.Status, "entered status");
      for I in 1 .. Outgoing.Len loop
         Text (I) := Character'Val (Natural (Outgoing.Data (I)));
      end loop;
      Check (Outgoing.Len > 0, "status response bytes");
      declare
         Slice : constant String := Text (1 .. Outgoing.Len);
      begin
         Check
           (Ada.Strings.Fixed.Index (Slice, "26.3") > 0
            and then Ada.Strings.Fixed.Index (Slice, "777") > 0,
            "status json");
      end;
   end;

   declare
      Empty : constant Protocol.Octets (1 .. 0) := (others => 0);
      ABC   : constant Protocol.Octets := Bytes ("abc");
      Notch : constant Auth.Digest := Auth.Offline_UUID ("Notch");
   begin
      Check (Hex (Auth.MD5 (Empty)) = "d41d8cd98f00b204e9800998ecf8427e", "md5 empty");
      Check (Hex (Auth.MD5 (ABC)) = "900150983cd24fb0d6963f7d28e17f72", "md5 abc");
      Check (Hex (Notch) = "b50ad385829d3141a2167e7d7539ba7f", "offline notch");
   end;

   declare
      State : Kernel.Authority;
      Before : Kernel.Authority;
      Move : Kernel.Move_Request;
      Result : Kernel.Attempt;
   begin
      Before := State;
      Kernel.Try_Move (State, Move, Result);
      Check (Result = Kernel.Rejected, "move rejected");
      Check (State = Before, "move rejection preserves state");
      State.Chunk := Kernel.Active;
      Move := (Player_Live => True, Chunk_Active => True, Collision_Free => True,
               Within_Rules => True, Target => (3, 4, 5));
      Kernel.Try_Move (State, Move, Result);
      Check (Result = Kernel.Accepted, "move accepted");
      Check (State.Position.X = 3 and then State.Position.Y = 4, "move committed");
   end;

   declare
      Source : Kernel.Stack := (Item => 1, Count => 10, Max_Count => 64);
      Dest   : Kernel.Stack := (Item => 0, Count => 0, Max_Count => 64);
      Before_S : constant Kernel.Stack := Source;
      Before_D : constant Kernel.Stack := Dest;
      Result : Kernel.Attempt;
   begin
      Kernel.Try_Inventory_Move (Source, Dest, 0, Result);
      Check (Result = Kernel.Rejected, "zero move");
      Check (Source = Before_S and then Dest = Before_D, "zero move preserves");
      Kernel.Try_Inventory_Move (Source, Dest, 4, Result);
      Check (Result = Kernel.Accepted, "move 4");
      Check (Source.Count + Dest.Count = 10, "inventory conserved");
      Check (Dest.Item = 1 and then Source.Count = 6, "move split counts");
   end;

   declare
      Pool : Kernel.Entity_Pool := (others => (Live => False, Generation => 0));
      Handle : Kernel.Entity_Handle := (ID => 3, Generation => 1);
      Result : Kernel.Attempt;
   begin
      Pool (3) := (Live => True, Generation => 1);
      Check (Kernel.Handle_Valid (Pool, Handle), "handle live");
      Kernel.Try_Retire_Handle (Pool, Handle, Result);
      Check (Result = Kernel.Accepted, "retire");
      Check (not Kernel.Handle_Valid (Pool, Handle), "stale handle rejected");
      Kernel.Try_Retire_Handle (Pool, Handle, Result);
      Check (Result = Kernel.Rejected, "second retire");
   end;

   declare
      State : Kernel.Authority;
      Gen : constant Natural := State.Committed_Generation;
      Result : Kernel.Attempt;
   begin
      Kernel.Try_Save (State, Kernel.Take_Snapshot, False, Result);
      Check (Result = Kernel.Accepted, "snapshot");
      Kernel.Try_Save (State, Kernel.Commit, False, Result);
      Check (Result = Kernel.Rejected, "undurable commit");
      Check (State.Committed_Generation = Gen, "failed save does not commit");
      Kernel.Try_Save (State, Kernel.Take_Snapshot, False, Result);
      Check (Result = Kernel.Accepted, "snapshot again");
      Kernel.Try_Save (State, Kernel.Commit, True, Result);
      Check (Result = Kernel.Accepted, "durable commit");
      Check (State.Committed_Generation = Gen + 1, "generation advanced");
   end;

   declare
      State : Kernel.Authority;
      Result : Kernel.Attempt;
   begin
      Kernel.Try_Chunk_Transition (State, Kernel.Active, Result);
      Check (Result = Kernel.Rejected, "illegal chunk");
      Check (State.Chunk = Kernel.Unloaded, "chunk unchanged");
      Kernel.Try_Chunk_Transition (State, Kernel.Loading, Result);
      Check (Result = Kernel.Accepted, "start load");
      Kernel.Try_Set_Permission (State, False, 4, Result);
      Check (Result = Kernel.Rejected, "permission denied");
      Check (State.Permission = 0, "permission unchanged");
      Kernel.Try_Set_Permission (State, True, 2, Result);
      Check (Result = Kernel.Accepted, "permission set");
      Kernel.Try_Execute_Command (State, Kernel.Teleport, Result);
      Check (Result = Kernel.Accepted, "teleport allowed");
      Kernel.Try_Execute_Command (State, Kernel.Unknown, Result);
      Check (Result = Kernel.Rejected, "unknown command");
   end;

   declare
      Seed : Interfaces.Unsigned_32 := 16#A5A5_1234#;
      Buf  : Protocol.Octets (1 .. 32);
   begin
      for Case_Index in 1 .. 64 loop
         for I in Buf'Range loop
            Seed := Seed * 1664525 + 1013904223;
            Buf (I) := Protocol.Octet (Seed mod 256);
         end loop;
         declare
            Dec : constant Protocol.Varnum.Varint_Result :=
              Protocol.Varnum.Decode_Varint (Buf, 1);
            Frm : constant Protocol.Frame.Frame_Decode :=
              Protocol.Frame.Decode_Frame (Buf, 1);
         begin
            if Dec.Next > Buf'Last + 1 or else Frm.Next > Buf'Last + 1 then
               Check (False, "fuzz cursor");
            end if;
         end;
      end loop;
   end;

   if Protocol.Ids.Protocol_Id (Protocol.Ids.Sb_Handshake_Intention) /= 0
     or else Protocol.Ids.Protocol_Id (Protocol.Ids.Cb_Status_Status_Response) /= 0
     or else Protocol.Ids.Protocol_Id (Protocol.Ids.Cb_Login_Login_Disconnect) /= 0
   then
      Check (False, "pinned packet ids");
   end if;

   if Failures = 0 then
      Ada.Text_IO.Put_Line ("adacraft tests passed");
   else
      Ada.Text_IO.Put_Line ("adacraft tests failed:" & Failures'Image);
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
   end if;
end Adacraft_Tests;
