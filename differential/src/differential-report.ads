with Differential.Transcript;

package Differential.Report is

   --  Deterministic rendering for differential verdicts.
   --  Pure functions of their inputs: no timestamps, no durations,
   --  no wall-clock. Byte-identical output for identical inputs.

   --  Render one scenario line:
   --    "<Name> MATCH"                  when Matched and Detail empty
   --    "<Name> DIVERGE <Detail>"       otherwise with detail text
   --  Detail carries the first difference, e.g. "first diff ...".
   function Render
     (Name    : String;
      Matched : Boolean;
      Detail  : String := "") return String;

   --  Render the final summary line:
   --    "total=N match=M diverge=D"
   function Render_Summary
     (Total    : Natural;
      Matched  : Natural;
      Diverged : Natural) return String;

   --  Build the "first diff oracle vs candidate" detail text from
   --  the compared transcripts. Pure function of its inputs.
   function First_Diff_Detail
     (Oracle           : Differential.Transcript.Transcript;
      Candidate        : Differential.Transcript.Transcript;
      First_Index      : Natural;
      Outcome_Mismatch : Boolean) return String;

   --  Output helpers. Callers iterate in provider order so output
   --  order is deterministic.
   procedure Put_Report (Line : String);

   procedure Put_Report
     (Name    : String;
      Matched : Boolean;
      Detail  : String := "");

   procedure Put_Summary
     (Total    : Natural;
      Matched  : Natural;
      Diverged : Natural);

end Differential.Report;
