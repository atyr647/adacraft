with Differential.Obs;

package Differential.Compare is

   subtype Sequence is Obs.Observation_Vectors.Vector;

   End_Marker : constant String := "<end>";

   function Equal (A, B : Sequence) return Boolean;

   --  1-based index of the first difference; 0 when sequences are equal.
   --  A shorter sequence differs at its length + 1.
   function First_Diff (A, B : Sequence) return Natural;

   --  Text of the observation at Index, or "<end>" past the sequence end.
   function Describe (S : Sequence; Index : Positive) return String;

end Differential.Compare;
