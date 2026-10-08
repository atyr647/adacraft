--  Lab-only scenario capture logic (parent of Capture.Wire).
--  Per scenario/target: connect as client, send serverbound packets,
--  read clientbound until terminal, append one Transcript_Entry per
--  packet sent/received and advance the shipped #118 state machine.
--  Per-target failure is recorded as that target's outcome and does
--  not abort the whole run. No payload is recorded.

with Ada.Containers.Vectors;
with Ada.Strings.Unbounded;
with Adacraft.Protocol.State;
with Differential.Transcript;

package Differential.Capture is

   use Ada.Strings.Unbounded;

   type Target_Info is record
      Host : Unbounded_String := Null_Unbounded_String;
      Port : Natural := 0;
   end record;

   function Make_Target (Host : String; Port : Natural) return Target_Info;

   --  One serverbound packet to send: packet id plus handshake intent
   --  (intent is only consulted for the handshake intention packet).
   type Serverbound_Item is record
      Packet_Id : Natural := 0;
      Intent    : Integer := 0;
   end record;

   package Item_Vectors is new Ada.Containers.Vectors
     (Index_Type   => Natural,
      Element_Type => Serverbound_Item);

   type Scenario is record
      Name  : Unbounded_String := Null_Unbounded_String;
      Items : Item_Vectors.Vector;
   end record;

   function Scenario_Name (S : Scenario) return String;

   package Scenario_Vectors is new Ada.Containers.Vectors
     (Index_Type   => Natural,
      Element_Type => Scenario);

   subtype Scenario_List is Scenario_Vectors.Vector;

   function Empty_Provider return Scenario_List;
   --  Corpus provider stub (Q1 known gap): yields 0 scenarios.

   procedure Capture_For_Target
     (Host     : String;
      Port     : Natural;
      Item     : Scenario;
      Result   : out Transcript.Transcript;
      Initial  : Adacraft.Protocol.State.Connection_State :=
        Adacraft.Protocol.State.Handshake);
   --  Captures one transcript for one target/scenario. Never raises;
   --  transport or protocol failure is recorded in Result.Outcome.

end Differential.Capture;
