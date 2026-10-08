--  Lab-only offline selftest for the differential driver.
--  Owns Base_Result/Check (nowhere else). Builds transcripts in memory,
--  exercises Compare/Report, opens no sockets.
package Differential.Selftest is

   type Base_Result is record
      Total  : Natural := 0;
      Passed : Natural := 0;
   end record;

   procedure Check
     (R         : in out Base_Result;
      Name      : in String;
      Condition : in Boolean);

   function Failed (R : Base_Result) return Natural;

   --  Run all selftest checks. Prints
   --    "selftest: PASS (<n> checks)" on success,
   --  or "selftest: FAIL ..." naming each failed check.
   --  Returns 0 on pass, 1 on failure. Opens no sockets.
   function Run return Integer;

end Differential.Selftest;
