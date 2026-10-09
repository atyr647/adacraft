with Ada.Command_Line;
with Ada.Text_IO;
with GNAT.Sockets;
with Interfaces;
with Adacraft.Network;
with Adacraft.Protocol;
with Adacraft.Protocol.Buffer;
with Adacraft.Protocol.Frame;
with Adacraft.Protocol.Handshake_Exchange;
with Adacraft.Protocol.State;
with Adacraft.Protocol.Varnum;

procedure Test_Bad_Clients is
   use Adacraft.Protocol;
   package HE renames Adacraft.Protocol.Handshake_Exchange;
   package FR renames Adacraft.Protocol.Frame;
   package S renames Adacraft.Protocol.State;
   package V renames Adacraft.Protocol.Varnum;
   use type S.Connection_State;
   use type HE.Handle_Result;
   use type V.Status_Type;

   Failures : Natural := 0;

   procedure Check (Cond : Boolean; Name : String) is
   begin
      if not Cond then
         Failures := Failures + 1;
         Ada.Text_IO.Put_Line ("FAIL: " & Name);
      end if;
   end Check;

   --  Port contract is tested through Adacraft.Network.Parse_Port, the
   --  same implementation the server calls: empty, non-digit
   --  (incl. "-N"), 0 and > 65535 raise Constraint_Error, valid
   --  ports 1 .. 65535 are accepted unchanged.
   procedure Expect_Bad_Port (Image : String; Name : String) is
      P     : GNAT.Sockets.Port_Type := 1;
      Raised : Boolean := False;
   begin
      begin
         Adacraft.Network.Parse_Port (Image, P);
      exception
         when Constraint_Error =>
            Raised := True;
         when others =>
            Raised := False;
      end;
      Check (Raised, Name & " raises Constraint_Error, no exit");
   end Expect_Bad_Port;

   procedure Expect_Good_Port (Image : String; Want : Integer; Name : String) is
      use GNAT.Sockets;
      P : Port_Type := 1;
      Ok : Boolean := True;
   begin
      begin
         Adacraft.Network.Parse_Port (Image, P);
      exception
         when others =>
            Ok := False;
      end;
      Check (Ok and then Integer (P) = Want, Name);
   end Expect_Good_Port;

   function Build (Version : Interfaces.Unsigned_32; Addr : String;
                   Port : Interfaces.Unsigned_16;
                   Intent : Interfaces.Unsigned_32) return Octets
   is
      W : Buffer.Writer (1024);
   begin
      Buffer.Put_Varint (W, Version);
      Buffer.Put_String (W, Addr);
      Buffer.Put_U16 (W, Port);
      Buffer.Put_Varint (W, Intent);
      declare
         R : Octets (1 .. W.Len);
      begin
         for I in 1 .. W.Len loop
            R (I) := W.Data (I);
         end loop;
         return R;
      end;
   end Build;

   --  Run one handshake payload through Handle with all exceptions
   --  contained; models per-connection close-only, no raise, no exit.
   procedure Expect_Rejected_No_Raise
     (Packet_Id : Natural; Payload : Octets; Name : String)
   is
      Cur    : S.Connection_State := S.Handshake;
      Stored : HE.Connection_Data;
      Res    : HE.Handle_Result := HE.Accepted_Status;
      Raised : Boolean := False;
   begin
      begin
         HE.Handle (Packet_Id, Payload, Cur, Stored, Res);
      exception
         when others =>
            Raised := True;
      end;
      Check (not Raised, Name & " no raise");
      Check (Res = HE.Rejected_No_Change, Name & " rejected");
      Check (Cur = S.Handshake, Name & " state unchanged (close only)");
   end Expect_Rejected_No_Raise;

begin
   --  Parse_Port: bad values.
   Expect_Bad_Port ("", "port empty");
   Expect_Bad_Port ("abc", "port not-a-number");
   Expect_Bad_Port ("12x34", "port mixed digits");
   Expect_Bad_Port (" 25565", "port leading space");
   Expect_Bad_Port ("25565 ", "port trailing space");
   Expect_Bad_Port ("-1", "port negative");
   Expect_Bad_Port ("-25565", "port negative full");
   Expect_Bad_Port ("0", "port zero");
   Expect_Bad_Port ("00", "port double zero");
   Expect_Bad_Port ("65536", "port above max");
   Expect_Bad_Port ("99999", "port far above max");
   Expect_Bad_Port ("123456789", "port huge");
   --  Parse_Port: valid values behave as before.
   Expect_Good_Port ("1", 1, "port min valid");
   Expect_Good_Port ("80", 80, "port 80");
   Expect_Good_Port ("25565", 25565, "port default");
   Expect_Good_Port ("65535", 65535, "port max valid");
   Expect_Good_Port ("00080", 80, "port leading zeros");

   --  Handshake garbage: overlong VarInt (6 continuation bytes).
   declare
      P : constant Octets (1 .. 8) :=
        (16#80#, 16#80#, 16#80#, 16#80#, 16#80#, 16#01#,
         16#00#, 16#00#);
   begin
      Expect_Rejected_No_Raise (0, P, "overlong varint");
   end;

   --  Varnum decoder itself reports Overlong for 5+ continuation bytes.
   declare
      Buf : constant Octets (1 .. 6) :=
        (16#80#, 16#80#, 16#80#, 16#80#, 16#80#, 16#01#);
      Val : Interfaces.Integer_32 := 0;
      Got : Natural := 0;
      St  : V.Status_Type;
      Raised : Boolean := False;
   begin
      begin
         V.Decode (Buf, 1, Val, Got, St);
      exception
         when others =>
            Raised := True;
      end;
      Check (not Raised, "varnum overlong no raise");
      Check (St = V.Overlong, "varnum overlong status");
   end;

   --  Frame decoder: overlong VarInt length prefix (6 bytes) rejected.
   declare
      Buf : constant Octets (1 .. 7) :=
        (16#80#, 16#80#, 16#80#, 16#80#, 16#80#, 16#01#, 16#00#);
      D : FR.Frame_Decode;
      Raised : Boolean := False;
   begin
      begin
         D := FR.Decode_Frame (Buf, 1);
      exception
         when others =>
            Raised := True;
      end;
      Check (not Raised, "frame overlong prefix no raise");
      if not Raised then
         Check (D.Status /= Ok, "frame overlong prefix rejected");
      end if;
   end;

   --  Frame decoder: over-maximum declared length.
   --  0x80 0x80 0x80 0x01 is a 4-byte prefix (prefix > 3 bytes) -> reject.
   declare
      Buf : constant Octets (1 .. 5) :=
        (16#80#, 16#80#, 16#80#, 16#01#, 16#00#);
      D : FR.Frame_Decode;
      Raised : Boolean := False;
   begin
      begin
         D := FR.Decode_Frame (Buf, 1);
      exception
         when others =>
            Raised := True;
      end;
      Check (not Raised, "frame over-max length no raise");
      if not Raised then
         Check (D.Status = Rejected, "frame over-max length rejected");
      end if;
   end;

   --  Frame decoder: zero-length frame rejected (server needs packet id).
   declare
      Buf : constant Octets (1 .. 1) := (1 => 16#00#);
      D : FR.Frame_Decode;
      Raised : Boolean := False;
   begin
      begin
         D := FR.Decode_Frame (Buf, 1);
      exception
         when others =>
            Raised := True;
      end;
      Check (not Raised, "frame zero length no raise");
      if not Raised then
         Check (D.Status = Rejected, "frame zero length rejected");
      end if;
   end;

   --  Unknown handshake packet id closes only that conn.
   declare
      P : constant Octets := Build (777, "localhost", 25565, 1);
   begin
      Expect_Rejected_No_Raise (1, P, "unknown handshake id 1");
      Expect_Rejected_No_Raise (2, P, "unknown handshake id 2");
      Expect_Rejected_No_Raise (16#7F#, P, "unknown handshake id 7F");
   end;

   --  Invalid next-state (intent) values.
   declare
      procedure Case_Intent (Intent : Interfaces.Unsigned_32; Name : String) is
         P : constant Octets := Build (777, "localhost", 25565, Intent);
      begin
         Expect_Rejected_No_Raise (0, P, Name);
      end;
   begin
      Case_Intent (0, "intent 0 invalid");
      Case_Intent (4, "intent 4 invalid");
      Case_Intent (255, "intent 255 invalid");
      Case_Intent (16#FFFF_FFFF#, "intent max invalid");
   end;

   --  Truncated / malformed fields.
   declare
      Full : constant Octets := Build (777, "localhost", 25565, 1);
   begin
      Expect_Rejected_No_Raise
        (0, Full (Full'First .. Full'Last - 1), "truncated last byte");
      Expect_Rejected_No_Raise
        (0, Full (Full'First .. Full'First + 1), "truncated to 2 bytes");
      declare
         Empty : constant Octets (1 .. 0) := (others => 0);
      begin
         Expect_Rejected_No_Raise (0, Empty, "empty payload");
      end;
      declare
         P : Octets (1 .. Full'Length + 1);
      begin
         for I in Full'Range loop
            P (I - Full'First + 1) := Full (I);
         end loop;
         P (P'Last) := 16#00#;
         Expect_Rejected_No_Raise (0, P, "trailing byte malformed");
      end;
      declare
         Long_Addr : String (1 .. 256) := (others => 'a');
         P : constant Octets := Build (777, Long_Addr, 25565, 1);
      begin
         Expect_Rejected_No_Raise (0, P, "256-char address malformed");
      end;
   end;

   --  Close-only-that-conn: bad conn stays/rejected while a sibling
   --  good handshake on a separate state still transitions; nothing raises.
   declare
      Good_P : constant Octets := Build (777, "localhost", 25565, 1);
      Bad_P  : constant Octets (1 .. 8) :=
        (16#80#, 16#80#, 16#80#, 16#80#, 16#80#, 16#01#,
         16#00#, 16#00#);
      Cur_A : S.Connection_State := S.Handshake;
      Cur_B : S.Connection_State := S.Handshake;
      Sto_A : HE.Connection_Data;
      Sto_B : HE.Connection_Data;
      Res_A : HE.Handle_Result;
      Res_B : HE.Handle_Result;
      Raised : Boolean := False;
   begin
      begin
         HE.Handle (0, Bad_P, Cur_A, Sto_A, Res_A);
         HE.Handle (0, Good_P, Cur_B, Sto_B, Res_B);
      exception
         when others =>
            Raised := True;
      end;
      Check (not Raised, "sibling pair no raise, no exit");
      Check (Res_A = HE.Rejected_No_Change and then Cur_A = S.Handshake,
             "bad sibling closed only");
      Check (Res_B = HE.Accepted_Status and then Cur_B = S.Status,
             "good sibling unaffected");
   end;

   --  Unknown-id on one conn does not affect a sibling good conn.
   declare
      Good_P : constant Octets := Build (760, "other.example", 25566, 2);
      Cur_A : S.Connection_State := S.Handshake;
      Cur_B : S.Connection_State := S.Handshake;
      Sto_A : HE.Connection_Data;
      Sto_B : HE.Connection_Data;
      Res_A : HE.Handle_Result;
      Res_B : HE.Handle_Result;
      Raised : Boolean := False;
   begin
      begin
         HE.Handle (5, Good_P, Cur_A, Sto_A, Res_A);
         HE.Handle (0, Good_P, Cur_B, Sto_B, Res_B);
      exception
         when others =>
            Raised := True;
      end;
      Check (not Raised, "unknown-id pair no raise");
      Check (Res_A = HE.Rejected_No_Change and then Cur_A = S.Handshake,
             "unknown-id conn closed only");
      Check (Res_B = HE.Accepted_Login and then Cur_B = S.Login,
             "good conn still logs in");
   end;

   if Failures = 0 then
      Ada.Text_IO.Put_Line ("PASS test_bad_clients");
   else
      Ada.Text_IO.Put_Line ("FAILURES:" & Failures'Image);
   end if;
   Ada.Command_Line.Set_Exit_Status
     (if Failures = 0 then Ada.Command_Line.Success else Ada.Command_Line.Failure);
end Test_Bad_Clients;
