with Ada.Command_Line;
with Ada.Text_IO;
with Interfaces;
with Adacraft.Protocol;
with Adacraft.Protocol.Buffer;
with Adacraft.Protocol.Handshake_Exchange;
with Adacraft.Protocol.State;

procedure Test_Handshake_Exchange is
   package P renames Adacraft.Protocol;
   package H renames Adacraft.Protocol.Handshake_Exchange;
   package S renames Adacraft.Protocol.State;
   use type H.Disposition_Kind;
   use type S.Connection_State;

   Failures : Natural := 0;

   procedure Check (Condition : Boolean; Name : String) is
   begin
      if not Condition then
         Failures := Failures + 1;
         Ada.Text_IO.Put_Line ("FAIL: " & Name);
      end if;
   end Check;

   procedure Try
     (Input       : P.Octets;
      State       : in out S.Connection_State;
      Version     : out Natural;
      Disposition : out H.Disposition_Kind)
   is
      Output : P.Buffer.Writer (32);
   begin
      H.Handle (Input, State, Version, Disposition, Output);
      Check (Output.Len = 0 and then not Output.Failed, "no response bytes");
   end Try;

   Status_Packet : constant P.Octets :=
     (1 => 0, 2 => 16#F9#, 3 => 16#05#,
      4 => 3, 5 => Character'Pos ('a'), 6 => Character'Pos ('b'),
      7 => Character'Pos ('c'), 8 => 16#63#, 9 => 16#DD#, 10 => 1);
   Login_Packet : constant P.Octets :=
     (1 => 0, 2 => 16#F9#, 3 => 16#05#,
      4 => 3, 5 => Character'Pos ('a'), 6 => Character'Pos ('b'),
      7 => Character'Pos ('c'), 8 => 16#63#, 9 => 16#DD#, 10 => 2);
   Invalid_Intent : constant P.Octets :=
     (1 => 0, 2 => 16#F9#, 3 => 16#05#,
      4 => 3, 5 => Character'Pos ('a'), 6 => Character'Pos ('b'),
      7 => Character'Pos ('c'), 8 => 16#63#, 9 => 16#DD#, 10 => 4);
   Truncated : constant P.Octets := (1 => 0, 2 => 16#F9#);
   Overlong : constant P.Octets :=
     (1 => 0, 2 => 16#F9#, 3 => 16#85#, 4 => 0);
   Trailing : constant P.Octets :=
     (1 => 0, 2 => 16#F9#, 3 => 16#05#,
      4 => 3, 5 => Character'Pos ('a'), 6 => Character'Pos ('b'),
      7 => Character'Pos ('c'), 8 => 16#63#, 9 => 16#DD#,
      10 => 1, 11 => 0);
   Wrong_Id : constant P.Octets :=
     (1 => 1, 2 => 16#F9#, 3 => 16#05#,
      4 => 3, 5 => Character'Pos ('a'), 6 => Character'Pos ('b'),
      7 => Character'Pos ('c'), 8 => 16#63#, 9 => 16#DD#, 10 => 1);
begin
   declare
      Current : S.Connection_State := S.Handshake;
      Version : Natural;
      Result  : H.Disposition_Kind;
   begin
      Try (Status_Packet, Current, Version, Result);
      Check (Result = H.Progress and Current = S.Status and Version = 777,
             "valid Status intention transitions and records version");
   end;

   declare
      Current : S.Connection_State := S.Handshake;
      Version : Natural;
      Result  : H.Disposition_Kind;
   begin
      Try (Login_Packet, Current, Version, Result);
      Check (Result = H.Progress and Current = S.Login and Version = 777,
             "valid Login intention transitions and records version");
   end;

   for Packet of (Invalid_Intent, Truncated, Overlong, Trailing, Wrong_Id) loop
      declare
         Current : S.Connection_State := S.Handshake;
         Version : Natural;
         Result  : H.Disposition_Kind;
      begin
         Try (Packet, Current, Version, Result);
         Check (Result = H.Silent_Close and Current = S.Handshake and Version = 0,
                "invalid handshake closes without changing state");
      end;
   end loop;

   if Failures = 0 then
      Ada.Text_IO.Put_Line ("handshake exchange tests passed");
   else
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
   end if;
end Test_Handshake_Exchange;
