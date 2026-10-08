with Differential.Transcript;

package Differential.Compare is

   use Differential.Transcript;

   type Verdict is (Match, Diverge);

   type Difference_Kind is
     (No_Difference,
      State_Difference,
      Direction_Difference,
      Packet_Id_Difference,
      Length_Difference,
      Outcome_Difference);

   type Comparison_Result is record
      Result           : Verdict := Match;
      First_Index      : Natural := 0;
      Outcome_Mismatch : Boolean := False;
      Kind             : Difference_Kind := No_Difference;
   end record;

   function Compare
     (Oracle    : Differential.Transcript.Transcript;
      Candidate : Differential.Transcript.Transcript) return Comparison_Result;

end Differential.Compare;
