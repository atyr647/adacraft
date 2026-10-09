--  Encryption wiring unit tests, no network.
--  Uses injected fixed keys; #213 fake not needed (no session touched).
with Ada.Command_Line;
with Ada.Streams;
with Ada.Text_IO;
with Interfaces;
with Adacraft.Network;
with Adacraft.Protocol;
with Adacraft.Protocol.Buffer;
with Adacraft.Protocol.Frame;
with Adacraft.Protocol.Login;
with Adacraft.Protocol.Packets;
with Adacraft.Protocol.State;

procedure Test_Login_Encryption is
   package Net renames Adacraft.Network;
   package Proto renames Adacraft.Protocol;
   package Buf renames Adacraft.Protocol.Buffer;
   package Frm renames Adacraft.Protocol.Frame;
   package Log renames Adacraft.Protocol.Login;
   package Pkts renames Adacraft.Protocol.Packets;
   package St renames Adacraft.Protocol.State;

   use type Ada.Streams.Stream_Element_Offset;
   use type Ada.Streams.Stream_Element;
   use type Proto.Octet;
   use type Frm.Feed_Status;
   use type Pkts.Start_Dispatch_Outcome;
   use type Pkts.Key_Dispatch_Outcome;
   use type St.Connection_State;

   Failures : Natural := 0;

   procedure Check (Cond : Boolean; Name : String) is
   begin
      if not Cond then
         Failures := Failures + 1;
         Ada.Text_IO.Put_Line ("FAIL encryption: " & Name);
      end if;
   end Check;

   Secret : constant Net.Shared_Secret_Bytes :=
     (16#00#, 16#01#, 16#02#, 16#03#, 16#04#, 16#05#, 16#06#, 16#07#,
      16#08#, 16#09#, 16#0A#, 16#0B#, 16#0C#, 16#0D#, 16#0E#, 16#0F#);
   Token : constant Net.Verify_Token_Bytes := (16#AA#, 16#BB#, 16#CC#, 16#DD#);
   Wrong_Token : constant Net.Verify_Token_Bytes :=
     (16#00#, 16#00#, 16#00#, 16#00#);
   Pub : constant Proto.Octets (1 .. 4) := (16#11#, 16#22#, 16#33#, 16#44#);

   Dummy_Uuid : constant Proto.Octets (1 .. 16) :=
     (16#01#, 16#02#, 16#03#, 16#04#, 16#05#, 16#06#, 16#07#, 16#08#,
      16#09#, 16#0A#, 16#0B#, 16#0C#, 16#0D#, 16#0E#, 16#0F#, 16#10#);

   function Build_Start_Payload return Proto.Octets is
      W : Buf.Writer (64);
   begin
      Buf.Put_String (W, "Notch");
      Buf.Put_Bytes (W, Dummy_Uuid);
      declare
         R : Proto.Octets (1 .. W.Len);
      begin
         for I in 1 .. W.Len loop
            R (I) := W.Data (I);
         end loop;
         return R;
      end;
   end Build_Start_Payload;

   function Build_Key_Payload
     (Sec : Proto.Octets; Tok : Proto.Octets) return Proto.Octets
   is
      W : Buf.Writer (128);
   begin
      Buf.Put_Varint (W, Interfaces.Unsigned_32 (Sec'Length));
      Buf.Put_Bytes (W, Sec);
      Buf.Put_Varint (W, Interfaces.Unsigned_32 (Tok'Length));
      Buf.Put_Bytes (W, Tok);
      declare
         R : Proto.Octets (1 .. W.Len);
      begin
         for I in 1 .. W.Len loop
            R (I) := W.Data (I);
         end loop;
         return R;
      end;
   end Build_Key_Payload;

   function To_SEA (O : Proto.Octets) return Ada.Streams.Stream_Element_Array is
      R : Ada.Streams.Stream_Element_Array
        (1 .. Ada.Streams.Stream_Element_Offset (O'Length));
   begin
      for I in 1 .. O'Length loop
         R (Ada.Streams.Stream_Element_Offset (I)) :=
           Ada.Streams.Stream_Element (O (O'First + I - 1));
      end loop;
      return R;
   end To_SEA;

   function To_Octets
     (S : Ada.Streams.Stream_Element_Array) return Proto.Octets
   is
      R : Proto.Octets (1 .. Natural (S'Length));
      I : Natural := 1;
   begin
      for E of S loop
         R (I) := Proto.Octet (E);
         I := I + 1;
      end loop;
      return R;
   end To_Octets;

   function Same_SEA
     (A, B : Ada.Streams.Stream_Element_Array) return Boolean
   is
   begin
      if A'Length /= B'Length then
         return False;
      end if;
      for I in 1 .. Natural (A'Length) loop
         if A (A'First + Ada.Streams.Stream_Element_Offset (I) - 1) /=
           B (B'First + Ada.Streams.Stream_Element_Offset (I) - 1)
         then
            return False;
         end if;
      end loop;
      return True;
   end Same_SEA;

   --  Frame helpers over Stream_Element_Array via Frame.Feed.
   Frames_Seen : Natural := 0;
   Last_Len : Natural := 0;

   procedure On_Frame (F : in Frm.Byte_Array) is
   begin
      Frames_Seen := Frames_Seen + 1;
      Last_Len := Natural (F'Length);
   end On_Frame;

   procedure Reset_Frames is
   begin
      Frames_Seen := 0;
      Last_Len := 0;
   end Reset_Frames;

   function Frame_Wire (P_Body : Ada.Streams.Stream_Element_Array)
     return Ada.Streams.Stream_Element_Array
   is
      Out_Wire : Ada.Streams.Stream_Element_Array (1 .. 4_096);
      Last : Ada.Streams.Stream_Element_Offset;
      Status : Frm.Encode_Status;
   begin
      Frm.Encode (P_Body, Out_Wire, Last, Status);
      if Status /= Frm.Ok then
         return (1 .. 0 => 0);
      end if;
      return Out_Wire (Out_Wire'First .. Last);
   end Frame_Wire;

begin
   --  1. Bidirectional client-cipher round trip with known secret.
   declare
      A, B : Net.Connection_Context;
      Plain : Ada.Streams.Stream_Element_Array (1 .. 8) :=
        (1, 2, 3, 4, 5, 6, 7, 8);
      Wire : Ada.Streams.Stream_Element_Array (1 .. 8) := Plain;
      Back : Ada.Streams.Stream_Element_Array (1 .. 8);
      Ok1, Ok2 : Boolean;
   begin
      Ok1 := Net.Try_Enable_Encryption (A, Secret);
      Ok2 := Net.Try_Enable_Encryption (B, Secret);
      Check (Ok1 and Ok2, "roundtrip enable once");
      Check (Net.Is_Encryption_Enabled (A), "roundtrip enabled A");
      Net.On_Send_Frame (A, Wire);
      Check (not Same_SEA (Wire, Plain), "roundtrip ciphertext differs");
      Back := Wire;
      Net.On_Receive_Bytes (B, Back);
      Check (Same_SEA (Back, Plain), "roundtrip bidirectional decrypt");
      --  Reverse direction.
      Wire := Plain;
      Net.On_Send_Frame (B, Wire);
      Back := Wire;
      Net.On_Receive_Bytes (A, Back);
      Check (Same_SEA (Back, Plain), "roundtrip reverse decrypt");
   end;

   --  2. Multi-packet continuity both directions (no per-packet reset).
   declare
      A, B : Net.Connection_Context;
      Dummy : Boolean;
      P1 : Ada.Streams.Stream_Element_Array (1 .. 4) := (10, 20, 30, 40);
      P2 : Ada.Streams.Stream_Element_Array (1 .. 4) := (50, 60, 70, 80);
      W1 : Ada.Streams.Stream_Element_Array (1 .. 4) := P1;
      W2 : Ada.Streams.Stream_Element_Array (1 .. 4) := P2;
      R1, R2 : Ada.Streams.Stream_Element_Array (1 .. 4);
   begin
      Dummy := Net.Try_Enable_Encryption (A, Secret);
      Dummy := Net.Try_Enable_Encryption (B, Secret);
      Net.On_Send_Frame (A, W1);
      Net.On_Send_Frame (A, W2);
      R1 := W1;
      R2 := W2;
      Net.On_Receive_Bytes (B, R1);
      Net.On_Receive_Bytes (B, R2);
      Check (Same_SEA (R1, P1), "continuity pkt1");
      Check (Same_SEA (R2, P2), "continuity pkt2");
      Check (not Same_SEA (W1, W2) or else Same_SEA (P1, P2),
        "continuity distinct keystream");
   end;

   --  3. Leftover plaintext-response + encrypted bytes in one read.
   declare
      First, Count : Natural;
   begin
      Pkts.Leftover_Bounds (Consumed => 10, Last => 14,
        First => First, Count => Count);
      Check (First = 11 and Count = 4, "leftover bounds some");
      Pkts.Leftover_Bounds (Consumed => 10, Last => 10,
        First => First, Count => Count);
      Check (Count = 0, "leftover bounds none");
      --  Leftover bytes decrypt before framing: encrypt then decrypt slice.
      declare
         A : Net.Connection_Context;
         Dummy : Boolean := Net.Try_Enable_Encryption (A, Secret);
         pragma Unreferenced (Dummy);
         Leftover_Body : Ada.Streams.Stream_Element_Array (1 .. 3) := (9, 9, 9);
         Wire : constant Ada.Streams.Stream_Element_Array := Frame_Wire (Leftover_Body);
         Enc : Ada.Streams.Stream_Element_Array (Wire'Range) := Wire;
         Dec : Ada.Streams.Stream_Element_Array (Wire'Range);
         D : Frm.Decoder_Type;
         S : Frm.Feed_Status;
      begin
         Net.On_Send_Frame (A, Enc);
         Dec := Enc;
         Net.On_Receive_Bytes (A, Dec);
         Check (Same_SEA (Dec, Wire), "leftover decrypt equals wire");
         Reset_Frames;
         Frm.Feed (D, Dec, On_Frame'Access, S);
         Check (S = Frm.Success and Frames_Seen = 1,
           "leftover decrypted frame decodes");
      end;
   end;

   --  4a. One-byte fragmentation after enable.
   declare
      A : Net.Connection_Context;
      Dummy : Boolean := Net.Try_Enable_Encryption (A, Secret);
      pragma Unreferenced (Dummy);
      Frag_Body : Ada.Streams.Stream_Element_Array (1 .. 5) := (1, 2, 3, 4, 5);
      Wire : constant Ada.Streams.Stream_Element_Array := Frame_Wire (Frag_Body);
      Enc : Ada.Streams.Stream_Element_Array (Wire'Range) := Wire;
      D : Frm.Decoder_Type;
      S : Frm.Feed_Status;
      One : Ada.Streams.Stream_Element_Array (1 .. 1);
   begin
      Net.On_Send_Frame (A, Enc);
      Reset_Frames;
      for I in Enc'Range loop
         --  Decrypt byte-by-byte as ingress would, then feed one byte.
         declare
            Single : Ada.Streams.Stream_Element_Array (1 .. 1) := (1 => Enc (I));
         begin
            Net.On_Receive_Bytes (A, Single);
            One := Single;
            Frm.Feed (D, One, On_Frame'Access, S);
            Check (S = Frm.Success, "frag feed ok");
         end;
      end loop;
      Check (Frames_Seen = 1 and Last_Len = 5, "1-byte fragmentation frame");
   end;

   --  4b. Coalesced frames in one chunk after enable.
   declare
      A : Net.Connection_Context;
      Dummy : Boolean := Net.Try_Enable_Encryption (A, Secret);
      pragma Unreferenced (Dummy);
      B1 : Ada.Streams.Stream_Element_Array (1 .. 2) := (7, 8);
      B2 : Ada.Streams.Stream_Element_Array (1 .. 2) := (9, 10);
      W1 : constant Ada.Streams.Stream_Element_Array := Frame_Wire (B1);
      W2 : constant Ada.Streams.Stream_Element_Array := Frame_Wire (B2);
      Both : Ada.Streams.Stream_Element_Array (1 .. W1'Length + W2'Length);
      D : Frm.Decoder_Type;
      S : Frm.Feed_Status;
   begin
      Both (1 .. W1'Length) := W1;
      Both (W1'Length + 1 .. Both'Last) := W2;
      Net.On_Send_Frame (A, Both);
      Net.On_Receive_Bytes (A, Both);
      Reset_Frames;
      Frm.Feed (D, Both, On_Frame'Access, S);
      Check (S = Frm.Success and Frames_Seen = 2, "coalesced two frames");
   end;

   --  5. Online Login Start -> Encryption Request, no Success yet.
   declare
      Sess : Log.Login_Session;
      R : constant Pkts.Start_Dispatch_Result :=
        Pkts.Handle_Login_Start (Sess, Build_Start_Payload,
          Online_Mode => True, Public_Key => Pub,
          Token => To_Octets (To_SEA (Token)));
   begin
      Check (R.Outcome = Pkts.Send_Encryption_Request, "online sends request");
      Check (R.Has_Request, "online has request");
      Check (R.Next_State = St.Login_Awaiting_Encryption_Response,
        "online awaiting state");
   end;

   --  6. Offline plaintext path unchanged.
   declare
      Sess : Log.Login_Session;
      Conn : Net.Connection_Context;
      R : constant Pkts.Start_Dispatch_Result :=
        Pkts.Handle_Login_Start (Sess, Build_Start_Payload,
          Online_Mode => False, Public_Key => Pub,
          Token => To_Octets (To_SEA (Token)));
   begin
      Net.Set_Online_Mode (Conn, False);
      Check (R.Outcome = Pkts.Send_Login_Success, "offline success");
      Check (not R.Has_Request, "offline no request");
      Check (not Net.Is_Encryption_Enabled (Conn), "offline stays plaintext");
   end;

   --  7. Bad-token disconnect with no cipher and no Success.
   declare
      Sess : Log.Login_Session;
      Key_Pay : constant Proto.Octets :=
        Build_Key_Payload (To_Octets (To_SEA (Secret)),
          To_Octets (To_SEA (Wrong_Token)));
      Tok_Oct : constant Proto.Octets := To_Octets (To_SEA (Token));
      R : constant Pkts.Key_Dispatch_Result :=
        Pkts.Handle_Encryption_Response (St.Login_Awaiting_Encryption_Response,
          Sess, Key_Pay, "Notch", Tok_Oct, False);
      Conn : Net.Connection_Context;
   begin
      Check (R.Outcome = Pkts.Need_Disconnect_Close, "bad token disconnect");
      Check (not R.Enable_Cipher, "bad token no cipher");
      Check (not Net.Is_Encryption_Enabled (Conn), "bad token conn plaintext");
   end;

   --  7b. Malformed secret (wrong length) disconnects.
   declare
      Sess : Log.Login_Session;
      Short : constant Proto.Octets (1 .. 3) := (1, 2, 3);
      Key_Pay : constant Proto.Octets :=
        Build_Key_Payload (Short, To_Octets (To_SEA (Token)));
      Tok_Oct : constant Proto.Octets := To_Octets (To_SEA (Token));
      R : constant Pkts.Key_Dispatch_Result :=
        Pkts.Handle_Encryption_Response (St.Login_Awaiting_Encryption_Response,
          Sess, Key_Pay, "Notch", Tok_Oct, False);
   begin
      Check (R.Outcome = Pkts.Need_Disconnect_Close, "malformed disconnect");
      Check (not R.Enable_Cipher, "malformed no cipher");
   end;

   --  8. Wrong-state and second-response rejection.
   declare
      Sess : Log.Login_Session;
      Key_Pay : constant Proto.Octets :=
        Build_Key_Payload (To_Octets (To_SEA (Secret)),
          To_Octets (To_SEA (Token)));
      Tok_Oct : constant Proto.Octets := To_Octets (To_SEA (Token));
      R1 : constant Pkts.Key_Dispatch_Result :=
        Pkts.Handle_Encryption_Response (St.Login, Sess,
          Key_Pay, "Notch", Tok_Oct, False);
      R2 : constant Pkts.Key_Dispatch_Result :=
        Pkts.Handle_Encryption_Response (St.Status, Sess,
          Key_Pay, "Notch", Tok_Oct, False);
      R3 : constant Pkts.Key_Dispatch_Result :=
        Pkts.Handle_Encryption_Response (St.Login_Awaiting_Encryption_Response,
          Sess, Key_Pay, "Notch", Tok_Oct, True);
   begin
      Check (R1.Outcome = Pkts.Protocol_Error_Close, "wrong state login");
      Check (R2.Outcome = Pkts.Protocol_Error_Close, "status never enables");
      Check (not R1.Enable_Cipher and not R2.Enable_Cipher,
        "wrong state no cipher");
      Check (R3.Outcome = Pkts.Protocol_Error_Close
        and not R3.Enable_Cipher, "second response rejected");
   end;

   --  9. Success enables exactly once; enable latch never disables.
   declare
      Sess : Log.Login_Session;
      Key_Pay : constant Proto.Octets :=
        Build_Key_Payload (To_Octets (To_SEA (Secret)),
          To_Octets (To_SEA (Token)));
      Tok_Oct : constant Proto.Octets := To_Octets (To_SEA (Token));
      R : constant Pkts.Key_Dispatch_Result :=
        Pkts.Handle_Encryption_Response (St.Login_Awaiting_Encryption_Response,
          Sess, Key_Pay, "Notch", Tok_Oct, False);
      Conn : Net.Connection_Context;
      First, Second : Boolean;
   begin
      Check (R.Outcome = Pkts.Enable_Then_Success, "success enables");
      Check (R.Enable_Cipher, "success enable flag");
      First := Net.Try_Enable_Encryption (Conn, Secret);
      Second := Net.Try_Enable_Encryption (Conn, Secret);
      Check (First and not Second, "enable-at-most-once latch");
      Check (Net.Is_Encryption_Enabled (Conn), "enabled never disabled");
   end;

   --  10. Malformed post-decrypt framing-error disconnect, no crash.
   declare
      D : Frm.Decoder_Type;
      S : Frm.Feed_Status;
      Bad : Frm.Byte_Array (1 .. 4) := (16#80#, 16#80#, 16#80#, 16#80#);
      A : Net.Connection_Context;
      Dummy : Boolean := Net.Try_Enable_Encryption (A, Secret);
      pragma Unreferenced (Dummy);
   begin
      Net.On_Receive_Bytes (A, Bad);
      Reset_Frames;
      Frm.Feed (D, Bad, On_Frame'Access, S);
      Check (S = Frm.Framing_Error, "post-decrypt framing error");
      Check (Frames_Seen = 0, "no frame on error");
   end;

   if Failures = 0 then
      Ada.Text_IO.Put_Line ("login encryption tests passed");
   else
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
   end if;
end Test_Login_Encryption;
