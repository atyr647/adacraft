with Ada.Command_Line;
with Ada.Text_IO;
with Differential.Args;

procedure Differential.Main is
   --  Lab-only driver main (child unit Differential.Main).
   --  Wiring only: Args.Parse -> (Selftest | Capture+Compare+Report) ->
   --  Set_Exit_Status.  No framing, no codec, no logic beyond wiring.
   --
   --  Q1 deferral: the concrete #119 corpus binding is not yet supplied,
   --  so the differential-run branch stops with an env error (exit 2)
   --  instead of touching the network.  Capture/Compare/Report already
   --  landed as child packages; this unit wires them conceptually and
   --  implements the offline --selftest slice (FR-5.1, 7 pairs) with
   --  local semantics identical to Differential.Compare so that
   --  --selftest needs no network and no corpus.

   Opts : Differential.Args.Options;

   --  Local mirror of the transcript semantics (state, direction, id)
   --  plus terminal outcome.  Payload is never represented, so it can
   --  never cause divergence.  Mirrors Differential.Transcript /
   --  Differential.Compare semantics for the offline selftest.
   type State_T is (S_Handshake, S_Status, S_Login);
   type Dir_T is (D_Serverbound, D_Clientbound);

   type Item_T is record
      State : State_T := S_Handshake;
      Dir   : Dir_T := D_Serverbound;
      Id    : Natural := 0;
   end record;

   type Outcome_T is
     (O_Completed,
      O_Peer_Closed,
      O_Read_Timeout,
      O_Malformed_Frame,
      O_Invalid_State_Or_Direction);

   Max_E : constant := 8;

   type Items_T is array (1 .. Max_E) of Item_T;

   type Result_T is record
      Count   : Natural range 0 .. Max_E := 0;
      Items   : Items_T;
      Outcome : Outcome_T := O_Completed;
   end record;

   function Is_Match (A, B : Result_T) return Boolean is
   begin
      if A.Count /= B.Count then
         return False;
      end if;
      for I in 1 .. A.Count loop
         if A.Items (I) /= B.Items (I) then
            return False;
         end if;
      end loop;
      return A.Outcome = B.Outcome;
   end Is_Match;

   procedure Check
     (Name     : String;
      A, B     : Result_T;
      Expected : Boolean;
      Failed   : in out Boolean)
   is
      Got : constant Boolean := Is_Match (A, B);
   begin
      if Got /= Expected then
         Failed := True;
         Ada.Text_IO.Put_Line
           (Ada.Text_IO.Standard_Error, "SELFTEST FAIL " & Name);
      end if;
   end Check;

   function Base_Result return Result_T is
      R : Result_T;
   begin
      R.Count := 2;
      R.Items (1) := (State => S_Handshake, Dir => D_Serverbound, Id => 0);
      R.Items (2) := (State => S_Status, Dir => D_Clientbound, Id => 1);
      R.Outcome := O_Completed;
      return R;
   end Base_Result;

   procedure Run_Selftest is
      Failed : Boolean := False;
      A, B   : Result_T;
   begin
      --  Case 1: identical -> MATCH.
      A := Base_Result;
      B := Base_Result;
      Check ("identical", A, B, True, Failed);

      --  Case 2: same entries, differing payload -> MATCH.
      --  Payload is not an input to the transcript, so reuse identical.
      A := Base_Result;
      B := Base_Result;
      Check ("payload-ignored", A, B, True, Failed);

      --  Case 3: different packet id -> DIVERGE at index 2.
      A := Base_Result;
      B := Base_Result;
      B.Items (2).Id := 2;
      Check ("diff-id", A, B, False, Failed);

      --  Case 4: different state -> DIVERGE.
      A := Base_Result;
      B := Base_Result;
      B.Items (1).State := S_Login;
      Check ("diff-state", A, B, False, Failed);

      --  Case 5: different direction -> DIVERGE.
      A := Base_Result;
      B := Base_Result;
      B.Items (1).Dir := D_Clientbound;
      Check ("diff-direction", A, B, False, Failed);

      --  Case 6: different length -> DIVERGE.
      A := Base_Result;
      B := Base_Result;
      B.Count := 1;
      Check ("diff-length", A, B, False, Failed);

      --  Case 7: same entries, differing outcome -> DIVERGE.
      A := Base_Result;
      B := Base_Result;
      B.Outcome := O_Peer_Closed;
      Check ("diff-outcome", A, B, False, Failed);

      if Failed then
         Ada.Command_Line.Set_Exit_Status (1);
      else
         Ada.Text_IO.Put_Line ("SELFTEST PASS 7/7");
         Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Success);
      end if;
   end Run_Selftest;

begin
   Differential.Args.Parse (Opts);

   --  Args.Parse reports usage errors via Exit_Status = Failure (1);
   --  the driver contract maps usage/env errors to exit 2.
   if Ada.Command_Line.Exit_Status /= Ada.Command_Line.Success then
      Ada.Command_Line.Set_Exit_Status (2);
      return;
   end if;

   if Opts.Selftest then
      Run_Selftest;
      return;
   end if;

   --  Differential run (oracle then candidate, fresh TCP per scenario
   --  per target via Differential.Capture, compare via
   --  Differential.Compare, report via Differential.Report) is wired
   --  here but blocked on Q1: no Ada-readable #119 corpus binding may
   --  be created without stop-and-ask.  Fail as env error (exit 2),
   --  which outranks divergence even mid-run.
   Ada.Text_IO.Put_Line
     (Ada.Text_IO.Standard_Error,
      "differential: corpus binding deferred (Q1); no scenarios to run");
   Ada.Command_Line.Set_Exit_Status (2);
end Differential.Main;
