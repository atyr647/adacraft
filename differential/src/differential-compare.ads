with Differential.Transcript;

package Differential.Compare is
   type Difference_Kind is
     (No_Difference,
      State_Difference,
      Direction_Difference,
      Packet_Id_Difference,
      Length_Difference,
      Outcome_Difference);

   type Verdict is record
      Is_Match          : Boolean := False;
      Difference        : Difference_Kind := No_Difference;
      Entry_Index       : Natural := 0;
   end record;

   function Compare
     (Left  : Differential.Transcript.Transcript;
      Right : Differential.Transcript.Transcript) return Verdict;
end Differential.Compare;
