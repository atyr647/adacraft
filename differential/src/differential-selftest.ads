--  Lab-only offline self-test for the differential harness.
--  No network. Calls Differential.Compare and Differential.Transcript
--  directly.

with Differential.Compare;
with Differential.Transcript;

package Differential.Selftest is
   pragma Elaborate_Body;

   --  Canonical non-empty result all self-test cases derive from.
   function Base_Result return Transcript.Target_Result;

   --  Runs one named check: compares Oracle vs Candidate with
   --  Differential.Compare and requires Expected verdict.
   --  Returns True on success; on failure prints the check name
   --  and returns False.
   function Check
     (Name      : String;
      Oracle    : Transcript.Target_Result;
      Candidate : Transcript.Target_Result;
      Expected  : Compare.Verdict) return Boolean;

   --  Runs all checks, prints "selftest: PASS (n checks)" on success
   --  or names the failing check(s) on failure.
   --  Returns 0 when every check passes, 1 otherwise.
   function Run return Integer;

end Differential.Selftest;
