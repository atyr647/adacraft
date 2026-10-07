with Ada.Command_Line;
with Ada.Directories;
with Ada.Strings.Unbounded;
with Ada.Text_IO;
with Differential.Client;
with Differential.Extract;
with Differential.Obs;

--  Offline extraction tests: multi-packet steps and every outcome.
procedure Test_Diff_Extract is
   package C renames Differential.Client;
   package O renames Differential.Obs;
   package E renames Differential.Extract;
   package SU renames Ada.Strings.Unbounded;
   use type O.Outcome;
   use type Ada.Containers.Count_Type;

   Failures : Natural := 0;

   procedure Check (Cond : Boolean; Name : String) is
   begin
      if not Cond then
         Ada.Text_IO.Put_Line ("FAIL " & Name);
         Failures := Failures + 1;
      end if;
   end Check;

   function Str (J : String) return SU.Unbounded_String is
      N : constant Natural := J'Length;
      R : SU.Unbounded_String;
   begin
      if N < 128 then
         SU.Append (R, Character'Val (N));
      else
         SU.Append (R, Character'Val (128 + N mod 128));
         SU.Append (R, Character'Val (N / 128));
      end if;
      SU.Append (R, J);
      return R;
   end Str;

   Status_Json : constant String :=
     "{""version"":{""name"":""26.3"",""protocol"":777},"
     & """players"":{""max"":20,""online"":0,""sample"":[]},"
     & """description"":{""text"":""A Minecraft Server""},"
     & """favicon"":""data:image/png;base64,AAAA""}";

   function Field (S : O.Step_Observation; N : String) return String is
     (if S.Fields.Contains (N) then S.Fields.Element (N) else "<none>");

   function Log
     (State : C.PS.Connection_State; Sent : Boolean := True)
      return C.Step_Log
   is
      L : C.Step_Log;
   begin
      L.State_After := State;
      L.Sent := Sent;
      return L;
   end Log;

   procedure Add (L : in out C.Step_Log; Id : Natural; P : SU.Unbounded_String)
   is
   begin
      L.Packets.Append ((Id => Id, Payload => P));
      L.No_Data := False;
   end Add;

   L1, L2, L3, L4, L5, L6, L7, L8 : C.Step_Log;
   S : O.Step_Observation;
   Out_Run : C.Run_Output;
   Ob : O.Observation;
begin
   --  Multi-packet step: status response + pong in one step.
   L1 := Log (C.PS.Status);
   Add (L1, 0, Str (Status_Json));
   Add (L1, 1, SU.To_Unbounded_String ("12345678"));
   S := E.Extract_Step (L1);
   Check (S.Result = O.Ok, "status ok");
   Check (Field (S, O.F_Status_Version_Name) = """26.3""", "version name");
   Check (Field (S, O.F_Status_Version_Protocol) = "777", "protocol");
   Check (Field (S, O.F_Status_Players_Max) = "20", "max");
   Check (Field (S, O.F_Status_Players_Online) = "0", "online");
   Check (Field (S, O.F_Status_Description) = "{""text"":""A Minecraft Server""}",
          "description");
   Check (S.Unlisted.Contains ("status.favicon"), "favicon unlisted");
   Check (S.Unlisted.Contains ("status.players.sample"), "sample unlisted");
   Check (S.Unlisted.Contains ("status.pong"), "pong recorded");
   Check (not S.Fields.Contains ("status.favicon"), "favicon not compared");

   --  Rejected login.
   L2 := Log (C.PS.Login);
   Add (L2, 0, Str ("{""text"":""Not allowed""}"));
   S := E.Extract_Step (L2);
   Check (S.Result = O.Rejected, "rejected");
   Check (Field (S, O.F_Login_Outcome) = """rejected""", "login outcome");
   Check (Field (S, O.F_Login_Reason) = "{""text"":""Not allowed""}", "reason");

   --  Disconnected: closed, no packets.
   L3 := Log (C.PS.Login);
   L3.Closed := True;
   S := E.Extract_Step (L3);
   Check (S.Result = O.Disconnected, "disconnected");
   Check (Field (S, O.F_Login_Outcome) = """disconnected""", "disc outcome");

   --  Timeout: sent, nothing came back.
   L4 := Log (C.PS.Status);
   S := E.Extract_Step (L4);
   Check (S.Result = O.Timeout, "timeout");

   --  Malformed: framing error, and bad JSON.
   L5 := Log (C.PS.Status);
   L5.Framing_Error := True;
   Check (E.Extract_Step (L5).Result = O.Malformed, "framing malformed");
   L6 := Log (C.PS.Status);
   Add (L6, 0, Str ("{""version"":"));
   Check (E.Extract_Step (L6).Result = O.Malformed, "bad json malformed");

   --  Terminal: send failed.
   L7 := Log (C.PS.Handshake, Sent => False);
   Check (E.Extract_Step (L7, True).Result = O.Terminal, "terminal");

   --  Skipped step: ok, nothing recorded.
   L8 := Log (C.PS.Status, Sent => False);
   S := E.Extract_Step (L8);
   Check (S.Result = O.Ok and then S.Fields.Is_Empty, "skipped step");

   --  Extra: unrecognised packet lands in unlisted, not compared.
   L8 := Log (C.PS.Status);
   Add (L8, 42, SU.To_Unbounded_String ("xx"));
   S := E.Extract_Step (L8);
   Check (S.Unlisted.Contains ("packet.42") and then S.Fields.Is_Empty,
          "extra packet unlisted");

   --  Whole run.
   Out_Run.Steps.Append (L1);
   Out_Run.Steps.Append (L7);
   Out_Run.Failed := True;
   Ob := E.Extract (Out_Run, "x");
   Check (Ob.Steps.Length = 2, "two observed steps");
   Check (Ob.Steps (2).Result = O.Terminal, "last step terminal");
   Check (Ob.Steps (1).Result = O.Ok, "first step ok");
   Check (SU.To_String (Ob.Scenario_Id) = "x", "scenario id");

   --  Fixture present.
   declare
      Path : constant String :=
        "tests/fixtures/differential/recorded_packet_streams.json";
   begin
      Check (Ada.Directories.Exists (Path), "fixture exists");
   end;

   if Failures = 0 then
      Ada.Text_IO.Put_Line ("test_diff_extract: all passed");
   else
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
   end if;
end Test_Diff_Extract;
