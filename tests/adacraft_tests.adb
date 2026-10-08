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
with Test_Protocol_Packet_Encoder;

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

   declare
      package Streams renames Ada.Streams;
      package Frame renames Adacraft.Protocol.Frame;
      use type Streams.Stream_Element;
      use type Streams.Stream_Element_Offset;
      use type Frame.Feed_Status;

      subtype SE is Streams.Stream_Element;
      subtype SEO is Streams.Stream_Element_Offset;
      subtype SEA is Streams.Stream_Element_Array;

      type Dec_Access is access Frame.Decoder_Type;
      procedure Free_Dec is new Ada.Unchecked_Deallocation
        (Frame.Decoder_Type, Dec_Access);

      D : Dec_Access := new Frame.Decoder_Type;

      Max_Frames : constant := 32;
      Count    : Natural := 0;
      Lens     : array (1 .. Max_Frames) of Natural := (others => 0);
      Starts   : array (1 .. Max_Frames) of Natural := (others => 0);
      Data     : array (1 .. 1024) of SE := (others => 0);
      Data_Len : Natural := 0;

      procedure Fresh is
      begin
         Free_Dec (D);
         D := new Frame.Decoder_Type;
         Count := 0;
         Data_Len := 0;
      end Fresh;

      procedure Record_Frame (F : in SEA) is
      begin
         if Count < Max_Frames and then Data_Len + F'Length <= Data'Length then
            Count := Count + 1;
            Lens (Count) := F'Length;
            Starts (Count) := Data_Len;
            for I in F'Range loop
               Data_Len := Data_Len + 1;
               Data (Data_Len) := F (I);
            end loop;
         else
            Count := Count + 1;
         end if;
      end Record_Frame;

      function Frame_Is (N : Positive; Expected : SEA) return Boolean is
      begin
         if N > Count or else N > Max_Frames
           or else Lens (N) /= Expected'Length
         then
            return False;
         end if;
         for K in 0 .. Expected'Length - 1 loop
            if Data (Starts (N) + K + 1) /= Expected (Expected'First + SEO (K))
            then
               return False;
            end if;
         end loop;
         return True;
      end Frame_Is;

      procedure Feed_Chunk (C : in SEA; Name : in String) is
         St : Frame.Feed_Status;
      begin
         Frame.Feed (D.all, C, Record_Frame'Access, St);
         Check (St = Frame.Success, Name & " status");
      end Feed_Chunk;

      function Pat (I : SEO) return SE is (SE (I mod 251));

      E_12   : constant SEA := (1 => 1, 2 => 2);
      E_9    : constant SEA := (1 => 9);
      E_1_5  : constant SEA := (1 => 1, 2 => 2, 3 => 3, 4 => 4, 5 => 5);
      E_Nil  : constant SEA (1 .. 0) := (others => 0);
   begin
      --  T-1: body split across chunks.
      declare
         W : constant SEA (1 .. 6) := (5, 1, 2, 3, 4, 5);
      begin
         Fresh;
         Feed_Chunk (W (1 .. 3), "T-1 a");
         Check (Count = 0, "T-1 no frame after first chunk");
         Feed_Chunk (W (4 .. 5), "T-1 b");
         Check (Count = 0, "T-1 no frame after second chunk");
         Feed_Chunk (W (6 .. 6), "T-1 c");
         Check (Count = 1, "T-1 one frame");
         Check (Frame_Is (1, E_1_5), "T-1 body");
      end;

      --  T-2: byte-at-a-time feeding.
      declare
         W : constant SEA (1 .. 7) := (3, 10, 20, 30, 0, 1, 99);
         E_3 : constant SEA := (1 => 10, 2 => 20, 3 => 30);
         E_1 : constant SEA := (1 => 99);
      begin
         Fresh;
         for I in SEO range 1 .. 7 loop
            Feed_Chunk (W (I .. I), "T-2 byte");
            case I is
               when 1 | 2 | 3 => Check (Count = 0, "T-2 count early");
               when 4 => Check (Count = 1, "T-2 count after 4");
               when 5 => Check (Count = 2, "T-2 count after 5");
               when 6 => Check (Count = 2, "T-2 count after 6");
               when others => Check (Count = 3, "T-2 count after 7");
            end case;
         end loop;
         Check (Frame_Is (1, E_3), "T-2 frame 1");
         Check (Frame_Is (2, E_Nil), "T-2 frame 2 empty");
         Check (Frame_Is (3, E_1), "T-2 frame 3");
      end;

      --  T-3: prefix split across chunks.
      declare
         W : SEA (1 .. 202);
      begin
         W (1) := 16#C8#;
         W (2) := 16#01#;
         for I in SEO range 3 .. 202 loop
            W (I) := Pat (I - 2);
         end loop;
         Fresh;
         Feed_Chunk (W (1 .. 1), "T-3 a");
         Check (Count = 0, "T-3 after prefix byte 1");
         Feed_Chunk (W (2 .. 50), "T-3 b");
         Check (Count = 0, "T-3 after prefix byte 2 and partial body");
         Feed_Chunk (W (51 .. 202), "T-3 c");
         Check (Count = 1, "T-3 one frame");
         Check (Frame_Is (1, W (3 .. 202)), "T-3 body");
      end;

      --  T-4: multiple frames in one chunk plus trailing partial frame.
      declare
         W : constant SEA (1 .. 9) := (2, 1, 2, 0, 1, 9, 4, 5, 6);
         R : constant SEA (1 .. 2) := (7, 8);
         E_5_8 : constant SEA := (1 => 5, 2 => 6, 3 => 7, 4 => 8);
      begin
         Fresh;
         Feed_Chunk (W, "T-4 a");
         Check (Count = 3, "T-4 three complete frames");
         Check (Frame_Is (1, E_12), "T-4 frame 1");
         Check (Frame_Is (2, E_Nil), "T-4 frame 2 empty");
         Check (Frame_Is (3, E_9), "T-4 frame 3");
         Feed_Chunk (R, "T-4 b");
         Check (Count = 4, "T-4 trailing frame completed");
         Check (Frame_Is (4, E_5_8), "T-4 frame 4");
      end;

      --  T-5: non-minimal prefixes.
      declare
         W : constant SEA (1 .. 10) :=
           (16#80#, 16#00#, 16#85#, 16#80#, 16#00#, 1, 2, 3, 4, 5);
      begin
         Fresh;
         Feed_Chunk (W, "T-5");
         Check (Count = 2, "T-5 two frames");
         Check (Lens (1) = 0 and then Frame_Is (1, E_Nil), "T-5 length 0");
         Check (Lens (2) = 5 and then Frame_Is (2, E_1_5), "T-5 length 5");
      end;

      --  T-11: non-1 lower bounds and zero-length chunks.
      declare
         Neg  : constant SEA (-1 .. 1) := (2, 7, 8);
         High : constant SEA (100 .. 102) := (2, 7, 8);
         Nil1 : constant SEA (1 .. 0) := (others => 0);
         Nil5 : constant SEA (5 .. 4) := (others => 0);
         Mid  : constant SEA (50 .. 50) := (1 => 2);
         Tail : constant SEA (60 .. 61) := (7, 8);
         E_78 : constant SEA := (1 => 7, 2 => 8);
      begin
         Fresh;
         Feed_Chunk (Neg, "T-11 negative lower bound");
         Check (Count = 1 and then Frame_Is (1, E_78), "T-11 negative bound frame");

         Fresh;
         Feed_Chunk (High, "T-11 lower bound 100");
         Check (Count = 1 and then Frame_Is (1, E_78), "T-11 bound 100 frame");

         Fresh;
         Feed_Chunk (Nil1, "T-11 empty 1");
         Feed_Chunk (Nil5, "T-11 empty 2");
         Check (Count = 0, "T-11 empty chunks no callbacks");

         Feed_Chunk (Mid, "T-11 prefix");
         Feed_Chunk (Nil1, "T-11 empty mid-frame");
         Check (Count = 0, "T-11 no callback mid-frame");
         Feed_Chunk (Tail, "T-11 tail");
         Check (Count = 1 and then Frame_Is (1, E_78), "T-11 frame after empty chunk");
      end;

      --  T-6 .. T-10: limits and errors.
      declare
         Max_Len : constant := 2_097_151;

         type SEA_Access is access SEA;
         procedure Free_Wire is new Ada.Unchecked_Deallocation
           (SEA, SEA_Access);

         Wire      : SEA_Access;
         Big_Count : Natural := 0;
         Big_Len   : Natural := 0;
         Big_Match : Boolean := True;
         St        : Frame.Feed_Status;
         Nil       : constant SEA (1 .. 0) := (others => 0);

         procedure Record_Big (F : in SEA) is
         begin
            Big_Count := Big_Count + 1;
            Big_Len := F'Length;
            for K in 0 .. F'Length - 1 loop
               if F (F'First + SEO (K)) /= Pat (SEO (K) + 1) then
                  Big_Match := False;
               end if;
            end loop;
         end Record_Big;

         procedure Expect_Error (C : in SEA; Name : in String) is
            S : Frame.Feed_Status;
         begin
            Frame.Feed (D.all, C, Record_Frame'Access, S);
            Check (S = Frame.Framing_Error, Name & " status");
         end Expect_Error;
      begin
         --  T-6: maximum-size body, whole and split.
         Wire := new SEA (1 .. Max_Len + 3);
         Wire (1) := 16#FF#;
         Wire (2) := 16#FF#;
         Wire (3) := 16#7F#;
         for I in SEO range 1 .. Max_Len loop
            Wire (3 + I) := Pat (I);
         end loop;

         Fresh;
         Frame.Feed (D.all, Wire.all, Record_Big'Access, St);
         Check (St = Frame.Success, "T-6 whole status");
         Check (Big_Count = 1, "T-6 whole one frame");
         Check (Big_Len = Max_Len, "T-6 whole length");
         Check (Big_Match, "T-6 whole content");

         Big_Count := 0;
         Big_Len := 0;
         Big_Match := True;
         Fresh;
         Frame.Feed (D.all, Wire (1 .. 2), Record_Big'Access, St);
         Check (St = Frame.Success, "T-6 split a status");
         Frame.Feed (D.all, Wire (3 .. 1000), Record_Big'Access, St);
         Check (St = Frame.Success, "T-6 split b status");
         Frame.Feed
           (D.all, Wire (1001 .. 1_048_576), Record_Big'Access, St);
         Check (St = Frame.Success, "T-6 split c status");
         Frame.Feed
           (D.all, Wire (1_048_577 .. Max_Len + 2), Record_Big'Access, St);
         Check (St = Frame.Success, "T-6 split d status");
         Check (Big_Count = 0, "T-6 split no frame before last byte");
         Frame.Feed
           (D.all, Wire (Max_Len + 3 .. Max_Len + 3), Record_Big'Access, St);
         Check (St = Frame.Success, "T-6 split e status");
         Check (Big_Count = 1, "T-6 split one frame");
         Check (Big_Len = Max_Len, "T-6 split length");
         Check (Big_Match, "T-6 split content");
         Free_Wire (Wire);

         --  T-7: overlong prefix is rejected at the third byte.
         declare
            Three : constant SEA (1 .. 3) := (16#80#, 16#80#, 16#80#);
            Four  : constant SEA (1 .. 8) :=
              (16#80#, 16#80#, 16#80#, 16#01#, 1, 0, 0, 0);
         begin
            Fresh;
            Expect_Error (Three, "T-7 three bytes");
            Check (Count = 0, "T-7 no callbacks");

            Fresh;
            Feed_Chunk (Three (1 .. 2), "T-7 first two bytes");
            Expect_Error (Three (3 .. 3), "T-7 third byte");
            Check (Count = 0, "T-7 no callbacks split");

            Fresh;
            Expect_Error (Four, "T-7 four bytes and trailing");
            Check (Count = 0, "T-7 no callbacks trailing");
         end;

         --  T-8: oversize length encoding.
         declare
            Over : constant SEA (1 .. 4) :=
              (16#80#, 16#80#, 16#80#, 16#01#);
         begin
            Fresh;
            Expect_Error (Over, "T-8 oversize");
            Check (Count = 0, "T-8 no callbacks");
         end;

         --  T-9: sticky failure.
         declare
            Bad  : constant SEA (1 .. 3) := (16#80#, 16#80#, 16#80#);
            Good : constant SEA (1 .. 3) := (2, 1, 2);
            Zero : constant SEA (1 .. 1) := (1 => 0);
         begin
            Fresh;
            Expect_Error (Bad, "T-9 initial");
            Expect_Error (Good, "T-9 good chunk after failure");
            Expect_Error (Nil, "T-9 empty chunk after failure");
            Expect_Error (Zero, "T-9 zero-length frame after failure");
            Expect_Error (Nil, "T-9 empty chunk again");
            Check (Count = 0, "T-9 no callbacks after failure");
         end;

         --  T-10: good frames delivered, then an error in the same chunk.
         declare
            W : constant SEA (1 .. 9) :=
              (2, 1, 2, 0, 16#80#, 16#80#, 16#80#, 1, 5);
            After : constant SEA (1 .. 2) := (1, 7);
         begin
            Fresh;
            Expect_Error (W, "T-10 chunk");
            Check (Count = 2, "T-10 prior frames delivered");
            Check (Frame_Is (1, E_12), "T-10 frame 1");
            Check (Frame_Is (2, E_Nil), "T-10 frame 2 empty");
            Expect_Error (After, "T-10 later chunk");
            Check (Count = 2, "T-10 no later callbacks");
            Check (Frame_Is (1, E_12), "T-10 frame 1 kept");
         end;
      end;

      Free_Dec (D);
   end;

   Test_Protocol_Packet_Encoder;
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
