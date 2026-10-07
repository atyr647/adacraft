with Ada.Containers.Vectors;
with Ada.Strings.Unbounded;
with Differential.Obs;

--  Pure field-level semantic comparison (A6, A8, A16). Reports differences
--  only; outcome-category classification is done elsewhere. Inputs are
--  expected to be normalized already. Exact equality: no retries, no
--  thresholds, no tolerance.
package Differential.Compare is

   type Diff_Kind is
     (State_Differs,    --  protocol state after the step differs
      Outcome_Differs,  --  step outcome differs (incl. disconnected)
      Value_Differs,    --  compared field present on both, values differ
      Field_Missing,    --  in the oracle, absent from AdaCraft
      Field_Extra,      --  in AdaCraft, absent from the oracle
      Step_Missing,     --  oracle has the step, AdaCraft does not
      Step_Extra);      --  AdaCraft has a step the oracle does not

   Absent : constant String := "<absent>";

   type Diff_Entry is record
      Step           : Positive := 1;
      Kind           : Diff_Kind := Value_Differs;
      Path           : Ada.Strings.Unbounded.Unbounded_String;
      Oracle_Value   : Ada.Strings.Unbounded.Unbounded_String;
      Adacraft_Value : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   package Diff_Vectors is new Ada.Containers.Vectors
     (Positive, Diff_Entry);

   type Result is record
      Pass  : Boolean := True;
      Diffs : Diff_Vectors.Vector;
   end record;

   function Compare
     (Oracle   : Differential.Obs.Observation;
      Adacraft : Differential.Obs.Observation) return Result;

   function Image (K : Diff_Kind) return String;

end Differential.Compare;
