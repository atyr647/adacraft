with Ada.Strings.Unbounded;
with Differential.Obs;
with Differential.Scenario;

--  The seam every adapter (oracle, AdaCraft harness) and test stub
--  implements.
package Differential.Target is

   --  How the run ended, independent of field comparison.
   type Run_Category is
     (Completed,        --  observation produced
      Timed_Out,        --  a bounded wait expired
      Failed,           --  target failed to produce an observation
      Infrastructure);  --  prerequisite/lifecycle failure

   type Run_Result is record
      Category    : Run_Category := Failed;
      Observation : Differential.Obs.Observation;
      Detail      : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   type Target is limited interface;

   function Run_Scenario
     (T        : in out Target;
      Scenario : Differential.Scenario.Projection;
      Timeout  : Duration) return Run_Result is abstract;

end Differential.Target;
