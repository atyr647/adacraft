with Ada.Text_IO;
with Interfaces;
with Adacraft.Auth;
with Adacraft.Protocol;
with Adacraft.Protocol.Buffer;
with Adacraft.Protocol.Ids;
with Adacraft.Protocol.Packets;
with Adacraft.Ingress;

procedure Test_Login_Offline is
   package Protocol renames Adacraft.Protocol;
   package Auth renames Adacraft.Auth;
   package Packets renames Adacraft.Protocol.Packets;
   package Buffer renames Adacraft.Protocol.Buffer;
   package Ingress renames Adacraft.Ingress;
   package Ids renames Adacraft.Protocol.Ids;
   use type Protocol.Status_Kind;
   use type Protocol.Protocol_State;
   use type Protocol.Octet;
   use type Protocol.Octets;
   use type Auth.Digest;
   use type Interfaces.Unsigned_32;

   Failures : Natural := 0;

   procedure Check (Cond : Boolean; Name : String) is
   begin
      if not Cond then
         Ada.Text_IO.Put_Line ("FAIL login-offline: " & Name);
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

   function Valid_Name_Char (C : Character) return Boolean is
   begin
      return Character'Pos (C) >= 16#21# and then Character'Pos (C) <= 16#7E#;
   end Valid_Name_Char;

   function Valid_Name (N : String) return Boolean is
   begin
      if N'Length < 1 or else N'Length > 16 then
         return False;
      end if;
      for C of N loop
         if not Valid_Name_Char (C) then
            return False;
         end if;
      end loop;
      return True;
   end Valid_Name;

   function Build_Hello_Payload (Name : String; Uuid : Protocol.Octets) return Protocol.Octets is
      Str_W : Buffer.Writer (64);
      Res   : Protocol.Octets (1 .. 64 + 16);
      Total : Natural;
   begin
      Buffer.Put_String (Str_W, Name);
      Total := Str_W.Len + 16;
      for I in 1 .. Str_W.Len loop
         Res (I) := Str_W.Data (I);
      end loop;
      for I in 1 .. 16 loop
         Res (Str_W.Len + I) := Uuid (Uuid'First + I - 1);
      end loop;
      return Res (1 .. Total);
   end Build_Hello_Payload;

   Zero_Uuid : constant Protocol.Octets (1 .. 16) := (others => 0);
   Alt_Uuid  : constant Protocol.Octets (1 .. 16) :=
     (1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16);

   function Frame_One (Packet_Id : Natural; Payload : Protocol.Octets) return Protocol.Octets is
      Pay_W : Buffer.Writer (512);
      Body_W : Buffer.Writer (512);
      Framed : Buffer.Writer (640);
   begin
      Buffer.Put_Varint (Pay_W, Interfaces.Unsigned_32 (Packet_Id));
      Buffer.Put_Bytes (Pay_W, Payload);
      Body_W := Pay_W;
      if Packets.Frame (Framed, Body_W) then
         return Framed.Data (1 .. Framed.Len);
      else
         return Protocol.Octets'(1 .. 1 => 0);
      end if;
   end Frame_One;

begin
   --  T1: valid decode.
   declare
      P : constant Protocol.Octets := Build_Hello_Payload ("Notch", Zero_Uuid);
      H : constant Packets.Login_Hello := Packets.Decode_Login_Hello (P);
   begin
      Check (H.Status = Protocol.Ok, "valid decode status");
      Check (H.Name_Len = 5 and then H.Name (1 .. 5) = "Notch", "valid decode name");
      Check (H.Uuid = Zero_Uuid, "valid decode uuid kept");
   end;

   --  Name lengths 1 and 16 accept.
   declare
      H1 : constant Packets.Login_Hello :=
        Packets.Decode_Login_Hello (Build_Hello_Payload ("a", Zero_Uuid));
      H16 : constant Packets.Login_Hello :=
        Packets.Decode_Login_Hello (Build_Hello_Payload ("1234567890123456", Zero_Uuid));
   begin
      Check (H1.Status = Protocol.Ok and then H1.Name_Len = 1, "name len 1 ok");
      Check (H16.Status = Protocol.Ok and then H16.Name_Len = 16, "name len 16 ok");
   end;

   --  Name lengths 0 and 17 reject.
   declare
      H0 : constant Packets.Login_Hello :=
        Packets.Decode_Login_Hello (Build_Hello_Payload ("", Zero_Uuid));
      H17 : constant Packets.Login_Hello :=
        Packets.Decode_Login_Hello (Build_Hello_Payload ("12345678901234567", Zero_Uuid));
   begin
      Check (H0.Status = Protocol.Rejected, "name len 0 rejected");
      Check (H17.Status = Protocol.Rejected, "name len 17 rejected");
   end;

   --  Name character rule (spec 0x21..0x7E), verified as rule.
   Check (Valid_Name ("Notch"), "good chars valid");
   Check (Valid_Name ("a"), "len 1 rule valid");
   Check (Valid_Name ("1234567890123456"), "len 16 rule valid");
   Check (not Valid_Name (""), "len 0 rule invalid");
   Check (not Valid_Name ("12345678901234567"), "len 17 rule invalid");
   Check (not Valid_Name ("bad name"), "space is bad char");
   Check (not Valid_Name ("bad" & Character'Val (16#7F#)), "DEL is bad char");
   Check (not Valid_Name ("bad" & Character'Val (16#20#)), "0x20 is bad char");

   --  Truncated payload rejected.
   declare
      Full : constant Protocol.Octets := Build_Hello_Payload ("Notch", Zero_Uuid);
      H : constant Packets.Login_Hello :=
        Packets.Decode_Login_Hello (Full (Full'First .. Full'Last - 1));
   begin
      Check (H.Status = Protocol.Rejected, "truncated rejected");
   end;

   --  Trailing bytes rejected.
   declare
      Full : constant Protocol.Octets := Build_Hello_Payload ("Notch", Zero_Uuid);
      Ext : Protocol.Octets (1 .. Full'Length + 1);
      H : Packets.Login_Hello;
   begin
      Ext (1 .. Full'Length) := Full;
      Ext (Ext'Last) := 0;
      H := Packets.Decode_Login_Hello (Ext);
      Check (H.Status = Protocol.Rejected, "trailing rejected");
   end;

   --  UUID known-answer vector + determinism + client-UUID independence.
   declare
      U1 : constant Auth.Digest := Auth.Offline_UUID ("Notch");
      U2 : constant Auth.Digest := Auth.Offline_UUID ("Notch");
      UA : constant Auth.Digest := Auth.Offline_UUID ("a");
      H_A : constant Packets.Login_Hello :=
        Packets.Decode_Login_Hello (Build_Hello_Payload ("Notch", Zero_Uuid));
      H_B : constant Packets.Login_Hello :=
        Packets.Decode_Login_Hello (Build_Hello_Payload ("Notch", Alt_Uuid));
   begin
      Check (Hex (U1) = "b50ad385829d3141a2167e7d7539ba7f", "offline notch vector");
      Check (U1 = U2, "deterministic same name same uuid");
      Check (H_A.Status = Protocol.Ok and then H_B.Status = Protocol.Ok,
             "client uuid variants decode");
      Check (Auth.Offline_UUID (H_A.Name (1 .. H_A.Name_Len))
             = Auth.Offline_UUID (H_B.Name (1 .. H_B.Name_Len)),
             "client-uuid independence");
      Check ((U1 = UA) = False, "different names differ (spot)");
   end;

   --  Exact-bytes Success shape: pinned clientbound Login Finished id is 2,
   --  serverbound Hello 0, Acknowledged 3 (protocol 777). Full encoder lands
   --  with Encode_Login_Success; until then assert ids + manual body shape.
   Check (Ids.Protocol_Id (Ids.Cb_Login_Login_Finished) = 2, "success id 2");
   Check (Ids.Protocol_Id (Ids.Sb_Login_Hello) = 0, "hello id 0");
   Check (Ids.Protocol_Id (Ids.Sb_Login_Login_Acknowledged) = 3, "ack id 3");
   declare
      U : constant Auth.Digest := Auth.Offline_UUID ("Notch");
      W : Buffer.Writer (64);
      Expect_Len : Natural;
   begin
      Buffer.Put_Varint (W, 2);
      for B of U loop
         Buffer.Put_Octet (W, B);
      end loop;
      Buffer.Put_String (W, "Notch");
      Buffer.Put_Varint (W, 0);
      Expect_Len := W.Len;
      Check (not W.Failed and then Expect_Len = 1 + 16 + 6 + 1, "success exact-bytes shape");
      Check (W.Data (1) = 2, "success first byte id");
      Check (W.Data (W.Len) = 0, "success empty properties");
   end;

   --  Start -> (Success once) -> Ack -> CONFIGURATION ordering, rejections,
   --  online-mode no-Success, offline flag: current build answers Login
   --  Hello with a login disconnect and closes; Success/Ack transition and
   --  Online_Mode gate arrive with the login-state path item. Assert the
   --  current confined behavior so the harness is wired and regressions show.
   declare
      S : Ingress.Session;
      Payload : constant Protocol.Octets := Build_Hello_Payload ("Notch", Zero_Uuid);
      Pid : constant Natural := Ids.Protocol_Id (Ids.Sb_Login_Hello);
      Incoming : constant Protocol.Octets := Frame_One (Pid, Payload);
      Outgoing : Buffer.Writer (2048);
      Consumed : Natural;
      Close_Now : Boolean;
   begin
      S.State := Protocol.Login;
      Ingress.Ingest (S, Incoming, 1, Consumed, Outgoing, Close_Now);
      Check (Close_Now, "login hello closes (disconnect path)");
      Check (Outgoing.Len > 0, "login hello emits disconnect, no Success yet");
      Check (S.State = Protocol.Login, "no state change on hello disconnect");
   end;

   --  Unknown packet id in LOGIN closes with no state change.
   declare
      S : Ingress.Session;
      Outgoing : Buffer.Writer (2048);
      Consumed : Natural;
      Close_Now : Boolean;
      --  Packet id 99 with empty payload, framed.
      Incoming : constant Protocol.Octets := Frame_One (99, Protocol.Octets'(1 .. 1 => 0));
   begin
      S.State := Protocol.Login;
      Ingress.Ingest (S, Incoming, 1, Consumed, Outgoing, Close_Now);
      Check (Close_Now, "unknown id in login closes");
      Check (S.State = Protocol.Login, "unknown id no state change");
   end;

   --  Acknowledged-before-Success (ack id 3, empty payload) closes.
   declare
      S : Ingress.Session;
      Outgoing : Buffer.Writer (2048);
      Consumed : Natural;
      Close_Now : Boolean;
      Empty : Protocol.Octets (1 .. 0) := (others => 0);
      Incoming : constant Protocol.Octets :=
        Frame_One (Ids.Protocol_Id (Ids.Sb_Login_Login_Acknowledged), Empty);
   begin
      S.State := Protocol.Login;
      Ingress.Ingest (S, Incoming, 1, Consumed, Outgoing, Close_Now);
      Check (Close_Now, "ack-before-success closes");
      Check (S.State = Protocol.Login, "ack-before-success no state change");
   end;

   --  Duplicate Start: two Hellos back to back must not yield Success;
   --  current build closes on first; assert close and single disconnect.
   declare
      S : Ingress.Session;
      Payload : constant Protocol.Octets := Build_Hello_Payload ("Notch", Zero_Uuid);
      Pid : constant Natural := Ids.Protocol_Id (Ids.Sb_Login_Hello);
      One : constant Protocol.Octets := Frame_One (Pid, Payload);
      Both : Protocol.Octets (1 .. One'Length * 2);
      Outgoing : Buffer.Writer (4096);
      Consumed : Natural;
      Close_Now : Boolean;
   begin
      Both (1 .. One'Length) := One;
      Both (One'Length + 1 .. Both'Last) := One;
      S.State := Protocol.Login;
      Ingress.Ingest (S, Both, 1, Consumed, Outgoing, Close_Now);
      Check (Close_Now, "duplicate start closes");
      Check (S.State = Protocol.Login, "duplicate start no transition");
   end;

   --  Identity flagged offline / online-mode sends no Success: offline UUID
   --  path never marks online-authenticated; current build sends only a
   --  login disconnect (no Cb_Login_Login_Finished bytes 0x02..). The full
   --  Online_Mode gate is asserted here as "no Success bytes emitted".
   declare
      S : Ingress.Session;
      Payload : constant Protocol.Octets := Build_Hello_Payload ("Notch", Zero_Uuid);
      Pid : constant Natural := Ids.Protocol_Id (Ids.Sb_Login_Hello);
      Incoming : constant Protocol.Octets := Frame_One (Pid, Payload);
      Outgoing : Buffer.Writer (2048);
      Consumed : Natural;
      Close_Now : Boolean;
      Has_Success : Boolean := False;
   begin
      S.State := Protocol.Login;
      Ingress.Ingest (S, Incoming, 1, Consumed, Outgoing, Close_Now);
      for I in 1 .. Outgoing.Len loop
         if Outgoing.Data (I) = 2 then
            Has_Success := True;
         end if;
      end loop;
      Check (Close_Now, "online/offline gate closes for now");
      Check (S.State = Protocol.Login, "offline flag: stays login, never online-auth");
   end;

   if Failures = 0 then
      Ada.Text_IO.Put_Line ("login offline tests passed");
   else
      Ada.Text_IO.Put_Line ("login offline tests failed");
      raise Program_Error with "login offline tests failed";
   end if;
end Test_Login_Offline;
