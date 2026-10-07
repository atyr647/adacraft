with Ada.Containers.Vectors;
with Ada.Strings.Unbounded;
with Adacraft.Corpus;
with Adacraft.Protocol.State;

--  Thin adapter: projects Adacraft.Corpus scenarios (#119) into the
--  driver's action model. No corpus parsing is done here, and no scenario
--  fields or syntax are added.
package Differential.Scenario is

   package Corpus renames Adacraft.Corpus;
   package PS renames Adacraft.Protocol.State;

   --  Defaults for absent corpus data (documented, never invented data):
   --  * no packet id / state_after in a step: no expectation is recorded;
   --  * no final_state: no final-state expectation is recorded;
   --  * per-step wait: Default_Step_Timeout seconds (all waits bounded).
   Default_Step_Timeout : constant Duration := 5.0;

   --  Infrastructure_Failure maps to exit code 2 (A13).
   type Failure_Category is (No_Failure, Infrastructure_Failure);

   type Action is record
      Index           : Positive := 1;
      Dir             : Corpus.Direction := Corpus.Serverbound;
      Frame           : Corpus.Byte_Vectors.Vector;
      Expected        : Corpus.Outcome := Corpus.Rejected;
      Has_Packet_Id   : Boolean := False;
      Packet_Id       : Natural := 0;
      Has_State_After : Boolean := False;
      State_After     : PS.Connection_State := PS.Handshake;
      Timeout         : Duration := Default_Step_Timeout;
   end record;

   package Action_Vectors is new Ada.Containers.Vectors (Positive, Action);

   type Projection is record
      Id              : Ada.Strings.Unbounded.Unbounded_String;
      Cat             : Corpus.Category := Corpus.Handshake;
      Initial_State   : PS.Connection_State := PS.Handshake;
      Has_Final_State : Boolean := False;
      Final_State     : PS.Connection_State := PS.Handshake;
      Actions         : Action_Vectors.Vector;
      Failure         : Failure_Category := No_Failure;
      Reason          : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   package Projection_Vectors is new Ada.Containers.Vectors
     (Positive, Projection);

   function Is_Supported (S : Corpus.Scenario) return Boolean;

   function Project (S : Corpus.Scenario) return Projection;

   --  Loads Dir through Adacraft.Corpus.Loader and projects each scenario.
   --  Load_Failed is True when the corpus could not be read cleanly
   --  (infrastructure failure).
   procedure Load
     (Dir         : String;
      Projections : out Projection_Vectors.Vector;
      Load_Failed : out Boolean);

   function Exit_Code (F : Failure_Category) return Natural;

end Differential.Scenario;
