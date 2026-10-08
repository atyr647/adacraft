with Ada.Text_IO;
with Adacraft.Protocol.State;
with Differential.Compare;
with Differential.Report;
with Differential.Transcript;

package body Differential.Selftest is

   use type Adacraft.Protocol.State.Packet_Id;
   use type Adacraft.Protocol.State.Connection_State;
   use type Differential.Transcript.Direction;
   use type Differential.Compare.Verdict;
   use type Differential.Compare.Difference_Kind;

   function Base_Result return Differential.Transcript.Transcript is
      T : Differential.Transcript.Transcript;
      E1 : constant Differential.Transcript.Transcript_Entry :=
        (State     => Adacraft.Protocol.State.Handshake,
         Dir       => Differential.Transcript.C_To_S,
         Packet_ID => 0);
      E2 : constant Differential.Transcript.Transcript_Entry :=
        (State     => Adacraft.Protocol.State.Status,
         Dir       => Differential.Transcript.S_To_C,
         Packet_ID => 1);
   begin
      Differential.Transcript.Clear (T);
      Differential.Transcript.Append (T, E1);
      Differential.Transcript.Append (T, E2);
      Differential.Transcript.Set_Outcome
        (T, Differential.Transcript.Completed);
      return T;
   end Base_Result;

   procedure Check
     (Name      : String;
      Condition : Boolean;
      Passed    : in out Natural;
      Total     : in out Natural)
   is
   begin
      Total := Total + 1;
      if Condition then
         Passed := Passed + 1;
      else
         Ada.Text_IO.Put_Line
           (Ada.Text_IO.Standard_Error, "selftest: FAIL " & Name);
      end if;
   end Check;

   function Image_Trim (Value : Natural) return String is
      Img : constant String := Natural'Image (Value);
   begin
      return Img (Img'First + 1 .. Img'Last);
   end Image_Trim;

   function Run_Selftest return Integer is
      Passed : Natural := 0;
      Total  : Natural := 0;
      Base   : Differential.Transcript.Transcript := Base_Result;
      Same   : Differential.Transcript.Transcript := Base_Result;
      Other  : Differential.Transcript.Transcript;
      R1     : Differential.Compare.Comparison_Result;
      R2     : Differential.Compare.Comparison_Result;
   begin
      --  identical -> MATCH
      R1 := Differential.Compare.Compare (Base, Same);
      Check ("identical-MATCH",
        R1.Result = Differential.Compare.Match, Passed, Total);

      --  differing packet-ID -> DIVERGE
      Other := Base_Result;
      declare
         E : Differential.Transcript.Transcript_Entry :=
           Differential.Transcript.Get_Entry (Other, 1);
      begin
         E.Packet_ID := E.Packet_ID + Adacraft.Protocol.State.Packet_Id (1);
         Other.Entries (1) := E;
      end;
      R1 := Differential.Compare.Compare (Base, Other);
      Check ("packet-id-DIVERGE",
        R1.Result = Differential.Compare.Diverge
          and then R1.First_Index = 1,
        Passed, Total);

      --  differing state -> DIVERGE
      Other := Base_Result;
      declare
         E : Differential.Transcript.Transcript_Entry :=
           Differential.Transcript.Get_Entry (Other, 2);
      begin
         E.State := Adacraft.Protocol.State.Play;
         Other.Entries (2) := E;
      end;
      R1 := Differential.Compare.Compare (Base, Other);
      Check ("state-DIVERGE",
        R1.Result = Differential.Compare.Diverge
          and then R1.First_Index = 2,
        Passed, Total);

      --  differing direction -> DIVERGE
      Other := Base_Result;
      declare
         E : Differential.Transcript.Transcript_Entry :=
           Differential.Transcript.Get_Entry (Other, 1);
      begin
         E.Dir := Differential.Transcript.S_To_C;
         Other.Entries (1) := E;
      end;
      R1 := Differential.Compare.Compare (Base, Other);
      Check ("direction-DIVERGE",
        R1.Result = Differential.Compare.Diverge
          and then R1.First_Index = 1,
        Passed, Total);

      --  differing length -> DIVERGE
      Other := Base_Result;
      declare
         E : constant Differential.Transcript.Transcript_Entry :=
           (State     => Adacraft.Protocol.State.Status,
            Dir       => Differential.Transcript.S_To_C,
            Packet_ID => 2);
      begin
         Differential.Transcript.Append (Other, E);
      end;
      R1 := Differential.Compare.Compare (Base, Other);
      Check ("length-DIVERGE",
        R1.Result = Differential.Compare.Diverge
          and then R1.Kind = Differential.Compare.Length_Difference,
        Passed, Total);

      --  differing outcome -> DIVERGE
      Other := Base_Result;
      Differential.Transcript.Set_Outcome
        (Other, Differential.Transcript.Timeout);
      R1 := Differential.Compare.Compare (Base, Other);
      Check ("outcome-DIVERGE",
        R1.Result = Differential.Compare.Diverge
          and then R1.Outcome_Mismatch,
        Passed, Total);

      --  double-render determinism
      R1 := Differential.Compare.Compare (Base, Other);
      R2 := Differential.Compare.Compare (Base, Other);
      declare
         Detail_1 : constant String :=
           Differential.Report.First_Diff_Detail
             (Base, Other, R1.First_Index, R1.Outcome_Mismatch);
         Detail_2 : constant String :=
           Differential.Report.First_Diff_Detail
             (Base, Other, R2.First_Index, R2.Outcome_Mismatch);
         Line_1 : constant String :=
           Differential.Report.Render
             ("case", R1.Result = Differential.Compare.Match, Detail_1);
         Line_2 : constant String :=
           Differential.Report.Render
             ("case", R2.Result = Differential.Compare.Match, Detail_2);
         Sum_1 : constant String :=
           Differential.Report.Render_Summary
             (Total => 2, Matched => 1, Diverged => 1);
         Sum_2 : constant String :=
           Differential.Report.Render_Summary
             (Total => 2, Matched => 1, Diverged => 1);
      begin
         Check ("double-render-DET", Line_1 = Line_2, Passed, Total);
         Check ("double-summary-DET", Sum_1 = Sum_2, Passed, Total);
      end;

      if Passed = Total then
         Ada.Text_IO.Put_Line
           ("selftest: PASS (" & Image_Trim (Total) & " checks)");
         return 0;
      else
         Ada.Text_IO.Put_Line
           (Ada.Text_IO.Standard_Error,
            "selftest: FAIL (" & Image_Trim (Passed)
            & "/" & Image_Trim (Total) & " passed)");
         return 1;
      end if;
   end Run_Selftest;

end Differential.Selftest;
