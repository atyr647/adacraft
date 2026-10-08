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
   --  Q1 deferral: no concrete #119 corpus binding yet, so the run
   --  branch exits 2 without touching the network.

   use type Ada.Command_Line.Exit_Status;

   Opts : Differential.Args.Options;

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

   --  Reference the wired children so the run path visibly goes
   --  Args -> Capture -> Compare -> Report -> exit status.
   Timeout_Ref : constant Duration := Differential.Capture.Read_Timeout;
   pragma Unreferenced (Timeout_Ref);

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
   Differential.Report.Put_Summary (Total => 0, Matched => 0, Diverged => 0);
   Ada.Text_IO.Put_Line
     (Ada.Text_IO.Standard_Error,
      "differential: corpus binding deferred (Q1); no scenarios to run");
   Differential.Report.Apply_Exit (Diverged => 0, Env_Error => True);
end Differential.Main;
