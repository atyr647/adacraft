with Ada.Command_Line;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;
with Ada.Text_IO;
with Differential.Compare;
with Differential.Report;

--  Offline report tests: determinism and tally.
procedure Test_Diff_Report is
   package R renames Differential.Report;
   package SU renames Ada.Strings.Unbounded;
   use type R.Tally;

   Failures : Natural := 0;

   procedure Check (Cond : Boolean; Name : String) is
   begin
      if not Cond then
         Ada.Text_IO.Put_Line ("FAIL " & Name);
         Failures := Failures + 1;
      end if;
   end Check;

   function Has (S, Sub : String) return Boolean is
     (Ada.Strings.Fixed.Index (S, Sub) > 0);

   Results : R.Result_Vectors.Vector;
   Prov    : R.Provenance;
   One     : R.Scenario_Result;
   Two     : R.Scenario_Result;
   Three   : R.Scenario_Result;
   Four    : R.Scenario_Result;
begin
   One.Id := SU.To_Unbounded_String ("status-request");
   One.Unlisted.Include ("status.favicon", "ignored:string:30");

   Two.Id := SU.To_Unbounded_String ("login-rejected");
   Two.Cat := R.Mismatched;
   Two.Diffs.Append
     ((Step           => 1,
       Kind           => Differential.Compare.Value_Differs,
       Path           => SU.To_Unbounded_String ("status.players.max"),
       Oracle_Value   => SU.To_Unbounded_String ("20"),
       Adacraft_Value => SU.To_Unbounded_String ("21")));

   Three.Id := SU.To_Unbounded_String ("oracle-timeout");
   Three.Cat := R.Infrastructure;
   Three.Detail := SU.To_Unbounded_String ("ready ""timeout""");

   Four.Id := SU.To_Unbounded_String ("status-ping");

   Results.Append (One);
   Results.Append (Two);
   Results.Append (Three);
   Results.Append (Four);

   Prov.Jar_Path := SU.To_Unbounded_String ("/x/server.jar");
   Prov.Jar_Sha256 := SU.To_Unbounded_String ("abc123");
   Prov.Java_Version := SU.To_Unbounded_String ("25.0.1");
   Prov.Observed_Protocol := SU.To_Unbounded_String ("777");
   Prov.Corpus_Id := SU.To_Unbounded_String ("phase1");

   declare
      A : constant String := R.Render_Json (Prov, Results);
      B : constant String := R.Render_Json (Prov, Results);
   begin
      Check (A = B, "byte-identical");
      Check (Has (A, """matched"":2"), "tally matched in json");
      Check (Has (A, """mismatched"":1"), "tally mismatched in json");
      Check (Has (A, """infrastructure"":1"), "tally infra in json");
      Check (Has (A, """jar_sha256"":""abc123"""), "provenance");
      Check (Has (A, """schema_version"":1"), "schema version");
      Check (Has (A, """normalization_version"":1"), "norm version");
      Check (Has (A, """ignore_list_version"":1"), "ignore version");
      Check (Has (A, "ignored:string:30"), "ignored summary");
      Check (Has (A, "ready \""timeout\"""), "escaping");
      Check (not Has (A, "timestamp"), "no timestamps");
   end;

   Check (R.Tally_Of (Results) = (Matched => 2, Mismatched => 1,
                                  Infrastructure => 1), "tally");
   Check (R.Tally_Of (R.Result_Vectors.Empty_Vector)
          = (Matched => 0, Mismatched => 0, Infrastructure => 0),
          "empty tally");
   Check (Has (R.Render_Summary (Results), "matched=2 mismatched=1"),
          "summary");
   Check (R.Render_Summary (Results) = R.Render_Summary (Results),
          "summary deterministic");

   if Failures = 0 then
      Ada.Text_IO.Put_Line ("test_diff_report: ok");
   else
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
   end if;
end Test_Diff_Report;
