with Ada.Strings.Bounded;
with Differential.Args;
with Differential.Transcript;

package Differential.Capture is

   package Name_Strings is new Ada.Strings.Bounded.Generic_Bounded_Length
     (Max => 64);

   Max_Scenarios : constant Positive := 16;

   type Scenario is record
      Name : Name_Strings.Bounded_String;
   end record;

   type Scenario_Array is array (1 .. Max_Scenarios) of Scenario;

   type Scenario_Result is record
      Name      : Name_Strings.Bounded_String;
      Oracle    : Transcript.Transcript;
      Candidate : Transcript.Transcript;
   end record;

   type Result_Array is array (1 .. Max_Scenarios) of Scenario_Result;

   procedure Empty_Provider
     (List  : out Scenario_Array;
      Count : out Natural);
   --  Corpus loader deferred; always returns Count = 0.

   function Capture_Scenario
     (S      : Scenario;
      Target : Args.Endpoint) return Transcript.Transcript;
   --  Connect failure propagates so the caller exits 2.

   procedure Run_All
     (Cfg     : Args.Config;
      Results : out Result_Array;
      Count   : out Natural);

end Differential.Capture;
