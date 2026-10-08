with Differential.Transcript;

package body Differential.Compare is

   function Verdict_Image (V : Verdict) return String is
   begin
      case V is
         when Match =>
            return "MATCH";
         when Diverge =>
            return "DIVERGE";
      end case;
   end Verdict_Image;

   function Divergence_Kind_Image (K : Divergence_Kind) return String is
   begin
      case K is
         when No_Divergence =>
            return "no-divergence";
         when Entry_Mismatch =>
            return "entry-mismatch";
         when Length_Mismatch =>
            return "length-mismatch";
         when Outcome_Mismatch =>
            return "outcome-mismatch";
      end case;
   end Divergence_Kind_Image;

   function Oracle_Image (R : Comparison_Result) return String is
   begin
      return To_String (R.Oracle_Text);
   end Oracle_Image;

   function Candidate_Image (R : Comparison_Result) return String is
   begin
      return To_String (R.Candidate_Text);
   end Candidate_Image;

   function First_Detail (R : Comparison_Result) return String is
      Idx_Img : constant String := Natural'Image (R.First_Index);
      Idx : constant String := Idx_Img (Idx_Img'First + 1 .. Idx_Img'Last);
   begin
      if R.Outcome_Verdict = Match then
         return "match";
      end if;
      return
        "index=" & Idx
        & " oracle=" & To_String (R.Oracle_Text)
        & " candidate=" & To_String (R.Candidate_Text);
   end First_Detail;

   function Compare
     (Oracle    : Transcript.Transcript;
      Candidate : Transcript.Transcript) return Comparison_Result
   is
      use Transcript;
      LO  : constant Natural := Length (Oracle);
      LC  : constant Natural := Length (Candidate);
      Min : constant Natural := Natural'Min (LO, LC);
   begin
      for I in 0 .. Min loop
         exit when I = Min;
         declare
            O : constant Transcript_Entry := Element_At (Oracle, I);
            C : constant Transcript_Entry := Element_At (Candidate, I);
         begin
            if O.State /= C.State
              or else O.Direction /= C.Direction
              or else O.Packet_Id /= C.Packet_Id
            then
               return
                 (Outcome_Verdict => Diverge,
                  Kind            => Entry_Mismatch,
                  First_Index     => I,
                  Oracle_Text     =>
                    To_Unbounded_String (Transcript_Entry_Image (O)),
                  Candidate_Text  =>
                    To_Unbounded_String (Transcript_Entry_Image (C)));
            end if;
         end;
      end loop;

      if LO /= LC then
         declare
            O_Txt : Unbounded_String := To_Unbounded_String ("end");
            C_Txt : Unbounded_String := To_Unbounded_String ("end");
         begin
            if LO > Min then
               O_Txt := To_Unbounded_String
                 (Transcript_Entry_Image (Element_At (Oracle, Min)));
            end if;
            if LC > Min then
               C_Txt := To_Unbounded_String
                 (Transcript_Entry_Image (Element_At (Candidate, Min)));
            end if;
            return
              (Outcome_Verdict => Diverge,
               Kind            => Length_Mismatch,
               First_Index     => Min,
               Oracle_Text     => O_Txt,
               Candidate_Text  => C_Txt);
         end;
      end if;

      if Oracle.Outcome /= Candidate.Outcome then
         return
           (Outcome_Verdict => Diverge,
            Kind            => Outcome_Mismatch,
            First_Index     => LO,
            Oracle_Text     =>
              To_Unbounded_String (Outcome_Image (Oracle.Outcome)),
            Candidate_Text  =>
              To_Unbounded_String (Outcome_Image (Candidate.Outcome)));
      end if;

      return
        (Outcome_Verdict => Match,
         Kind            => No_Divergence,
         First_Index     => 0,
         Oracle_Text     => Null_Unbounded_String,
         Candidate_Text  => Null_Unbounded_String);
   end Compare;

end Differential.Compare;
