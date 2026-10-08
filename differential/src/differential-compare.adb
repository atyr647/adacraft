with Differential.Transcript;
with Adacraft.Protocol.State;

package body Differential.Compare is

   use type Differential.Transcript.Direction_T;
   use type Differential.Transcript.Terminal_Outcome;
   use type Adacraft.Protocol.State.Connection_State;

   function Entries_Equal
     (A : Differential.Transcript.Transcript;
      B : Differential.Transcript.Transcript) return Boolean
   is
      use Differential.Transcript;
   begin
      if Length (A) /= Length (B) then
         return False;
      end if;
      for I in 1 .. Length (A) loop
         declare
            EA : constant Transcript_Entry := Get (A, I);
            EB : constant Transcript_Entry := Get (B, I);
         begin
            if EA.State /= EB.State
              or else EA.Dir /= EB.Dir
              or else EA.Packet_Id /= EB.Packet_Id
            then
               return False;
            end if;
         end;
      end loop;
      return True;
   end Entries_Equal;

   function Compare
     (A : Differential.Transcript.Transcript;
      B : Differential.Transcript.Transcript) return Verdict
   is
      use Differential.Transcript;
   begin
      if Length (A) /= Length (B) then
         return Diverge;
      end if;
      if not Entries_Equal (A, B) then
         return Diverge;
      end if;
      if Get_Outcome (A) /= Get_Outcome (B) then
         return Diverge;
      end if;
      return Match;
   end Compare;

   function First_Difference
     (A : Differential.Transcript.Transcript;
      B : Differential.Transcript.Transcript) return Natural
   is
      use Differential.Transcript;
      LA : constant Natural := Length (A);
      LB : constant Natural := Length (B);
      M  : Natural := LA;
   begin
      if LB < M then
         M := LB;
      end if;
      for I in 1 .. M loop
         declare
            EA : constant Transcript_Entry := Get (A, I);
            EB : constant Transcript_Entry := Get (B, I);
         begin
            if EA.State /= EB.State
              or else EA.Dir /= EB.Dir
              or else EA.Packet_Id /= EB.Packet_Id
            then
               return I;
            end if;
         end;
      end loop;
      if LA /= LB then
         return M + 1;
      end if;
      if Get_Outcome (A) /= Get_Outcome (B) then
         return LA + 1;
      end if;
      return 0;
   end First_Difference;

end Differential.Compare;
