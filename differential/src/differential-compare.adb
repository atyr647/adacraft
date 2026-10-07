package body Differential.Compare is

   use type Obs.Observation;
   use type Ada.Containers.Count_Type;

   function First_Diff (A, B : Sequence) return Natural is
      La : constant Natural := Natural (A.Length);
      Lb : constant Natural := Natural (B.Length);
      Common : constant Natural := Natural'Min (La, Lb);
   begin
      for I in 1 .. Common loop
         if A.Element (I) /= B.Element (I) then
            return I;
         end if;
      end loop;
      if La = Lb then
         return 0;
      end if;
      return Common + 1;
   end First_Diff;

   function Equal (A, B : Sequence) return Boolean
   is (First_Diff (A, B) = 0);

   function Describe (S : Sequence; Index : Positive) return String is
   begin
      if Index > Natural (S.Length) then
         return End_Marker;
      end if;
      return Obs.To_String (S.Element (Index));
   end Describe;

end Differential.Compare;
