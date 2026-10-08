with Ada.Command_Line;
with Ada.Text_IO;
with Adacraft.Protocol.State;
with Differential.Args;
with Differential.Capture;
with Differential.Compare;
with Differential.Report;
with Differential.Transcript;

procedure Differential.Main is
   --  Lab-only driver main (child unit Differential.Main).
   --  Wiring only: Args.Parse -> (Selftest | Capture+Compare+Report) ->
   --  Set_Exit_Status.  No framing, no codec, no logic beyond wiring.
   --  The corpus provider is deferred; the run branch wires the capture,
   --  compare, report, and exit-status stages.

   use type Ada.Command_Line.Exit_Status;

   Opts : Differential.Args.Options;

   type Empty_Provider is
     new Differential.Capture.Provider with null record;

   overriding function Count
     (P : Empty_Provider) return Natural is
   begin
      return 0;
   end Count;

   overriding procedure Get
     (P     : in out Empty_Provider;
      Index : Positive;
      Item  : out Differential.Capture.Scenario_Descriptor) is
   begin
      raise Constraint_Error with "empty scenario provider";
   end Get;

   function Base_Result return Differential.Transcript.Scenario_Result is
      R  : Differential.Transcript.Scenario_Result;
      Ok : Boolean;
      E1 : constant Differential.Transcript.Transcript_Entry :=
        (State     => Adacraft.Protocol.State.Handshake,
         Direction => Adacraft.Protocol.State.Serverbound,
         Id        => 0);
      E2 : constant Differential.Transcript.Transcript_Entry :=
        (State     => Adacraft.Protocol.State.Status,
         Direction => Adacraft.Protocol.State.Clientbound,
         Id        => 1);
   begin
      Differential.Transcript.Set_Name (R, "selftest");
      Differential.Transcript.Append (R.Entries, E1, Ok);
      Differential.Transcript.Append (R.Entries, E2, Ok);
      R.Outcome := Differential.Completed;
      return R;
   end Base_Result;

   procedure Check
     (Name          : String;
      A, B          : Differential.Transcript.Scenario_Result;
      Expected_Kind : Differential.Compare.Verdict_Kind;
      Expected_Idx  : Natural;
      Failed        : in out Boolean)
   is
      V : constant Differential.Compare.Verdict :=
        Differential.Compare.Compare (A, B);
   begin
      if V.Kind /= Expected_Kind or else V.Index /= Expected_Idx then
         Failed := True;
         Ada.Text_IO.Put_Line
           (Ada.Text_IO.Standard_Error,
            "SELFTEST FAIL " & Name
            & " expected=("
            & Differential.Compare.Verdict_Kind'Image (Expected_Kind)
            & "," & Natural'Image (Expected_Idx) & ")"
            & " got=("
            & Differential.Compare.Verdict_Kind'Image (V.Kind)
            & "," & Natural'Image (V.Index) & ")"
            & " " & Differential.Report.Entry_Detail
              (Index          => 1,
               Expected_Entry => V.Expected_Entry,
               Got_Entry      => V.Got_Entry));
      end if;
   end Check;

   procedure Run_Selftest is
      use type Differential.Compare.Verdict_Kind;
      Failed : Boolean := False;
      A, B   : Differential.Transcript.Scenario_Result;
   begin
      A := Base_Result; B := Base_Result;
      Check ("identical", A, B, Differential.Compare.Match, 0, Failed);
      A := Base_Result; B := Base_Result;
      Check ("payload-ignored", A, B, Differential.Compare.Match, 0, Failed);
      A := Base_Result; B := Base_Result;
      B.Entries.Entries (2).Id := 2;
      Check ("diff-id", A, B, Differential.Compare.Diverge_Entry, 2, Failed);
      A := Base_Result; B := Base_Result;
      B.Entries.Entries (1).State := Adacraft.Protocol.State.Login;
      Check ("diff-state", A, B, Differential.Compare.Diverge_Entry, 1, Failed);
      A := Base_Result; B := Base_Result;
      B.Entries.Entries (1).Direction := Adacraft.Protocol.State.Clientbound;
      Check ("diff-direction", A, B,
             Differential.Compare.Diverge_Entry, 1, Failed);
      A := Base_Result; B := Base_Result;
      B.Entries.Count := 1;
      Check ("diff-length", A, B,
             Differential.Compare.Diverge_Length, 2, Failed);
      A := Base_Result; B := Base_Result;
      B.Outcome := Differential.Peer_Closed;
      Check ("diff-outcome", A, B,
             Differential.Compare.Diverge_Outcome, 0, Failed);
      if Failed then
         Ada.Command_Line.Set_Exit_Status (1);
      else
         Ada.Text_IO.Put_Line ("SELFTEST PASS 7/7");
         Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Success);
      end if;
   end Run_Selftest;

   procedure Run_Differential is
      Source : Empty_Provider;
      Oracle_Results :
        Differential.Capture.Result_Array
          (1 .. Differential.Capture.Max_Scenario_Count);
      Candidate_Results :
        Differential.Capture.Result_Array
          (1 .. Differential.Capture.Max_Scenario_Count);
      Total    : Natural := 0;
      Matched  : Natural := 0;
      Diverged : Natural := 0;
   begin
      Differential.Capture.Run_All
        (Oracle         => Opts.Oracle,
         Candidate      => Opts.Candidate,
         Source         => Source,
         Oracle_Out     => Oracle_Results,
         Candidate_Out  => Candidate_Results,
         Total          => Total);

      for I in 1 .. Total loop
         declare
            Expected : constant Differential.Transcript.Scenario_Result :=
              Oracle_Results (I);
            Got : constant Differential.Transcript.Scenario_Result :=
              Candidate_Results (I);
            Verdict : constant Differential.Compare.Verdict :=
              Differential.Compare.Compare (Expected, Got);
            Name : constant String :=
              Differential.Transcript.Name_Str (Expected);
         begin
            if Verdict.Kind = Differential.Compare.Match then
               Matched := Matched + 1;
               Differential.Report.Put_Match (Name);
            else
               Diverged := Diverged + 1;
               case Verdict.Kind is
                  when Differential.Compare.Diverge_Length =>
                     Differential.Report.Put_Diverge
                       (Name,
                        Differential.Report.Length_Detail
                          (Verdict.Expected_Length,
                           Verdict.Got_Length,
                           Verdict.Index));
                  when Differential.Compare.Diverge_Entry =>
                     Differential.Report.Put_Diverge
                       (Name,
                        Differential.Report.Entry_Detail
                          (Verdict.Index,
                           Verdict.Expected_Entry,
                           Verdict.Got_Entry));
                  when Differential.Compare.Diverge_Outcome =>
                     Differential.Report.Put_Diverge
                       (Name,
                        Differential.Report.Outcome_Detail
                          (Verdict.Expected_Outcome,
                           Verdict.Got_Outcome));
                  when Differential.Compare.Match =>
                     null;
               end case;
            end if;
         end;
      end loop;

      Differential.Report.Put_Summary (Total, Matched, Diverged);
      Differential.Report.Apply_Exit
        (Diverged => Diverged, Env_Error => False);
   exception
      when Differential.Capture.Env_Error =>
         Differential.Report.Put_Summary (Total, Matched, Diverged);
         Differential.Report.Apply_Exit
           (Diverged => Diverged, Env_Error => True);
   end Run_Differential;

begin
   Differential.Args.Parse (Opts);
   if Ada.Command_Line.Exit_Status /= Ada.Command_Line.Success then
      Ada.Command_Line.Set_Exit_Status (2);
      return;
   end if;
   if Opts.Selftest then
      Run_Selftest;
      return;
   end if;
   Run_Differential;
end Differential.Main;
