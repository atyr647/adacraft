with Ada.Strings.Unbounded;
with Ada.Text_IO;
with Differential.Compare;
with Differential.Transcript;

--  Lab-only pure deterministic report renderer.
--  One line per scenario in corpus order plus a summary line.
--  No timestamps, addresses, or run-varying data: rendering the
--  same input twice yields byte-identical output.

package Differential.Report is

   use Ada.Strings.Unbounded;

   type Named_Result is record
      Name   : Unbounded_String := Null_Unbounded_String;
      Result : Compare.Comparison_Result;
   end record;

   function Make_Result
     (Name   : String;
      Result : Compare.Comparison_Result) return Named_Result;

   function Scenario_Line (Item : Named_Result) return String;
   --  "MATCH <scenario>" or
   --  "DIVERGE <scenario> <first-divergence detail>".
   --  Detail comes from Compare.First_Detail and carries the
   --  oracle/candidate values at the first differing index.

   function Summary_Line
     (Total    : Natural;
      Matched  : Natural;
      Diverged : Natural) return String;
   --  "total=<n> match=<m> diverge=<d>" with no leading blanks.

   function Count_Matches
     (Items : Named_Result_Array) return Natural is abstract;
   --  Placeholder to catch accidental whole-file rewrite; not used.

end Differential.Report;
