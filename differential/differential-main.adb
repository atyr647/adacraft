--  Lab-only differential driver entry point.
--  Child unit Differential.Main: argument dispatch + calls only.
--  No state/direction/result/match logic lives here; comparison and
--  transcript types come from Differential.Compare/Transcript.

with Ada.Command_Line;
with Differential.Args;
with Differential.Capture;
with Differential.Compare;
with Differential.Report;
with Differential.Selftest;
with Differential.Transcript;

procedure Differential.Main is
   use type Differential.Args.Mode_Kind;
   use type Differential.Compare.Verdict;
   use type Differential.Transcript.Terminal_Outcome;

   Opts : Differential.Args.Options;

   function Image (N : Natural) return String is
      S : constant String := Natural'Image (N);
   begin
      if S'Length > 0 and then S (S'First) = ' ' then
         return S (S'First + 1 .. S'Last);
      end if;
      return S;
   end Image;

   procedure Fail_Usage is
   begin
      Differential.Args.Usage;
      Ada.Command_Line.Set_Exit_Status (2);
   end Fail_Usage;

   procedure Do_Selftest is
      Code : Integer;
   begin
      Code := Differential.Selftest.Run;
      if Code = 0 then
         Ada.Command_Line.Set_Exit_Status (0);
      else
         Ada.Command_Line.Set_Exit_Status (1);
      end if;
   end Do_Selftest;

   procedure Do_Run is
      Total    : Natural := 0;
      Matched  : Natural := 0;
      Diverged : Natural := 0;
      Failed   : Boolean := False;
   begin
      Total := Differential.Capture.Scenario_Count;
      if Total = 0 then
         Differential.Report.Put_Summary (0, 0, 0);
         Ada.Command_Line.Set_Exit_Status (0);
         return;
      end if;
      for I in 1 .. Total loop
         declare
            Name : constant String := "scenario-" & Image (I);
            Steps : Differential.Capture.Script :=
              Differential.Capture.Empty_Script;
            Oracle_Res : Differential.Transcript.Target_Result :=
              Differential.Capture.Run_Scenario (Opts.Oracle, Steps);
            Candidate_Res : Differential.Transcript.Target_Result :=
              Differential.Capture.Run_Scenario (Opts.Candidate, Steps);
         begin
            if Oracle_Res.Outcome = Differential.Transcript.Driver_Error
              or else Candidate_Res.Outcome
                = Differential.Transcript.Driver_Error
            then
               Failed := True;
               exit;
            end if;
            declare
               Detail : constant Differential.Compare.Comparison_Result :=
                 Differential.Compare.Compare (Oracle_Res, Candidate_Res);
            begin
               Differential.Report.Put_Verdict
                 (Name, Detail.Verdict, Detail);
               if Detail.Verdict = Differential.Compare.MATCH then
                  Matched := Matched + 1;
               else
                  Diverged := Diverged + 1;
               end if;
            end;
         end;
      end loop;
      if Failed then
         Ada.Command_Line.Set_Exit_Status (2);
      else
         Differential.Report.Put_Summary (Total, Matched, Diverged);
         if Diverged > 0 then
            Ada.Command_Line.Set_Exit_Status (1);
         else
            Ada.Command_Line.Set_Exit_Status (0);
         end if;
      end if;
   exception
      when others =>
         Ada.Command_Line.Set_Exit_Status (2);
   end Do_Run;

begin
   begin
      Opts := Differential.Args.Parse;
   exception
      when Differential.Args.Usage_Error =>
         Fail_Usage;
         return;
   end;
   if Opts.Mode = Differential.Args.Selftest then
      Do_Selftest;
   else
      Do_Run;
   end if;
exception
   when Differential.Args.Usage_Error =>
      Fail_Usage;
   when others =>
      Ada.Command_Line.Set_Exit_Status (2);
end Differential.Main;
