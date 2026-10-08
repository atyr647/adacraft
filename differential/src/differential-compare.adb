package body Differential.Compare is
   function Compare
     (Left  : Differential.Transcript.Transcript;
      Right : Differential.Transcript.Transcript) return Verdict
   is
      use type Differential.Transcript.Entry_Vectors.Vector;
      use type Differential.Transcript.Terminal_Outcome;
      use type Differential.Transcript.Direction_T;
      use type Differential.Transcript.Transcript_Entry;
      use type Adacraft.Protocol.State.Connection_State;
      use type Adacraft.Protocol.State.Packet_Id;

      Left_Length  : constant Natural := Natural (Left.Entries.Length);
      Right_Length : constant Natural := Natural (Right.Entries.Length);
      Shared_Length : constant Natural :=
        Natural'Min (Left_Length, Right_Length);
   begin
      for Index in 1 .. Shared_Length loop
         declare
            Left_Entry  : constant Differential.Transcript.Transcript_Entry :=
              Left.Entries.Element (Positive (Index));
            Right_Entry : constant Differential.Transcript.Transcript_Entry :=
              Right.Entries.Element (Positive (Index));
         begin
            if Left_Entry.State /= Right_Entry.State then
               return
                 (Is_Match    => False,
                  Difference  => State_Difference,
                  Entry_Index => Index);
            elsif Left_Entry.Direction /= Right_Entry.Direction then
               return
                 (Is_Match    => False,
                  Difference  => Direction_Difference,
                  Entry_Index => Index);
            elsif Left_Entry.Packet_Id /= Right_Entry.Packet_Id then
               return
                 (Is_Match    => False,
                  Difference  => Packet_Id_Difference,
                  Entry_Index => Index);
            end if;
         end;
      end loop;

      if Left_Length /= Right_Length then
         return
           (Is_Match    => False,
            Difference  => Length_Difference,
            Entry_Index => Shared_Length + 1);
      elsif Left.Outcome /= Right.Outcome then
         return
           (Is_Match    => False,
            Difference  => Outcome_Difference,
            Entry_Index => 0);
      else
         return
           (Is_Match    => True,
            Difference  => No_Difference,
            Entry_Index => 0);
      end if;
   end Compare;
end Differential.Compare;
