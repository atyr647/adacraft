--  Harness-only AdaCraft loopback target: single-connection listener on
--  127.0.0.1 using the #117 frame decoder and the #118 state machine.
--  No world, no gameplay, no persistence, no compression/encryption.
package Differential.Target.Adacraft is

   type Adacraft_Target is limited new Differential.Target.Target
     with null record;

   overriding function Run_Scenario
     (T        : in out Adacraft_Target;
      Scenario : Differential.Scenario.Projection;
      Timeout  : Duration) return Run_Result;

end Differential.Target.Adacraft;
