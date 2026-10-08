with Ada.Strings.Unbounded;
with Differential.Transcript;

--  Lab-only ordered semantic comparison of two transcripts.
--  Payload is never recorded and never affects the verdict.
--  Strict order; no reordering tolerance.

package Differential.Compare is

   use Ada.Strings.Unbounded;

   type Verdict is (Match, Diverge);

   type Divergence_Kind is
     (No_Divergence,
      Entry_Mismatch,
      Length_Mismatch,
      Outcome_Mismatch);

   type Comparison_Result is record
      Outcome_Verdict : Verdict := Match;
      Kind            : Divergence_Kind := No_Divergence;
      First_Index     : Natural := 0;
      Oracle_Text     : Unbounded_String := Null_Unbounded_String;
      Candidate_Text  : Unbounded_String := Null_Unbounded_String;
   end record;

   function Compare
     (Oracle    : Transcript.Transcript;
      Candidate : Transcript.Transcript) return Comparison_Result;
   --  MATCH iff same entry count and pairwise equal
   --  (state, direction, packet id) and equal terminal outcomes.
   --  Else DIVERGE at the first differing entry index, or at
   --  index = min length for a count mismatch, or at index =
   --  entry count for an outcome mismatch. Oracle_Text and
   --  Candidate_Text carry the oracle/candidate values at that
   --  point ("end" when one side has no entry there).

   function Verdict_Image (V : Verdict) return String;

   function Divergence_Kind_Image (K : Divergence_Kind) return String;

   function Oracle_Image (R : Comparison_Result) return String;

   function Candidate_Image (R : Comparison_Result) return String;

   function First_Detail (R : Comparison_Result) return String;
   --  Deterministic one-fragment detail for the report line:
   --  "match" when verdict is Match, else
   --  "index=<i> oracle=<o> candidate=<c>".

end Differential.Compare;
