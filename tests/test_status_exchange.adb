with Ada.Command_Line;
with Ada.Text_IO;
with Interfaces;
with Adacraft.Protocol;
with Adacraft.Protocol.Buffer;
with Adacraft.Protocol.Status_Exchange;
with Adacraft.Protocol.State;

procedure Test_Status_Exchange is
   package P renames Adacraft.Protocol;
   package B renames Adacraft.Protocol.Buffer;
   package X renames Adacraft.Protocol.Status_Exchange;
   package S renames Adacraft.Protocol.State;
   use type Interfaces.Unsigned_8;
   use type X.Disposition_Kind;

   Failures : Natural := 0;

   procedure Check (Condition : Boolean; Name : String) is
   begin
      if not Condition then
         Failures := Failures + 1;
         Ada.Text_IO.Put_Line ("FAIL: " & Name);
      end if;
   end Check;

   procedure Call
     (Input       : P.Octets;
      Sent        : in out Boolean;
      Result      : out X.Disposition_Kind;
      Output      : out B.Writer)
   is
   begin
      X.Handle (Input, S.Status, Sent, Result, Output);
   end Call;

   Empty_Request : constant P.Octets := [1 => 0];
   Ping_Request : constant P.Octets :=
     [1 => 1, 2 => 16#80#, 3 => 16#01#, 4 => 16#02#, 5 => 16#03#,
      6 => 16#04#, 7 => 16#05#, 8 => 16#06#, 9 => 16#07#];
begin
   declare
      Sent : Boolean := False;
      Result : X.Disposition_Kind;
      Output : B.Writer (256);
   begin
      Call (Empty_Request, Sent, Result, Output);
      Check
        ((Result = X.Progress) and then Sent and then (not Output.Failed),
         "status response sent once");
      Check
        (Output.Len > 2
         and then Output.Data (Output.Len - 1) = Character'Pos ('}')
         and then Output.Data (Output.Len) = Character'Pos ('}'),
         "status response contains the expected JSON tail");

      Call (Empty_Request, Sent, Result, Output);
      Check
        ((Result = X.Silent_Close) and then Sent and then Output.Len = 0,
         "second status request is rejected");
   end;

   declare
      Sent : Boolean := False;
      Result : X.Disposition_Kind;
      Output : B.Writer (32);
   begin
      Call (Ping_Request, Sent, Result, Output);
      Check
        ((Result = X.Close_After_Send) and then (not Output.Failed)
         and then Output.Len = 10
         and then Output.Data (1) = 9
         and then Output.Data (2) = 1,
         "ping returns framed pong");
      for I in 1 .. 8 loop
         Check
           (Output.Data (I + 2) = Ping_Request (I + 1),
            "pong echoes ping payload byte" & Integer'Image (I));
      end loop;
   end;

   declare
      Sent : Boolean := False;
      Result : X.Disposition_Kind;
      Output : B.Writer (32);
   begin
      Call ([1 => 0, 2 => 0], Sent, Result, Output);
      Check ((Result = X.Silent_Close) and then (not Sent) and then Output.Len = 0,
             "status request with payload rejected");
      Call ([1 => 2], Sent, Result, Output);
      Check ((Result = X.Silent_Close) and then Output.Len = 0,
             "unknown status packet rejected");
      Call ([1 => 1, 2 => 0], Sent, Result, Output);
      Check ((Result = X.Silent_Close) and then Output.Len = 0,
             "truncated ping rejected");
   end;

   declare
      Sent : Boolean := False;
      Result : X.Disposition_Kind;
      Output : B.Writer (32);
   begin
      X.Handle ([1 => 0], S.Handshake, Sent, Result, Output);
      Check ((Result = X.Silent_Close) and then (not Sent) and then Output.Len = 0,
             "non-status state rejected");
   end;

   if Failures = 0 then
      Ada.Text_IO.Put_Line ("status exchange tests passed");
   else
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
   end if;
end Test_Status_Exchange;
