with Differential.Client;
with Differential.Obs;

--  Turns the client's per-step decoded packet log into observations.
--  No comparison logic; raw bytes, timing and socket boundaries are dropped.
package Differential.Extract is

   --  Send_Failed marks the step on which sending failed (Terminal).
   function Extract_Step
     (Log         : Differential.Client.Step_Log;
      Send_Failed : Boolean := False) return Differential.Obs.Step_Observation;

   function Extract
     (Output      : Differential.Client.Run_Output;
      Scenario_Id : String) return Differential.Obs.Observation;

end Differential.Extract;
