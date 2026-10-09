with Ada.Strings.Unbounded;
with Adacraft.Protocol.Login;
with Adacraft.Protocol.State;

--  Test-only replay glue over the existing protocol modules.
package Adacraft.Corpus.Runner is

   --  Per-scenario LOGIN context: holds the pending serverbound
   --  output frame (Login Success or Login Disconnect) produced by
   --  the previous step, plus closed/active flags. Clientbound
   --  expectation steps assert the exact pending bytes.
   type Login_Ctx is record
      Has_Pending    : Boolean := False;
      Pending_Output : Byte_Vectors.Vector;
      Closed         : Boolean := False;
      Active         : Boolean := False;
      Session        : Adacraft.Protocol.Login.Login_Session;
   end record;

   type Filter is record
      Has_Id       : Boolean := False;
      Id           : Unbounded_String;
      Has_Category : Boolean := False;
      Cat          : Category := Handshake;
   end record;

   type Category_Counts is array (Category) of Natural;

   type Run_Summary is record
      Total  : Natural := 0;
      Passed : Natural := 0;
      Failed : Natural := 0;
      Per    : Category_Counts := (others => 0);
   end record;

   --  Replays one scenario in a fresh context. Failure is empty on success,
   --  otherwise "step=.. expected=.. actual=.. detail=..".
   procedure Replay (S : Scenario; Failure : out Unbounded_String);

   --  Prints failure records and the summary to standard output.
   procedure Run_All
     (Scenarios : Scenario_Vectors.Vector;
      F         : Filter;
      Summary   : out Run_Summary);

end Adacraft.Corpus.Runner;
