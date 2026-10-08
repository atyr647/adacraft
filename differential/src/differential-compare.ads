--  Lab-only ordered exact comparison for the differential harness.
--  MATCH iff ordered (state, direction, packet-ID) sequences are equal
--  and terminal outcomes are equal. Payloads are never consulted.

with Differential.Transcript;

package Differential.Compare is
   pragma Elaborate_Body;

   --  Overall verdict for one scenario compared across two targets.
   type Verdict is (MATCH, DIVERGE);

   --  Machine-readable shape of the first divergence found.
   type Divergence_Kind is
     (No_Divergence,
      Length_Mismatch,
      Entry_Mismatch,
      Outcome_Difference);

   --  Default probe entry used when the diverging index exists on
   --  only one side (length mismatch) or on neither side (outcome only).
   function Default_Entry return Transcript.Transcript_Entry;

   --  Full comparison detail for one scenario.
   --    Verdict = MATCH  -> Kind = No_Divergence, First_Index = 0,
   --                        Outcome_Mismatch = False.
   --    Verdict = DIVERGE via entries -> Kind is Length_Mismatch or
   --                        Entry_Mismatch, First_Index is the 0-based
   --                        index of the first difference, Oracle_Entry
   --                        / Candidate_Entry hold the differing pair
   --                        (or Default_Entry when one side is short).
   --    Verdict = DIVERGE via outcome only -> Kind = Outcome_Difference,
   --                        Outcome_Mismatch = True, entry fields carry
   --                        Default_Entry.
   type Comparison_Result is record
      Verdict          : Differential.Compare.Verdict := MATCH;
      Kind             : Divergence_Kind := No_Divergence;
      First_Index      : Natural := 0;
      Oracle_Entry     : Transcript.Transcript_Entry := Default_Entry;
      Candidate_Entry  : Transcript.Transcript_Entry := Default_Entry;
      Outcome_Mismatch : Boolean := False;
   end record;

   --  Ordered exact compare of two target results.
   function Compare
     (Oracle    : Transcript.Target_Result;
      Candidate : Transcript.Target_Result) return Comparison_Result;

end Differential.Compare;
