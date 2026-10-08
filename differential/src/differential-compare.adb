with Differential.Transcript;

package body Differential.Compare is

   function Compare
     (Expected : Differential.Transcript.Scenario_Result;
      Got      : Differential.Transcript.Scenario_Result) return Verdict
   is
      use type Differential.Outcome;
      use type Adacraft.Protocol.State.Connection_State;
      use type Adacraft.Protocol.State.Packet_Direction;
      use type Adacraft.Protocol.State.Packet_Id;
      Len_E : constant Natural := Natural (Expected.Entries.Count);
      Len_G : constant Natural := Natural (Got.Entries.Count);
      R     : Verdict;
   begin
      R.Expected_Length := Len_E;
      R.Got_Length := Len_G;
      R.Expected_Outcome := Expected.Outcome;
      R.Got_Outcome := Got.Outcome;

      if Len_E /= Len_G then
         R.Kind := Diverge_Length;
         R.Index := Natural'Min (Len_E, Len_G) + 1;
         if Len_E > 0 and then Len_G > 0 then
            null;
         end if;
         --  Provide neighbouring entries when both sides non-empty
         --  is not possible for length mismatch; leave default entries.
         return R;
      end if;

      for I in 1 .. Len_E loop
         declare
            E : constant Differential.Transcript.Entry :=
              Differential.Transcript.Get (Expected.Entries, I);
            G : constant Differential.Transcript.Entry :=
              Differential.Transcript.Get (Got.Entries, I);
         begin
            if E.State /= G.State
              or else E.Direction /= G.Direction
              or else E.Id /= G.Id
            then
               R.Kind := Diverge_Entry;
               R.Index := I;
               R.Expected_Entry := E;
               R.Got_Entry := G;
               return R;
            end if;
         end;
      end loop;

      if Expected.Outcome /= Got.Outcome then
         R.Kind := Diverge_Outcome;
         R.Index := 0;
         return R;
      end if;

      R.Kind := Match;
      R.Index := 0;
      return R;
   end Compare;

end Differential.Compare;
