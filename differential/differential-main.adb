--  Lab-only driver dispatch. Argument dispatch and calls only.
--  No state/direction/outcome types, no match logic here.
--  Known gap: only Empty_Provider exists, so a real run reports
--  total=0 match=0 diverge=0 with exit 0 until a loader lands.
with Ada.Command_Line;
with Ada.Strings.Unbounded;
with Ada.Text_IO;
with Differential.Args;
with Differential.Capture;
with Differential.Compare;
with Differential.Report;
with Differential.Selftest;
with Differential.Transcript;

procedure Differential.Main is
   use Ada.Strings.Unbounded;
begin
   declare
      Is_Selftest : Boolean;
      Oracle      : Differential.Args.Endpoint;
      Candidate   : Differential.Args.Endpoint;
      Valid       : Boolean;
   begin
      Differential.Args.Parse_Command_Line
        (Is_Selftest => Is_Selftest,
         Oracle      => Oracle,
         Candidate   => Candidate,
         Valid       => Valid);
      if not Valid then
         Differential.Args.Print_Usage;
         Ada.Command_Line.Set_Exit_Status (2);
         return;
      end if;
      if Is_Selftest then
         Ada.Command_Line.Set_Exit_Status
           (Ada.Command_Line.Exit_Status (Differential.Selftest.Run));
         return;
      end if;
      declare
         Count : constant Natural := Differential.Capture.Scenario_Count;
      begin
         if Count = 0 then
            Ada.Text_IO.Put_Line ("total=0 match=0 diverge=0");
            Ada.Command_Line.Set_Exit_Status (0);
            return;
         end if;
         declare
            Results : Differential.Report.Result_Array (1 .. Count);
            Diverged : Boolean := False;
         begin
            for I in 1 .. Count loop
               declare
                  Scenario : constant Differential.Capture.Scenario_Kind :=
                    Differential.Capture.Scenario_At (I);
                  Name : constant String :=
                    Differential.Capture.Scenario_Name (Scenario);
                  TO : Differential.Transcript.Transcript;
                  TC : Differential.Transcript.Transcript;
                  Fail_O : Boolean;
                  Fail_C : Boolean;
                  V  : Differential.Compare.Verdict;
               begin
                  Differential.Capture.Run_Scenario (Oracle, Scenario, TO, Fail_O);
                  Differential.Capture.Run_Scenario
                    (Candidate, Scenario, TC, Fail_C);
                  if Fail_O or else Fail_C then
                     Ada.Text_IO.Put_Line
                       (File => Ada.Text_IO.Standard_Error,
                        Item => "differential: target unreachable before any scenario");
                     Ada.Command_Line.Set_Exit_Status (2);
                     return;
                  end if;
                  V := Differential.Compare.Compare (TO, TC);
                  Results (I) :=
                    (Name    => To_Unbounded_String (Name),
                     Outcome => V);
                  if not Differential.Compare.Is_Match (V) then
                     Diverged := True;
                  end if;
               end;
            end loop;
            Ada.Text_IO.Put_Line (Differential.Report.Render (Results));
            if Diverged then
               Ada.Command_Line.Set_Exit_Status (1);
            else
               Ada.Command_Line.Set_Exit_Status (0);
            end if;
         end;
      end;
   end;
end Differential.Main;
