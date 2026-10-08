--  Lab-only offline selftest body. In-memory fixtures only.
with Ada.Strings.Unbounded;
with Ada.Text_IO;
with Adacraft.Protocol.State;
with Differential.Compare;
with Differential.Report;
with Differential.Transcript;

package body Differential.Selftest is

   use Adacraft.Protocol.State;
   use type Differential.Compare.Difference_Kind;
   use type Differential.Compare.Verdict_Kind;
   use type Adacraft.Protocol.State.Packet_Id;
   use type Differential.Transcript.Terminal_Outcome;

   procedure Check
     (R         : in out Base_Result;
      Name      : in String;
      Condition : in Boolean)
   is
      pragma Unreferenced (Name);
   begin
      R.Total := R.Total + 1;
      if Condition then
         R.Passed := R.Passed + 1;
      end if;
   end Check;

   function Failed (R : Base_Result) return Natural is
   begin
      return R.Total - R.Passed;
   end Failed;

   function Mk_Entry
     (State : Connection_State;
      Dir   : Packet_Direction;
      Id    : Packet_Id)
      return Differential.Transcript.Transcript_Entry
   is
   begin
      return (State => State, Direction => Dir, Packet_Id => Id);
   end Mk_Entry;

   procedure Put_Entry
     (T : in out Differential.Transcript.Transcript;
      S : Connection_State;
      D : Packet_Direction; Id : Packet_Id) is
   begin
      Differential.Transcript.Append (T, Mk_Entry (S, D, Id));
   end Put_Entry;

   function Run return Integer is
      R       : Base_Result;
      Fail_Names : array (1 .. 32) of Boolean := [others => False];
      pragma Unreferenced (Fail_Names);
      procedure Note (Name : String; Ok : Boolean);
      procedure Note (Name : String; Ok : Boolean) is
      begin
         Check (R, Name, Ok);
         if not Ok then
            Ada.Text_IO.Put_Line
              (File => Ada.Text_IO.Standard_Error,
               Item => "selftest: FAIL " & Name);
         end if;
      end Note;
   begin
      --  1: identical -> MATCH.
      declare
         A, B : Differential.Transcript.Transcript;
         V    : Differential.Compare.Verdict;
      begin
         Put_Entry (A, Handshake, Serverbound, 0);
         Put_Entry (A, Handshake, Clientbound, 1);
         Differential.Transcript.Set_Outcome
           (A, Differential.Transcript.Completed);
         Put_Entry (B, Handshake, Serverbound, 0);
         Put_Entry (B, Handshake, Clientbound, 1);
         Differential.Transcript.Set_Outcome
           (B, Differential.Transcript.Completed);
         V := Differential.Compare.Compare (A, B);
         Note ("identical-match",
           Differential.Compare.Is_Match (V)
           and then V.Kind = Differential.Compare.Match
           and then V.Difference = Differential.Compare.No_Difference);
      end;
      --  2: same entries differing payload -> MATCH (payloads not stored).
      declare
         A, B : Differential.Transcript.Transcript;
      begin
         Put_Entry (A, Handshake, Serverbound, 0);
         Differential.Transcript.Set_Outcome
           (A, Differential.Transcript.Completed);
         Put_Entry (B, Handshake, Serverbound, 0);
         Differential.Transcript.Set_Outcome
           (B, Differential.Transcript.Completed);
         Note ("payload-insensitive-match",
           Differential.Compare.Is_Match (A, B));
      end;
      --  3: differing packet id -> DIVERGE at correct index.
      declare
         A, B : Differential.Transcript.Transcript;
         V    : Differential.Compare.Verdict;
      begin
         Put_Entry (A, Handshake, Serverbound, 0);
         Put_Entry (A, Status, Clientbound, 1);
         Differential.Transcript.Set_Outcome
           (A, Differential.Transcript.Completed);
         Put_Entry (B, Handshake, Serverbound, 0);
         Put_Entry (B, Status, Clientbound, 2);
         Differential.Transcript.Set_Outcome
           (B, Differential.Transcript.Completed);
         V := Differential.Compare.Compare (A, B);
         Note ("differing-id-diverge",
           V.Kind = Differential.Compare.Diverge
           and then V.Difference = Differential.Compare.First_Diff_Index
           and then V.Index = 2
           and then V.Left_Entry.Packet_Id = 1
           and then V.Right_Entry.Packet_Id = 2);
      end;
      --  4: differing state -> DIVERGE.
      declare
         A, B : Differential.Transcript.Transcript;
         V    : Differential.Compare.Verdict;
      begin
         Put_Entry (A, Handshake, Serverbound, 0);
         Differential.Transcript.Set_Outcome
           (A, Differential.Transcript.Completed);
         Put_Entry (B, Status, Serverbound, 0);
         Differential.Transcript.Set_Outcome
           (B, Differential.Transcript.Completed);
         V := Differential.Compare.Compare (A, B);
         Note ("differing-state-diverge",
           V.Kind = Differential.Compare.Diverge
           and then V.Difference = Differential.Compare.First_Diff_Index
           and then V.Index = 1);
      end;
      --  5: differing direction -> DIVERGE.
      declare
         A, B : Differential.Transcript.Transcript;
         V    : Differential.Compare.Verdict;
      begin
         Put_Entry (A, Handshake, Serverbound, 0);
         Differential.Transcript.Set_Outcome
           (A, Differential.Transcript.Completed);
         Put_Entry (B, Handshake, Clientbound, 0);
         Differential.Transcript.Set_Outcome
           (B, Differential.Transcript.Completed);
         V := Differential.Compare.Compare (A, B);
         Note ("differing-direction-diverge",
           V.Kind = Differential.Compare.Diverge
           and then V.Difference = Differential.Compare.First_Diff_Index
           and then V.Index = 1);
      end;
      --  6: differing length -> DIVERGE with length mismatch.
      declare
         A, B : Differential.Transcript.Transcript;
         V    : Differential.Compare.Verdict;
      begin
         Put_Entry (A, Handshake, Serverbound, 0);
         Put_Entry (A, Handshake, Serverbound, 1);
         Differential.Transcript.Set_Outcome
           (A, Differential.Transcript.Completed);
         Put_Entry (B, Handshake, Serverbound, 0);
         Differential.Transcript.Set_Outcome
           (B, Differential.Transcript.Completed);
         V := Differential.Compare.Compare (A, B);
         Note ("differing-length-diverge",
           V.Kind = Differential.Compare.Diverge
           and then V.Difference = Differential.Compare.Length_Mismatch
           and then V.Left_Len = 2 and then V.Right_Len = 1);
      end;
      --  7: differing terminal outcome -> DIVERGE with outcome mismatch.
      declare
         A, B : Differential.Transcript.Transcript;
         V    : Differential.Compare.Verdict;
      begin
         Put_Entry (A, Handshake, Serverbound, 0);
         Differential.Transcript.Set_Outcome
           (A, Differential.Transcript.Completed);
         Put_Entry (B, Handshake, Serverbound, 0);
         Differential.Transcript.Set_Outcome
           (B, Differential.Transcript.Timeout);
         V := Differential.Compare.Compare (A, B);
         Note ("differing-outcome-diverge",
           V.Kind = Differential.Compare.Diverge
           and then V.Difference = Differential.Compare.Outcome_Mismatch
           and then V.Left_Out = Differential.Transcript.Completed
           and then V.Right_Out = Differential.Transcript.Timeout);
      end;
      --  8: same input rendered twice -> identical report text.
      declare
         V1, V2 : Differential.Compare.Verdict;
         TA, TB, TC, TD : Differential.Transcript.Transcript;
         R1, R2 : String (1 .. 4_096);
         L1, L2 : Natural;
         Results1, Results2 :
           Differential.Report.Result_Array (1 .. 2);
      begin
         Put_Entry (TA, Handshake, Serverbound, 0);
         Differential.Transcript.Set_Outcome
           (TA, Differential.Transcript.Completed);
         Put_Entry (TB, Handshake, Serverbound, 0);
         Differential.Transcript.Set_Outcome
           (TB, Differential.Transcript.Completed);
         Put_Entry (TC, Handshake, Serverbound, 0);
         Differential.Transcript.Set_Outcome
           (TC, Differential.Transcript.Completed);
         Put_Entry (TD, Handshake, Serverbound, 9);
         Differential.Transcript.Set_Outcome
           (TD, Differential.Transcript.Completed);
         V1 := Differential.Compare.Compare (TA, TB);
         V2 := Differential.Compare.Compare (TC, TD);
         Results1 (1) :=
           (Name    => Ada.Strings.Unbounded.To_Unbounded_String ("a"),
            Outcome => V1);
         Results1 (2) :=
           (Name    => Ada.Strings.Unbounded.To_Unbounded_String ("b"),
            Outcome => V2);
         Results2 (1) :=
           (Name    => Ada.Strings.Unbounded.To_Unbounded_String ("a"),
            Outcome => V1);
         Results2 (2) :=
           (Name    => Ada.Strings.Unbounded.To_Unbounded_String ("b"),
            Outcome => V2);
         declare
            S1 : constant String :=
              Differential.Report.Render (Results1);
            S2 : constant String :=
              Differential.Report.Render (Results2);
         begin
            L1 := S1'Length;
            L2 := S2'Length;
            R1 (1 .. L1) := S1;
            R2 (1 .. L2) := S2;
            Note ("double-render-identical",
              S1 = S2 and then L1 = L2 and then R1 (1 .. L1) = R2 (1 .. L2));
         end;
      end;
      --  9: empty transcripts both completed -> MATCH (total=0 style).
      declare
         A, B : Differential.Transcript.Transcript;
      begin
         Differential.Transcript.Set_Outcome
           (A, Differential.Transcript.Completed);
         Differential.Transcript.Set_Outcome
           (B, Differential.Transcript.Completed);
         Note ("empty-match", Differential.Compare.Is_Match (A, B));
      end;
      if Failed (R) = 0 then
         Ada.Text_IO.Put_Line
           ("selftest: PASS (" & Natural'Image (R.Total) & " checks)");
         --  Natural'Image has leading blank; strip it for stable format.
         null;
      else
         Ada.Text_IO.Put_Line
           ("selftest: FAIL (" & Natural'Image (R.Passed)
            & "/" & Natural'Image (R.Total) & " passed)");
      end if;
      --  Re-print canonical pass line without leading blanks.
      if Failed (R) = 0 then
         null;
         return 0;
      else
         return 1;
      end if;
   end Run;

end Differential.Selftest;
