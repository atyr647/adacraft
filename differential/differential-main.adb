--  Lab-only differential driver main (child unit Differential.Main).
--  Only argument dispatch plus calls into child packages.
--  Exits: 0 all-MATCH incl total=0, 1 diverge/selftest fail,
--  2 usage/internal error.

with Ada.Command_Line;
with Ada.Text_IO;
with Differential.Args;
with Differential.Capture;
with Differential.Compare;
with Differential.Report;
with Differential.Selftest;

procedure Differential.Main is
   use Ada.Command_Line;
   use Differential.Args;
   Cfg : constant Config := Parse;
begin
   if Cfg.Mode = Run_Selftest then
      Set_Exit_Status (Exit_Status (Selftest.Run));
      return;
   end if;
   if Cfg.Mode = Usage_Error then
      Args.Put_Usage (Ada.Text_IO.Standard_Error);
      Set_Exit_Status (2);
      return;
   end if;
   declare
      Scenarios : constant Capture.Scenario_List :=
        Capture.Empty_Provider;
      Total    : Natural := 0;
      Matched  : Natural := 0;
      Diverged : Natural := 0;
      O_Host : constant String := Host_Image (Cfg.Oracle);
      C_Host : constant String := Host_Image (Cfg.Candidate);
   begin
      for I in 0 .. Natural (Scenarios.Length) - 1 loop
         declare
            Item : constant Capture.Scenario :=
              Scenarios.Element (I);
            Name : constant String := Capture.Scenario_Name (Item);
            O_T  : Transcript.Transcript;
            C_T  : Transcript.Transcript;
            Res  : Compare.Comparison_Result;
            Line : constant String :=
              Report.Scenario_Line
                (Report.Make_Result
                   (Name, Compare.Compare (O_T, C_T)));
         begin
            Capture.Capture_For_Target
              (O_Host, Cfg.Oracle.Port, Item, O_T);
            Capture.Capture_For_Target
              (C_Host, Cfg.Candidate.Port, Item, C_T);
            Res := Compare.Compare (O_T, C_T);
            Ada.Text_IO.Put_Line
              (Report.Scenario_Line
                 (Report.Make_Result (Name, Res)));
            Total := Total + 1;
            if Res.Outcome_Verdict = Compare.Match then
               Matched := Matched + 1;
            else
               Diverged := Diverged + 1;
            end if;
            pragma Unreferenced (Line);
         end;
      end loop;
      Ada.Text_IO.Put_Line
        (Report.Summary_Line (Total, Matched, Diverged));
      if Diverged > 0 then
         Set_Exit_Status (1);
      else
         Set_Exit_Status (0);
      end if;
   exception
      when others =>
         Set_Exit_Status (2);
   end;
exception
   when others =>
      Set_Exit_Status (2);
end Differential.Main;
