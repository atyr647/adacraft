with Ada.Command_Line;
with Ada.Text_IO;
with GNAT.Sockets;
with Differential.Args;
with Differential.Capture;
with Differential.Compare;
with Differential.Report;
with Differential.Selftest;
with Differential.Transcript;

procedure Differential.Main is
   use type Differential.Args.Mode_Kind;
   use type Differential.Compare.Verdict;
   Cfg : Differential.Args.Config := Differential.Args.Parse;
begin
   if not Cfg.Valid then
      Ada.Text_IO.Put_Line
        (Ada.Text_IO.Standard_Error,
         Differential.Args.Msg_Strings.To_String (Cfg.Error_Msg));
      Differential.Args.Print_Usage;
      Ada.Command_Line.Set_Exit_Status (2);
      return;
   end if;

   if Cfg.Mode = Differential.Args.Selftest then
      Ada.Command_Line.Set_Exit_Status
        (Ada.Command_Line.Exit_Status (Differential.Selftest.Run_Selftest));
      return;
   end if;

   declare
      Results  : Differential.Capture.Result_Array;
      Count    : Natural := 0;
      Matched  : Natural := 0;
      Diverged : Natural := 0;
   begin
      Differential.Capture.Run_All (Cfg, Results, Count);
      for I in 1 .. Count loop
         declare
            Oracle_Len : constant Natural :=
              Differential.Transcript.Get_Length (Results (I).Oracle);
            Cand_Len : constant Natural :=
              Differential.Transcript.Get_Length (Results (I).Candidate);
            pragma Unreferenced (Oracle_Len, Cand_Len);
            R : constant Differential.Compare.Comparison_Result :=
              Differential.Compare.Compare
                (Results (I).Oracle, Results (I).Candidate);
            Name : constant String :=
              Differential.Capture.Name_Strings.To_String (Results (I).Name);
            Is_Match : constant Boolean :=
              R.Result = Differential.Compare.Match;
            Detail : constant String :=
              (if Is_Match then ""
               else Differential.Report.First_Diff_Detail
                 (Results (I).Oracle, Results (I).Candidate,
                  R.First_Index, R.Outcome_Mismatch));
         begin
            Differential.Report.Put_Report
              (Differential.Report.Render (Name, Is_Match, Detail));
            if Is_Match then
               Matched := Matched + 1;
            else
               Diverged := Diverged + 1;
            end if;
         end;
      end loop;
      Differential.Report.Put_Summary (Count, Matched, Diverged);
      if Diverged > 0 then
         Ada.Command_Line.Set_Exit_Status (1);
      else
         Ada.Command_Line.Set_Exit_Status (0);
      end if;
   exception
      when GNAT.Sockets.Socket_Error | Constraint_Error =>
         Differential.Args.Print_Usage;
         Ada.Command_Line.Set_Exit_Status (2);
      when others =>
         Differential.Args.Print_Usage;
         Ada.Command_Line.Set_Exit_Status (2);
   end;
end Differential.Main;
