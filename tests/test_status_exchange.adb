with Ada.Text_IO;
with Interfaces;
with Adacraft.Protocol;
with Adacraft.Protocol.State;
with Adacraft.Protocol.Status_Exchange;

procedure Test_Status_Exchange is
   use Adacraft.Protocol;
   use type State.Connection_State;
   use type Interfaces.Unsigned_8;

   Failures : Natural := 0;

   procedure Check (Condition : Boolean; Name : String) is
   begin
      if Condition then
         Ada.Text_IO.Put_Line ("PASS: " & Name);
      else
         Failures := Failures + 1;
         Ada.Text_IO.Put_Line ("FAIL: " & Name);
      end if;
   end Check;

   function Reply_String (R : Status_Exchange.Outcome) return String is
   begin
      if not R.Has_Reply or else R.Reply_Length = 0 then
         return "";
      end if;
      declare
         S : String (1 .. R.Reply_Length);
      begin
         for I in 1 .. R.Reply_Length loop
            S (I) := Character'Val (Natural (R.Reply_Data (I)));
         end loop;
         return S;
      end;
   end Reply_String;

   function Contains (Haystack : String; Needle : String) return Boolean is
   begin
      if Needle'Length = 0 then
         return True;
      end if;
      if Haystack'Length < Needle'Length then
         return False;
      end if;
      for I in Haystack'First .. Haystack'Last - Needle'Length + 1 loop
         if Haystack (I .. I + Needle'Length - 1) = Needle then
            return True;
         end if;
      end loop;
      return False;
   end Contains;

   function To_Payload (V : Interfaces.Unsigned_64) return Octets is
      P : Octets (1 .. 8);
      Tmp : Interfaces.Unsigned_64 := V;
      use type Interfaces.Unsigned_64;
   begin
      for I in reverse 1 .. 8 loop
         P (I) := Octet (Tmp and 16#FF#);
         Tmp := Interfaces.Shift_Right (Tmp, 8);
      end loop;
      return P;
   end To_Payload;

   Empty : constant Octets (1 .. 0) := [];
   Cfg : constant Status_Exchange.Status_Config :=
     Status_Exchange.Default_Config;
   R : Status_Exchange.Outcome;
   Sent : Boolean;
begin
   --  Request -> Response JSON contents
   Sent := False;
   Status_Exchange.Handle (State.Status, 0, Empty, Cfg, Sent, R);
   Check (R.Accepted and then R.Has_Reply and then not R.Close_Requested
          and then Sent,
          "request accepted sets sent");
   declare
      S : constant String := Reply_String (R);
   begin
      Check (Contains (S, """name"":""26.3"""), "json name 26.3");
      Check (Contains (S, """protocol"":777"), "json protocol 777");
      Check (Contains (S, """max"":20"), "json max 20");
      Check (Contains (S, """online"":0"), "json online 0");
      Check (Contains (S, """description"""), "json description present");
      Check (Contains (S, "A Minecraft Server"), "json default motd");
      Check (R.Reply_Data (1) = 0, "response id 0x00");
   end;

   --  Custom max/online
   declare
      B : constant Status_Exchange.Config_Build_Result :=
        Status_Exchange.Build_Config ("26.3", 777, 42, 7, "Hi");
      S2 : Boolean := False;
      R2 : Status_Exchange.Outcome;
   begin
      Check (B.Valid, "custom config valid");
      Status_Exchange.Handle (State.Status, 0, Empty, B.Config, S2, R2);
      declare
         S : constant String := Reply_String (R2);
      begin
         Check (Contains (S, """max"":42"), "json custom max");
         Check (Contains (S, """online"":7"), "json custom online");
      end;
   end;

   --  MOTD escaping quote + backslash
   declare
      B : constant Status_Exchange.Config_Build_Result :=
        Status_Exchange.Build_Config ("26.3", 777, 20, 0, "a""b\c");
      S2 : Boolean := False;
      R2 : Status_Exchange.Outcome;
   begin
      Check (B.Valid, "escape config valid");
      Status_Exchange.Handle (State.Status, 0, Empty, B.Config, S2, R2);
      declare
         S : constant String := Reply_String (R2);
      begin
         Check (Contains (S, "a\""b\\c"), "motd quote+backslash escaped");
      end;
   end;

   --  Oversize config rejected at build
   declare
      Big : String (1 .. 40_000) := [others => 'x'];
      B : constant Status_Exchange.Config_Build_Result :=
        Status_Exchange.Build_Config ("26.3", 777, 20, 0, Big);
   begin
      Check (not B.Valid, "oversize config rejected");
   end;

   --  Second request rejected
   declare
      S2 : Boolean := True;
      R2 : Status_Exchange.Outcome;
   begin
      Status_Exchange.Handle (State.Status, 0, Empty, Cfg, S2, R2);
      Check (not R2.Accepted and then R2.Close_Requested
             and then not R2.Has_Reply,
             "second request rejected");
   end;

   --  Sequential second request via flag
   declare
      S2 : Boolean := False;
      R2 : Status_Exchange.Outcome;
   begin
      Status_Exchange.Handle (State.Status, 0, Empty, Cfg, S2, R2);
      Check (R2.Accepted, "first request ok");
      Status_Exchange.Handle (State.Status, 0, Empty, Cfg, S2, R2);
      Check (not R2.Accepted and then R2.Close_Requested,
             "sequential second request rejected");
   end;

   --  Ping -> identical Pong + close
   declare
      P : constant Octets := To_Payload (16#0102030405060708#);
      S2 : Boolean := False;
      R2 : Status_Exchange.Outcome;
   begin
      Status_Exchange.Handle (State.Status, 1, P, Cfg, S2, R2);
      Check (R2.Accepted and then R2.Has_Reply and then R2.Close_Requested,
             "ping pong close");
      Check (R2.Reply_Length = 9 and then R2.Reply_Data (1) = 1,
             "pong id 0x01 len 9");
      declare
         Match : Boolean := True;
      begin
         for I in 1 .. 8 loop
            if R2.Reply_Data (I + 1) /= P (I) then
               Match := False;
            end if;
         end loop;
         Check (Match, "pong echoes payload");
      end;
   end;

   --  Ping before Request accepted
   declare
      P : constant Octets := To_Payload (12345);
      S2 : Boolean := False;
      R2 : Status_Exchange.Outcome;
   begin
      Status_Exchange.Handle (State.Status, 1, P, Cfg, S2, R2);
      Check (R2.Accepted and then R2.Close_Requested and then not S2,
             "ping before request accepted");
   end;

   --  Non-empty Request rejected
   declare
      P : Octets (1 .. 1) := [others => 0];
      S2 : Boolean := False;
      R2 : Status_Exchange.Outcome;
   begin
      Status_Exchange.Handle (State.Status, 0, P, Cfg, S2, R2);
      Check (not R2.Accepted and then R2.Close_Requested,
             "non-empty request rejected");
   end;

   --  7-byte ping rejected
   declare
      P : Octets (1 .. 7) := [others => 1];
      S2 : Boolean := False;
      R2 : Status_Exchange.Outcome;
   begin
      Status_Exchange.Handle (State.Status, 1, P, Cfg, S2, R2);
      Check (not R2.Accepted and then R2.Close_Requested,
             "7-byte ping rejected");
   end;

   --  9-byte ping rejected
   declare
      P : Octets (1 .. 9) := [others => 2];
      S2 : Boolean := False;
      R2 : Status_Exchange.Outcome;
   begin
      Status_Exchange.Handle (State.Status, 1, P, Cfg, S2, R2);
      Check (not R2.Accepted and then R2.Close_Requested,
             "9-byte ping rejected");
   end;

   --  Unknown ID rejected
   declare
      S2 : Boolean := False;
      R2 : Status_Exchange.Outcome;
   begin
      Status_Exchange.Handle (State.Status, 2, Empty, Cfg, S2, R2);
      Check (not R2.Accepted and then R2.Close_Requested,
             "unknown id rejected");
   end;

   --  Non-Status state rejected
   declare
      S2 : Boolean := False;
      R2 : Status_Exchange.Outcome;
   begin
      Status_Exchange.Handle (State.Handshake, 0, Empty, Cfg, S2, R2);
      Check (not R2.Accepted and then R2.Close_Requested,
             "handshake state rejected");
      Status_Exchange.Handle (State.Login, 1, To_Payload (1), Cfg, S2, R2);
      Check (not R2.Accepted and then R2.Close_Requested,
             "login state rejected");
   end;

   if Failures > 0 then
      raise Program_Error with "test failures";
   end if;
   Ada.Text_IO.Put_Line ("ALL PASS");
end Test_Status_Exchange;
