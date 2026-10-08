--  Lab-only semantic comparison for the differential driver.
--  MATCH iff entry sequences are equal elementwise on
--  (state, direction, packet ID) and terminal outcomes are equal.
with Adacraft.Protocol.State;
with Differential.Transcript;

package Differential.Compare is

   use Differential.Transcript;
   use type Adacraft.Protocol.State.Connection_State;
   use type Adacraft.Protocol.State.Packet_Direction;
   use type Adacraft.Protocol.State.Packet_Id;

   type Verdict_Kind is (Match, Diverge);

   type Difference_Kind is
     (No_Difference,
      First_Diff_Index,
      Length_Mismatch,
      Outcome_Mismatch);

   type Verdict is record
      Kind        : Verdict_Kind := Match;
      Difference  : Difference_Kind := No_Difference;
      Index       : Natural := 0;
      Left_Len    : Natural := 0;
      Right_Len   : Natural := 0;
      Left_Out    : Terminal_Outcome := Completed;
      Right_Out   : Terminal_Outcome := Completed;
      Left_Entry  : Transcript_Entry :=
        (State     => Adacraft.Protocol.State.Handshake,
         Direction => Adacraft.Protocol.State.Serverbound,
         Packet_Id => 0);
      Right_Entry : Transcript_Entry :=
        (State     => Adacraft.Protocol.State.Handshake,
         Direction => Adacraft.Protocol.State.Serverbound,
         Packet_Id => 0);
   end record;

   function Entries_Equal
     (Left  : Transcript_Entry;
      Right : Transcript_Entry) return Boolean;

   function Compare
     (Left  : Differential.Transcript.Transcript;
      Right : Differential.Transcript.Transcript) return Verdict;

   function Is_Match (V : Verdict) return Boolean;

   function Is_Match
     (Left  : Differential.Transcript.Transcript;
      Right : Differential.Transcript.Transcript) return Boolean;

end Differential.Compare;
