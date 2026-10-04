with Ada.Command_Line;
with Ada.Streams;
with Ada.Strings.Fixed;
with Ada.Unchecked_Deallocation;
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

   declare
      package Streams renames Ada.Streams;
      package Frame renames Adacraft.Protocol.Frame;
      use type Streams.Stream_Element;
      use type Streams.Stream_Element_Offset;
      use type Frame.Encode_Status;

      subtype SE is Streams.Stream_Element;
      subtype SEO is Streams.Stream_Element_Offset;
      subtype SEA is Streams.Stream_Element_Array;

      type SEA_Access is access SEA;
      procedure Free is new Ada.Unchecked_Deallocation (SEA, SEA_Access);

      function Fill (I : SEO) return SE is (SE (I mod 251));

      procedure Small_Case
        (N          : SEO;
         Prefix_Len : SEO;
         P1, P2     : SE;
         Name       : String)
      is
         Payload : SEA (1 .. N);
         Output  : SEA (1 .. Prefix_Len + N) := (others => 0);
         Last    : SEO;
         Status  : Frame.Encode_Status;
         Same    : Boolean := True;
      begin
         for I in Payload'Range loop
            Payload (I) := Fill (I);
         end loop;
         Frame.Encode (Payload, Output, Last, Status);
         Check (Status = Frame.Ok, Name & " status");
         Check (Last = Prefix_Len + N, Name & " last");
         Check (Output (1) = P1, Name & " prefix 1");
         if Prefix_Len = 2 then
            Check (Output (2) = P2, Name & " prefix 2");
         end if;
         for I in 1 .. N loop
            if Output (Prefix_Len + I) /= Payload (I) then
               Same := False;
            end if;
         end loop;
         Check (Same, Name & " body copy");
      end Small_Case;
   begin
      Small_Case (0, 1, 16#00#, 0, "frame 0-byte");
      Small_Case (127, 1, 16#7F#, 0, "frame 127-byte");
      Small_Case (128, 2, 16#80#, 16#01#, "frame 128-byte");

      declare
         Max_Len : constant := 2_097_151;
         Payload : SEA_Access := new SEA (1 .. Max_Len);
         Output  : SEA_Access := new SEA (1 .. Max_Len + 3);
         Last    : SEO;
         Status  : Frame.Encode_Status;
         Same    : Boolean := True;
      begin
         for I in Payload'Range loop
            Payload (I) := Fill (I);
         end loop;
         Output.all := (others => 0);
         Frame.Encode (Payload.all, Output.all, Last, Status);
         Check (Status = Frame.Ok, "frame max status");
         Check (Last = 2_097_154, "frame max last");
         Check
           (Output (1) = 16#FF# and then Output (2) = 16#FF#
            and then Output (3) = 16#7F#,
            "frame max prefix");
         for I in SEO'(1) .. Max_Len loop
            if I = 1 or else I = 2 or else I = 1000 or else I = 1_048_576
              or else I = Max_Len - 1 or else I = Max_Len
            then
               if Output (3 + I) /= Payload (I) then
                  Same := False;
               end if;
            end if;
         end loop;
         Check (Same, "frame max body samples");
         Free (Payload);
         Free (Output);
      end;

      declare
         Payload : SEA_Access := new SEA (1 .. 2_097_152);
         Output  : SEA_Access := new SEA (1 .. 4);
         Last    : SEO;
         Status  : Frame.Encode_Status;
      begin
         Payload.all := (others => 7);
         Output.all := (others => 16#AA#);
         Frame.Encode (Payload.all, Output.all, Last, Status);
         Check (Status = Frame.Body_Too_Long, "frame body too long");
         Check (Output (1) = 16#AA# and then Output (4) = 16#AA#,
                "frame body too long writes nothing");
         Free (Payload);
         Free (Output);
      end;

      declare
         Payload : constant SEA (1 .. 1) := (1 => 5);
         Output  : SEA (1 .. 1) := (1 => 16#AA#);
         Last    : SEO;
         Status  : Frame.Encode_Status;
      begin
         Frame.Encode (Payload, Output, Last, Status);
         Check (Status = Frame.Output_Too_Small, "frame output too small");
         Check (Output (1) = 16#AA#, "frame output too small writes nothing");
      end;
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
