with Adacraft.Protocol.State;

package body Differential.Compare is

   use Differential.Transcript;
   use type Adacraft.Protocol.State.Connection_State;
   use type Adacraft.Protocol.State.Packet_Id;

   function Compare
     (Oracle    : Differential.Transcript.Transcript;
      Candidate : Differential.Transcript.Transcript) return Comparison_Result
   is
      Oracle_Len   : constant Natural := Get_Length (Oracle);
      Cand_Len     : constant Natural := Get_Length (Candidate);
      Oracle_Out   : constant Terminal_Outcome := Get_Outcome (Oracle);
      Cand_Out     : constant Terminal_Outcome := Get_Outcome (Candidate);
      Outcomes_Differ : constant Boolean := Oracle_Out /= Cand_Out;
      Min_Len      : Natural;
   begin
      if Oracle_Len < Cand_Len then
         Min_Len := Oracle_Len;
      else
         Min_Len := Cand_Len;
      end if;

      for I in 1 .. Min_Len loop
         declare
            O : constant Transcript_Entry := Get_Entry (Oracle, I);
            C : constant Transcript_Entry := Get_Entry (Candidate, I);
         begin
            if O.State /= C.State then
               return
                 (Result           => Diverge,
                  First_Index      => I,
                  Outcome_Mismatch => Outcomes_Differ,
                  Kind             => State_Difference);
            elsif O.Dir /= C.Dir then
               return
                 (Result           => Diverge,
                  First_Index      => I,
                  Outcome_Mismatch => Outcomes_Differ,
                  Kind             => Direction_Difference);
            elsif O.Packet_ID /= C.Packet_ID then
               return
                 (Result           => Diverge,
                  First_Index      => I,
                  Outcome_Mismatch => Outcomes_Differ,
                  Kind             => Packet_Id_Difference);
            end if;
         end;
      end loop;

      if Oracle_Len /= Cand_Len then
         return
           (Result           => Diverge,
            First_Index      => Min_Len + 1,
            Outcome_Mismatch => Outcomes_Differ,
            Kind             => Length_Difference);
      end if;

      if Outcomes_Differ then
         return
           (Result           => Diverge,
            First_Index      => 0,
            Outcome_Mismatch => True,
            Kind             => Outcome_Difference);
      end if;

      return
        (Result           => Match,
         First_Index      => 0,
         Outcome_Mismatch => False,
         Kind             => No_Difference);
   end Compare;

end Differential.Compare;
