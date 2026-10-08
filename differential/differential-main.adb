with Ada.Command_Line;
with Differential.Args;
with Differential.Capture;
with Differential.Compare;
with Differential.Report;
with Differential.Selftest;
with Differential.Transcript;

procedure Differential.Main is
   use Ada.Command_Line;
   Opts : Differential.Args.Options;
begin
   begin
      Differential.Args.Parse_Command_Line (Opts);
   exception
      when Differential.Args.Usage_Error =>
         Differential.Args.Print_Usage;
         Set_Exit_Status (2);
         return;
   end;
   if Opts.Selftest then
      declare
         Code : constant Natural := Differential.Selftest.Check;
      begin
         if Code = 0 then
            Set_Exit_Status (0);
         else
            Set_Exit_Status (1);
         end if;
      end;
      return;
   end if;
   declare
      Count    : Natural := 0;
      Matched  : Natural := 0;
      Diverged : Natural := 0;
   begin
      Differential.Capture.Empty_Provider (Count);
      --  Corpus order: scenario indices 1 .. Count (today 0).
      for I in 1 .. Count loop
         declare
            OT : Differential.Transcript.Transcript;
            CT : Differential.Transcript.Transcript;
            use type Differential.Compare.Verdict;
            V  : Differential.Compare.Verdict;
         begin
            Differential.Capture.Capture_Pair
              (Differential.Args.Host_Image (Opts.Oracle),
               Opts.Oracle.Port,
               Differential.Args.Host_Image (Opts.Candidate),
               Opts.Candidate.Port,
               I, OT, CT);
            V := Differential.Compare.Compare (OT, CT);
            if V = Differential.Compare.Match then
               Matched := Matched + 1;
            else
               Diverged := Diverged + 1;
            end if;
            Differential.Report.Put_Scenario ("scenario" & Integer'Image (I), OT, CT);
         end;
      end loop;
      Differential.Report.Put_Summary (Count, Matched, Diverged);
      if Diverged > 0 then
         Set_Exit_Status (1);
      else
         Set_Exit_Status (0);
      end if;
   exception
      when others =>
         Differential.Args.Print_Usage;
         Set_Exit_Status (2);
   end;
end Differential.Main;
