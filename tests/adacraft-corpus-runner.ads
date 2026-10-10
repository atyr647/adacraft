with Ada.Strings.Unbounded;
with Adacraft.Protocol.Handshake_Exchange;
with Adacraft.Protocol.State;
with Adacraft.Protocol.Status_Exchange;

--  Test-only replay glue over the existing protocol modules.
--  Dispatch-only API: per-scenario session mirrors the live
--  connection path in Adacraft.Network (Stored for
--  Handshake_Exchange.Handle, Sess reset via Status_Exchange.Reset
--  and passed as Session_State to Status_Exchange.Handle).
package Adacraft.Corpus.Runner is

   type Dispatch_Session is record
      Proto_State : Adacraft.Protocol.State.Connection_State :=
        Adacraft.Protocol.State.Handshake;
      Stored : Adacraft.Protocol.Handshake_Exchange.Connection_Data;
      Sess   : Adacraft.Protocol.Status_Exchange.Session;
      Pending : Byte_Vectors.Vector;
      Closing : Boolean := False;
   end record;

   procedure Init_Dispatch (D : out Dispatch_Session);

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
