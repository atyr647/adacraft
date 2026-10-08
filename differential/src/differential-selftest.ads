--  Lab-only offline self-test suite. Opens no socket.
--  Owns Base_Result, Check and Run. Calls Compare, Transcript
--  and Report directly.

with Ada.Strings.Unbounded;
with Differential.Compare;

package Differential.Selftest is

   use Ada.Strings.Unbounded;

   type Base_Result is record
      Total       : Natural := 0;
      Failed      : Natural := 0;
      Failed_Name : Unbounded_String := Null_Unbounded_String;
   end record;

   procedure Check
     (R         : in out Base_Result;
      Name      : String;
      Condition : Boolean);
   --  Records one named check. First failure sticks in Failed_Name.

   function Verdict_Exit (V : Compare.Verdict) return Integer;
   --  C6 mapping: Match -> 0, Diverge -> 1.

   function Run return Integer;
   --  Runs >= 8 offline checks (Compare + Transcript + Report
   --  double-render + verdict mapping). Prints
   --  "selftest: PASS (<k> checks)" on success, else names the
   --  failed check. Returns 0 on success, 1 on failure.
   --  Opens no socket.

   function Check_Count (R : Base_Result) return Natural;

end Differential.Selftest;
