--  Lab-only deterministic reporting for the differential harness.
--  Corpus order, fixed formats, no timestamps/addresses/timings.

with Differential.Compare;
with Differential.Transcript;

package Differential.Report is
   pragma Elaborate_Body;

   --  One line per scenario: "name: MATCH" or "name: DIVERGE ..." with
   --  the first difference (index, oracle entry, candidate entry,
   --  or outcome mismatch).
   procedure Put_Verdict
     (Name    : in String;
      Verdict : in Compare.Verdict;
      Detail  : in Compare.Comparison_Result);

   --  Final line: "summary: total=.. match=.. diverge=..".
   procedure Put_Summary
     (Total   : in Natural;
      Matched : in Natural;
      Diverged : in Natural);

   --  Image helpers (fixed formats, no locale dependence).
   function Image_Of (E : Transcript.Transcript_Entry) return String;
   function Image_Of (O : Transcript.Terminal_Outcome) return String;

end Differential.Report;
