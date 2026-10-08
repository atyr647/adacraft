--  Lab-only capture orchestration. Holds Read_Timeout 5.0s, Empty_Provider
--  only, uncompressed/unencrypted only. No socket I/O, no framing calls.
with Differential.Args;
with Differential.Transcript;

package Differential.Capture is

   Read_Timeout : constant Duration := 5.0;

   type Scenario_Kind is (Empty_Provider);

   function Scenario_Name (S : Scenario_Kind) return String;

   function Scenario_Count return Natural;

   function Scenario_At (Index : Positive) return Scenario_Kind;

   --  Run one scenario x one target to a Transcript.
   --  Pre_Run_Failed is True only when unreachable before any scenario
   --  bytes flow (caller exits 2). Mid-run loss becomes a terminal
   --  outcome in T instead.
   procedure Run_Scenario
     (Target         : in Differential.Args.Endpoint;
      Scenario       : in Scenario_Kind;
      T              : out Differential.Transcript.Transcript;
      Pre_Run_Failed : out Boolean);

end Differential.Capture;
