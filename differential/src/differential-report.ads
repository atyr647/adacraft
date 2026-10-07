with Ada.Containers.Vectors;
with Ada.Strings.Unbounded;
with Differential.Compare;
with Differential.Obs;

--  Deterministic report rendering and outcome tally. No timestamps in the
--  body. Exit-code precedence is NOT decided here (see differential-main).
package Differential.Report is

   type Category is (Matched, Mismatched, Infrastructure);

   type Scenario_Result is record
      Id       : Ada.Strings.Unbounded.Unbounded_String;
      Cat      : Category := Matched;
      Detail   : Ada.Strings.Unbounded.Unbounded_String;
      Diffs    : Differential.Compare.Diff_Vectors.Vector;
      Unlisted : Differential.Obs.Field_Maps.Map;  --  path -> summary
   end record;

   package Result_Vectors is new Ada.Containers.Vectors
     (Positive, Scenario_Result);

   type Provenance is record
      Jar_Path          : Ada.Strings.Unbounded.Unbounded_String;
      Jar_Sha256        : Ada.Strings.Unbounded.Unbounded_String;
      Java_Version      : Ada.Strings.Unbounded.Unbounded_String;
      Observed_Protocol : Ada.Strings.Unbounded.Unbounded_String;
      Corpus_Id         : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   type Tally is record
      Matched        : Natural := 0;
      Mismatched     : Natural := 0;
      Infrastructure : Natural := 0;
   end record;

   function Tally_Of (Results : Result_Vectors.Vector) return Tally;

   function Image (C : Category) return String;

   --  Stable key order, compact, no timestamps.
   function Render_Json
     (Prov    : Provenance;
      Results : Result_Vectors.Vector) return String;

   --  Short human-readable summary.
   function Render_Summary
     (Results : Result_Vectors.Vector) return String;

end Differential.Report;
