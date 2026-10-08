with Differential.Transcript;

package Differential.Capture is
   --  Lab-only orchestration + transcript building.
   --  Empty_Provider only (no corpus loader - Q1 deferred).
   --  Socket I/O lives in child Differential.Capture.Wire;
   --  this parent drives the same bytes vs oracle + candidate,
   --  tracks transitions via State Machine (#118), appends
   --  Transcript_Entry values. Failures become terminal
   --  outcomes, never propagate.

   procedure Empty_Provider (Count : out Natural);
   --  Sets Count to 0. No corpus loader yet (known gap).

   procedure Capture_Single
     (Host           : in String;
      Port           : in Natural;
      Scenario_Index : in Natural;
      T              : out Differential.Transcript.Transcript);
   --  Open Host:Port via Wire, drive scenario bytes (none for
   --  Empty_Provider), track #118 transitions, append entries.
   --  Never raises; failures map to T.Outcome.

   procedure Capture_Pair
     (Oracle_Host    : in String;
      Oracle_Port    : in Natural;
      Candidate_Host : in String;
      Candidate_Port : in Natural;
      Scenario_Index : in Natural;
      Oracle_T       : out Differential.Transcript.Transcript;
      Candidate_T    : out Differential.Transcript.Transcript);
   --  Capture the same scenario vs oracle and candidate.

end Differential.Capture;
