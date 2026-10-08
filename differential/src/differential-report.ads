with Ada.Containers.Vectors;
with Ada.Strings.Unbounded;
with Differential.Compare;

package Differential.Report is
   type Scenario_Result is record
      Name   : Ada.Strings.Unbounded.Unbounded_String;
      Verdict : Differential.Compare.Verdict;
   end record;

   package Scenario_Result_Vectors is new Ada.Containers.Vectors
     (Index_Type   => Positive,
      Element_Type => Scenario_Result);

   function Format
     (Scenarios : Scenario_Result_Vectors.Vector) return String;
end Differential.Report;
