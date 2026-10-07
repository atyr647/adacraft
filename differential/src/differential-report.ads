with Differential.Compare;

package Differential.Report is

   --  Single write point for the plain-text report (stdout).
   --  Only names, results, indices, observation strings and counts appear.

   procedure Pass (Name : String);

   procedure Diff (Name : String; Oracle, Subject : Compare.Sequence);

   procedure Error (Name : String; Reason : String);

   procedure Summary (Passed, Differed, Errored : Natural);

end Differential.Report;
