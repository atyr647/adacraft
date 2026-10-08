--  Lab-only offline self-test for the differential harness.

with Ada.Text_IO;
with Adacraft.Protocol.State;

package body Differential.Selftest is

   function Make_Entry
     (State : Adacraft.Protocol.State.Connection_State;
      Dir   : Adacraft.Protocol.State.Packet_Direction;
      Id    : Integer) return Transcript.Transcript_Entry
   is
   begin
      return
        (State     => State,
         Direction => Dir,
         Packet_Id => Adacraft.Protocol.State.Packet_Id (Id));
   end Make_Entry;

   function Base_Result return Transcript.Target_Result is
      use Adacraft.Protocol.State;
      Entries : Transcript.Transcript;
      Result  : Transcript.Target_Result;
   begin
      Transcript.Transcript_Vectors.Append
        (Entries, Make_Entry (Handshake, Serverbound, 0));
      Transcript.Transcript_Vectors.Append
        (Entries, Make_Entry (Status, Serverbound, 0));
      Result := (Entries => Entries, Outcome => Transcript.Completed);
      return Result;
   end Base_Result;

   function Check
     (Name      : String;
      Oracle    : Transcript.Target_Result;
      Candidate : Transcript.Target_Result;
      Expected  : Compare.Verdict) return Boolean
   is
      use type Compare.Verdict;
      Detail : constant Compare.Comparison_Result :=
        Compare.Compare (Oracle, Candidate);
   begin
      if Detail.Verdict = Expected then
         return True;
      else
         Ada.Text_IO.Put_Line ("selftest: FAIL " & Name);
         return False;
      end if;
   end Check;

   function Run return Integer is
      use Adacraft.Protocol.State;
      Passed : Natural := 0;
      Total  : Natural := 0;

      procedure Do_Check
        (Name      : String;
         Oracle    : Transcript.Target_Result;
         Candidate : Transcript.Target_Result;
         Expected  : Compare.Verdict)
      is
      begin
         Total := Total + 1;
         if Check (Name, Oracle, Candidate, Expected) then
            Passed := Passed + 1;
         end if;
      end Do_Check;

      Base      : Transcript.Target_Result := Base_Result;
      Other     : Transcript.Target_Result;
      Shorter   : Transcript.Target_Result;
      Longer    : Transcript.Target_Result;
      Entries   : Transcript.Transcript;
      Empty_Set : Transcript.Transcript;
   begin
      --  1. Identical transcripts match.
      Do_Check ("identical", Base, Base, Compare.MATCH);

      --  2. Same entries with different payloads still match:
      --  payloads are never stored, so a rebuilt equal transcript matches.
      Other := Base_Result;
      Do_Check ("same-entries-different-payloads", Base, Other, Compare.MATCH);

      --  3. Differing packet-ID diverges.
      Other := Base_Result;
      Transcript.Transcript_Vectors.Replace_Element
        (Other.Entries, 1, Make_Entry (Status, Serverbound, 1));
      Do_Check ("differing-id", Base, Other, Compare.DIVERGE);

      --  4. Differing direction diverges.
      Other := Base_Result;
      Transcript.Transcript_Vectors.Replace_Element
        (Other.Entries, 0, Make_Entry (Handshake, Clientbound, 0));
      Do_Check ("differing-direction", Base, Other, Compare.DIVERGE);

      --  5. Differing state diverges.
      Other := Base_Result;
      Transcript.Transcript_Vectors.Replace_Element
        (Other.Entries, 0, Make_Entry (Login, Serverbound, 0));
      Do_Check ("differing-state", Base, Other, Compare.DIVERGE);

      --  6. Differing length diverges (candidate shorter).
      Entries := Transcript.Transcript_Vectors.Copy (Base.Entries);
      Transcript.Transcript_Vectors.Delete_Last (Entries);
      Shorter := (Entries => Entries, Outcome => Transcript.Completed);
      Do_Check ("differing-length", Base, Shorter, Compare.DIVERGE);

      --  7. Differing length diverges (candidate longer).
      Entries := Transcript.Transcript_Vectors.Copy (Base.Entries);
      Transcript.Transcript_Vectors.Append
        (Entries, Make_Entry (Login, Serverbound, 0));
      Longer := (Entries => Entries, Outcome => Transcript.Completed);
      Do_Check ("differing-length-longer", Base, Longer, Compare.DIVERGE);

      --  8. Differing terminal outcome diverges.
      Other := Base_Result;
      Other.Outcome := Transcript.Peer_Closed;
      Do_Check ("differing-outcome", Base, Other, Compare.DIVERGE);

      --  9. Empty vs empty with same outcome matches.
      declare
         A : constant Transcript.Target_Result :=
           (Entries => Empty_Set, Outcome => Transcript.Completed);
         B : Transcript.Target_Result;
      begin
         B := (Entries => Empty_Set, Outcome => Transcript.Completed);
         Do_Check ("empty-identical", A, B, Compare.MATCH);
      end;

      if Passed = Total then
         Ada.Text_IO.Put_Line
           ("selftest: PASS (" & Natural'Image (Total) & " checks)");
         return 0;
      else
         Ada.Text_IO.Put_Line
           ("selftest: FAIL (" & Natural'Image (Passed) & " of"
            & Natural'Image (Total) & " checks passed)");
         return 1;
      end if;
   end Run;

end Differential.Selftest;
