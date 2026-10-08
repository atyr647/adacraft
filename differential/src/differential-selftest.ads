with Differential.Transcript;

package Differential.Selftest is

   --  Offline selftest: in-memory Compare checks only, no sockets.
   --  Run_Selftest prints "selftest: PASS (N checks)" and returns 0,
   --  or names the failing check and returns 1.

   function Base_Result return Differential.Transcript.Transcript;

   procedure Check
     (Name      : String;
      Condition : Boolean;
      Passed    : in out Natural;
      Total     : in out Natural);

   function Run_Selftest return Integer;

end Differential.Selftest;
