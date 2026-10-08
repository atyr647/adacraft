with Adacraft.Protocol.State;

package body Differential.Compare is

   function Default_Entry return Transcript.Transcript_Entry is
   begin
      return
        (State     => Adacraft.Protocol.State.Handshake,
         Direction => Adacraft.Protocol.State.Serverbound,
         Packet_Id => Adacraft.Protocol.State.Packet_Id (0));
   end Default_Entry;

   function Compare
     (Oracle    : Transcript.Target_Result;
      Candidate : Transcript.Target_Result) return Comparison_Result
   is
      use type Adacraft.Protocol.State.Connection_State;
      use type Adacraft.Protocol.State.Packet_Direction;
      use type Adacraft.Protocol.State.Packet_Id;
      use type Transcript.Terminal_Outcome;
      Oracle_Len    : constant Natural :=
        Natural (Transcript.Transcript_Vectors.Length (Oracle.Entries));
      Candidate_Len : constant Natural :=
        Natural (Transcript.Transcript_Vectors.Length (Candidate.Entries));
      Common_Len    : Natural;
   begin
      if Oracle_Len /= Candidate_Len then
         Common_Len := Natural'Min (Oracle_Len, Candidate_Len);
         if Common_Len > 0 then
            for I in 0 .. Common_Len - 1 loop
               declare
                  O : constant Transcript.Transcript_Entry :=
                    Transcript.Transcript_Vectors.Element (Oracle.Entries, I);
                  C : constant Transcript.Transcript_Entry :=
                    Transcript.Transcript_Vectors.Element (Candidate.Entries, I);
               begin
                  if O.State /= C.State
                    or O.Direction /= C.Direction
                    or O.Packet_Id /= C.Packet_Id
                  then
                     return
                       (Verdict          => DIVERGE,
                        Kind             => Entry_Mismatch,
                        First_Index      => I,
                        Oracle_Entry     => O,
                        Candidate_Entry  => C,
                        Outcome_Mismatch => False);
                  end if;
               end;
            end loop;
         end if;
         declare
            O_Entry : Transcript.Transcript_Entry := Default_Entry;
            C_Entry : Transcript.Transcript_Entry := Default_Entry;
         begin
            if Common_Len < Oracle_Len then
               O_Entry :=
                 Transcript.Transcript_Vectors.Element
                   (Oracle.Entries, Common_Len);
            end if;
            if Common_Len < Candidate_Len then
               C_Entry :=
                 Transcript.Transcript_Vectors.Element
                   (Candidate.Entries, Common_Len);
            end if;
            return
              (Verdict          => DIVERGE,
               Kind             => Length_Mismatch,
               First_Index      => Common_Len,
               Oracle_Entry     => O_Entry,
               Candidate_Entry  => C_Entry,
               Outcome_Mismatch => False);
         end;
      end if;

      if Oracle_Len > 0 then
         for I in 0 .. Oracle_Len - 1 loop
            declare
               O : constant Transcript.Transcript_Entry :=
                 Transcript.Transcript_Vectors.Element (Oracle.Entries, I);
               C : constant Transcript.Transcript_Entry :=
                 Transcript.Transcript_Vectors.Element (Candidate.Entries, I);
            begin
               if O.State /= C.State
                 or O.Direction /= C.Direction
                 or O.Packet_Id /= C.Packet_Id
               then
                  return
                    (Verdict          => DIVERGE,
                     Kind             => Entry_Mismatch,
                     First_Index      => I,
                     Oracle_Entry     => O,
                     Candidate_Entry  => C,
                     Outcome_Mismatch => False);
               end if;
            end;
         end loop;
      end if;

      if Oracle.Outcome /= Candidate.Outcome then
         return
           (Verdict          => DIVERGE,
            Kind             => Outcome_Difference,
            First_Index      => 0,
            Oracle_Entry     => Default_Entry,
            Candidate_Entry  => Default_Entry,
            Outcome_Mismatch => True);
      end if;

      return
        (Verdict          => MATCH,
         Kind             => No_Divergence,
         First_Index      => 0,
         Oracle_Entry     => Default_Entry,
         Candidate_Entry  => Default_Entry,
         Outcome_Mismatch => False);
   end Compare;

end Differential.Compare;
