with Adacraft.Protocol.State;
with Differential.Transcript;

package Differential.Compare is

   --  Pure semantic comparison of two scenario transcripts.
   --  No I/O.  Payload is never an input and cannot cause divergence.

   type Verdict_Kind is (Match, Diverge_Length, Diverge_Entry, Diverge_Outcome);

   type Verdict is record
      Kind             : Verdict_Kind := Match;
      Index            : Natural := 0;
      Expected_Length  : Natural := 0;
      Got_Length       : Natural := 0;
      Expected_Entry   : Differential.Transcript.Transcript_Entry;
      Got_Entry        : Differential.Transcript.Transcript_Entry;
      Expected_Outcome : Differential.Outcome := Differential.Completed;
      Got_Outcome      : Differential.Outcome := Differential.Completed;
   end record;

   function Compare
     (Expected : Differential.Transcript.Scenario_Result;
      Got      : Differential.Transcript.Scenario_Result) return Verdict;

end Differential.Compare;
