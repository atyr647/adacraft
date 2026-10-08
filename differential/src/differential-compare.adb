--  Lab-only semantic comparison body. Payload-insensitive by construction:
--  transcripts never store payloads, so comparison is on
--  (state, direction, packet ID) plus the terminal outcome.
package body Differential.Compare is

   use Differential.Transcript;
   use type Adacraft.Protocol.State.Connection_State;
   use type Adacraft.Protocol.State.Packet_Direction;
   use type Adacraft.Protocol.State.Packet_Id;

   function Entries_Equal
     (Left  : Transcript_Entry;
      Right : Transcript_Entry) return Boolean
   is
   begin
      return Left.State = Right.State
        and then Left.Direction = Right.Direction
        and then Left.Packet_Id = Right.Packet_Id;
   end Entries_Equal;

   function Compare
     (Left  : Differential.Transcript.Transcript;
      Right : Differential.Transcript.Transcript) return Verdict
   is
      L_Len : constant Natural := Length (Left);
      R_Len : constant Natural := Length (Right);
      L_Out : constant Terminal_Outcome := Get_Outcome (Left);
      R_Out : constant Terminal_Outcome := Get_Outcome (Right);
      Result : Verdict;
   begin
      Result.Left_Len := L_Len;
      Result.Right_Len := R_Len;
      Result.Left_Out := L_Out;
      Result.Right_Out := R_Out;
      if L_Len /= R_Len then
         Result.Kind := Diverge;
         Result.Difference := Length_Mismatch;
         Result.Index := 0;
         return Result;
      end if;
      for I in 1 .. L_Len loop
         declare
            LE : constant Transcript_Entry := Element (Left, I);
            RE : constant Transcript_Entry := Element (Right, I);
         begin
            if not Entries_Equal (LE, RE) then
               Result.Kind := Diverge;
               Result.Difference := First_Diff_Index;
               Result.Index := I;
               Result.Left_Entry := LE;
               Result.Right_Entry := RE;
               return Result;
            end if;
         end;
      end loop;
      if L_Out /= R_Out then
         Result.Kind := Diverge;
         Result.Difference := Outcome_Mismatch;
         Result.Index := 0;
         return Result;
      end if;
      Result.Kind := Match;
      Result.Difference := No_Difference;
      Result.Index := 0;
      return Result;
   end Compare;

   function Is_Match (V : Verdict) return Boolean is
   begin
      return V.Kind = Match;
   end Is_Match;

   function Is_Match
     (Left  : Differential.Transcript.Transcript;
      Right : Differential.Transcript.Transcript) return Boolean
   is
   begin
      return Is_Match (Compare (Left, Right));
   end Is_Match;

end Differential.Compare;
