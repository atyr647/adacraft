with Ada.Command_Line;
with Ada.Containers;
with Ada.Directories;
with Ada.Exceptions;
with Ada.Strings.Unbounded;
with Ada.Text_IO;
with Differential.Compare;
with Differential.Corpus;
with Differential.Obs;
with Differential.Runner;
with Test_Fake_Server;

procedure Test_Runner is

   use Ada.Strings.Unbounded;
   use type Ada.Containers.Count_Type;
   use type Differential.Obs.Event_Kind;
   package FS renames Test_Fake_Server;
   package Corpus renames Differential.Corpus;

   type Result_Kind is (Pass, Diff, Err);

   Timeout_Ms : constant := 300;
   Failures   : Natural := 0;

   function Corpus_Dir return String is
   begin
      if Ada.Directories.Exists ("tests/test_corpus") then
         return "tests/test_corpus";
      end if;
      return "differential/tests/test_corpus";
   end Corpus_Dir;

   function Find (Name : String) return Corpus.Scenario is
      Sc   : Corpus.Scenario_Vectors.Vector;
      Errs : Corpus.Error_Vectors.Vector;
   begin
      Corpus.Load (Corpus_Dir, Sc, Errs);
      for S of Sc loop
         if To_String (S.Name) = Name then
            return S;
         end if;
      end loop;
      raise Program_Error with "scenario not found: " & Name;
   end Find;

   function Ch (N : Natural) return Character is (Character'Val (N));

   function Pkt (Id, Payload : Natural) return String is
     (Ch (2) & Ch (Id) & Ch (Payload));

   function Script (A : FS.Action) return FS.Action_Vectors.Vector is
      V : FS.Action_Vectors.Vector;
   begin
      V.Append (A);
      return V;
   end Script;

   function Script2 (A, B : FS.Action) return FS.Action_Vectors.Vector is
      V : FS.Action_Vectors.Vector;
   begin
      V.Append (A);
      V.Append (B);
      return V;
   end Script2;

   function Join (S : Differential.Compare.Sequence) return String is
      R : Unbounded_String;
   begin
      for O of S loop
         Append (R, Differential.Obs.To_String (O) & "|");
      end loop;
      return To_String (R);
   end Join;

   procedure Execute
     (Name : String; O, S : FS.Server; Res : out Result_Kind;
      Orc, Sub : out Differential.Compare.Sequence)
   is
      Sc : constant Corpus.Scenario := Find (Name);
   begin
      Res := Pass;
      Differential.Runner.Run
        ("127.0.0.1", FS.Port (O), Timeout_Ms, Sc, Orc);
      if Orc.Length = 1
        and then Orc.First_Element.Kind = Differential.Obs.Connect_Failed
      then
         Res := Err;
         return;
      end if;
      Differential.Runner.Run
        ("127.0.0.1", FS.Port (S), Timeout_Ms, Sc, Sub);
      if not Differential.Compare.Equal (Orc, Sub) then
         Res := Diff;
      end if;
   exception
      when Differential.Runner.Step_Encoding_Error =>
         Res := Err;
   end Execute;

   procedure Check (Test : String; Ok : Boolean) is
   begin
      if Ok then
         Ada.Text_IO.Put_Line ("ok   " & Test);
      else
         Ada.Text_IO.Put_Line ("FAIL " & Test);
         Failures := Failures + 1;
      end if;
   end Check;

   --  Runs one oracle/subject pair and checks the classification.
   procedure Pair
     (Test, Scen : String;
      Orc_Script, Sub_Script : FS.Action_Vectors.Vector;
      Expect : Result_Kind)
   is
      O, S : FS.Server;
      Res  : Result_Kind;
      Q, R : Differential.Compare.Sequence;
   begin
      FS.Start (O, Orc_Script);
      FS.Start (S, Sub_Script);
      Execute (Scen, O, S, Res, Q, R);
      FS.Stop (O);
      FS.Stop (S);
      Check (Test, Res = Expect);
   exception
      when E : others =>
         Ada.Text_IO.Put_Line
           ("exception in " & Test & ": " & Ada.Exceptions.Exception_Name (E));
         Failures := Failures + 1;
   end Pair;

   Req : constant String := "status-request";

begin
   --  T1 same sequence
   Pair ("T1 same-sequence PASS", Req,
         Script (FS.Send (Pkt (1, 16#AA#))),
         Script (FS.Send (Pkt (1, 16#AA#))), Pass);
   --  T2 payload differs only
   Pair ("T2 payload-differ PASS", Req,
         Script (FS.Send (Pkt (1, 16#AA#))),
         Script (FS.Send (Pkt (1, 16#BB#))), Pass);
   --  T3 packet id differs
   Pair ("T3 id-differ DIFF", Req,
         Script (FS.Send (Pkt (0, 1))),
         Script (FS.Send (Pkt (1, 1))), Diff);
   --  T4 early close
   Pair ("T4 early-close DIFF", Req,
         Script2 (FS.Send (Pkt (0, 1)), FS.Close_Now),
         Script (FS.Close_Now), Diff);
   --  T5 malformed (oversized length prefix)
   Pair ("T5 malformed DIFF", Req,
         Script (FS.Send (Pkt (0, 1))),
         Script (FS.Raw (Ch (255) & Ch (255) & Ch (255) & Ch (127))), Diff);
   --  T6 invalid in state
   Pair ("T6 invalid-in-state DIFF", Req,
         Script (FS.Send (Pkt (0, 1))),
         Script (FS.Send (Pkt (16#30#, 0))), Diff);
   --  T7 silent peer
   Pair ("T7 silent-timeout DIFF", Req,
         Script2 (FS.Send (Pkt (0, 1)), FS.Close_Now),
         Script (FS.Hold_Silent), Diff);
   --  T8 subject connect failure
   Pair ("T8 subject-connect-failure DIFF", Req,
         Script (FS.Send (Pkt (0, 1))),
         Script (FS.Refuse_All), Diff);

   --  T9 argument/corpus validation happens before any socket
   declare
      O, S : FS.Server;
      Sc   : Corpus.Scenario_Vectors.Vector;
      Errs : Corpus.Error_Vectors.Vector;
   begin
      FS.Start (O, Script (FS.Close_Now));
      FS.Start (S, Script (FS.Close_Now));
      Corpus.Load ("no/such/corpus/dir", Sc, Errs);
      delay 0.2;
      Check ("T9 invalid corpus rejected, no connections",
             Errs.Length > 0 and then FS.Accepts (O) = 0
             and then FS.Accepts (S) = 0);
      FS.Stop (O);
      FS.Stop (S);
   end;

   --  T10 determinism: two full runs, identical text
   declare
      Texts : array (1 .. 2) of Unbounded_String;
   begin
      for K in Texts'Range loop
         declare
            O, S : FS.Server;
            Res  : Result_Kind;
            Q, R : Differential.Compare.Sequence;
         begin
            FS.Start (O, Script2 (FS.Send (Pkt (0, 1)), FS.Close_Now));
            FS.Start (S, Script (FS.Send (Pkt (1, 2))));
            Execute (Req, O, S, Res, Q, R);
            Texts (K) := To_Unbounded_String
              (Result_Kind'Image (Res) & "#" & Join (Q) & "#" & Join (R)
               & "#" & Differential.Compare.Describe (Q, 1)
               & Natural'Image (Differential.Compare.First_Diff (Q, R)));
            FS.Stop (O);
            FS.Stop (S);
         end;
      end loop;
      Check ("T10 determinism", Texts (1) = Texts (2));
   end;

   --  T11 ERROR classification: oracle unreachable, unencodable step
   Pair ("T11a oracle-connect-failure ERROR", Req,
         Script (FS.Refuse_All),
         Script (FS.Send (Pkt (0, 1))), Err);
   Pair ("T11b unencodable-step ERROR", "unencodable-step",
         Script (FS.Send (Pkt (0, 1))),
         Script (FS.Send (Pkt (0, 1))), Err);

   --  T12 both roles on one fake
   declare
      F    : FS.Server;
      Res  : Result_Kind;
      Q, R : Differential.Compare.Sequence;
   begin
      FS.Start (F, Script (FS.Send (Pkt (1, 7))));
      Execute (Req, F, F, Res, Q, R);
      FS.Stop (F);
      Check ("T12 same fake both roles PASS", Res = Pass);
   end;

   if Failures > 0 then
      Ada.Text_IO.Put_Line (Natural'Image (Failures) & " failure(s)");
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
   else
      Ada.Text_IO.Put_Line ("all differential tests passed");
   end if;
end Test_Runner;
