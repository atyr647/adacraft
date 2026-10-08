--  Lab-only deterministic report rendering for the differential driver.
--  Pure function Render takes names + verdicts only; no timestamps,
--  addresses, ports, or timing. Byte-identical for same inputs.
with Ada.Strings.Unbounded;
with Differential.Compare;
with Differential.Transcript;

package Differential.Report is

   use Ada.Strings.Unbounded;

   type Result_Entry is record
      Name    : Unbounded_String := Null_Unbounded_String;
      Outcome : Differential.Compare.Verdict;
   end record;

   type Result_Array is array (Positive range <>) of Result_Entry;

   --  Render one line per scenario in provider (array) order with
   --  MATCH/DIVERGE, plus a final total=<n> match=<m> diverge=<d> line.
   --  Pure: output depends only on Names and Verdicts in Results.
   function Render (Results : Result_Array) return String;

   function Entry_Image
     (Item : Differential.Transcript.Transcript_Entry) return String;

   function Outcome_Image
     (Value : Differential.Transcript.Terminal_Outcome) return String;

end Differential.Report;
