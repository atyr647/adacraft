with Ada.Text_IO;
with Adacraft.Protocol.State;
with Differential.Compare;
with Differential.Report;
with Differential.Transcript;

package body Differential.Selftest is

   use Ada.Strings.Unbounded;

   procedure Check
     (R         : in out Base_Result;
      Name      : String;
      Condition : Boolean)
   is
   begin
      R.Total := R.Total + 1;
      if not Condition and then R.Failed = 0 then
         R.Failed_Name := To_Unbounded_String (Name);
      end if;
      if not Condition then
         R.Failed := R.Failed + 1;
      end if;
   end Check;

   function Check_Count (R : Base_Result) return Natural is
   begin
      return R.Total;
   end Check_Count;

   function Verdict_Exit (V : Compare.Verdict) return Integer is
   begin
      if V = Compare.Match then
         return 0;
      end if;
      return 1;
   end Verdict_Exit;

   function Nat_Image (N : Natural) return String is
      Img : constant String := Natural'Image (N);
   begin
      return Img (Img'First + 1 .. Img'Last);
   end Nat_Image;

   procedure Fill
     (T       : in out Transcript.Transcript;
      Outcome : Transcript.Terminal_Outcome := Transcript.Completed)
   is
      use Transcript;
      use Adacraft.Protocol.State;
   begin
      T.Entries.Clear;
      Append (T, (State => Handshake, Direction => Serverbound,
                  Packet_Id => 0));
      Append (T, (State => Status, Direction => Clientbound,
                  Packet_Id => 1));
      Transcript.Set_Outcome (T, Outcome);
   end Fill;

   function Run return Integer is
      use Transcript;
      use Adacraft.Protocol.State;
      R  : Base_Result;
      O  : Transcript.Transcript;
      C  : Transcript.Transcript;
      CR : Compare.Comparison_Result;
   begin
      --  1: identical -> MATCH.
      Fill (O);
      Fill (C);
      CR := Compare.Compare (O, C);
      Check (R, "identical-match",
             CR.Outcome_Verdict = Compare.Match);

      --  2: differing id -> DIVERGE at index 1.
      Fill (O);
      Fill (C);
      C.Entries.Replace_Element
        (1, (State => Status, Direction => Clientbound, Packet_Id => 9));
      CR := Compare.Compare (O, C);
      Check (R, "diff-id-diverge",
             CR.Outcome_Verdict = Compare.Diverge
             and then CR.First_Index = 1);

      --  3: differing state -> DIVERGE at index 0.
      Fill (O);
      Fill (C);
      C.Entries.Replace_Element
        (0, (State => Login, Direction => Serverbound, Packet_Id => 0));
      CR := Compare.Compare (O, C);
      Check (R, "diff-state-diverge",
             CR.Outcome_Verdict = Compare.Diverge
             and then CR.First_Index = 0);

      --  4: differing direction -> DIVERGE at index 1.
      Fill (O);
      Fill (C);
      C.Entries.Replace_Element
        (1, (State => Status, Direction => Serverbound, Packet_Id => 1));
      CR := Compare.Compare (O, C);
      Check (R, "diff-direction-diverge",
             CR.Outcome_Verdict = Compare.Diverge
             and then CR.First_Index = 1);

      --  5: differing count -> DIVERGE at index 2.
      Fill (O);
      Fill (C);
      Append (C, (State => Play, Direction => Clientbound, Packet_Id => 2));
      CR := Compare.Compare (O, C);
      Check (R, "diff-count-diverge",
             CR.Outcome_Verdict = Compare.Diverge
             and then CR.First_Index = 2);

      --  6: differing outcome -> DIVERGE at index = entry count.
      Fill (O, Completed);
      Fill (C, Timeout);
      CR := Compare.Compare (O, C);
      Check (R, "diff-outcome-diverge",
             CR.Outcome_Verdict = Compare.Diverge
             and then CR.First_Index = Transcript.Length (O));

      --  7: report double-render identical.
      Fill (O);
      Fill (C);
      CR := Compare.Compare (O, C);
      declare
         Item : constant Report.Named_Result :=
           Report.Make_Result ("scn", CR);
         L1 : constant String := Report.Scenario_Line (Item);
         L2 : constant String := Report.Scenario_Line (Item);
         S1 : constant String := Report.Summary_Line (1, 1, 0);
         S2 : constant String := Report.Summary_Line (1, 1, 0);
      begin
         Check (R, "double-render-identical", L1 = L2 and then S1 = S2);
      end;

      --  8: verdict to exit mapping per C6.
      Check (R, "verdict-exit-mapping",
             Verdict_Exit (Compare.Match) = 0
             and then Verdict_Exit (Compare.Diverge) = 1);

      --  9: diverge detail carries oracle/candidate values.
      Fill (O);
      Fill (C);
      C.Entries.Replace_Element
        (0, (State => Login, Direction => Serverbound, Packet_Id => 7));
      CR := Compare.Compare (O, C);
      declare
         Item : constant Report.Named_Result :=
           Report.Make_Result ("scn", CR);
         Line : constant String := Report.Scenario_Line (Item);
      begin
         Check (R, "diverge-line-detail",
                Line'Length > 12
                and then Line (Line'First .. Line'First + 6) = "DIVERGE");
      end;

      if R.Failed = 0 then
         Ada.Text_IO.Put_Line ("selftest: PASS ("
           & Nat_Image (R.Total) & " checks)");
         return 0;
      else
         Ada.Text_IO.Put_Line ("selftest: FAIL "
           & To_String (R.Failed_Name));
         return 1;
      end if;
   end Run;

end Differential.Selftest;
