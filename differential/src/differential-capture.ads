with Ada.Containers.Vectors;
with Adacraft.Protocol;
with Adacraft.Protocol.State;
with Differential.Transcript;

package Differential.Capture is
   type Scenario_Step is record
      Packet_Id : Adacraft.Protocol.State.Packet_Id := 0;
      Payload   : Adacraft.Protocol.Octets (1 .. 0);
      Direction : Differential.Transcript.Direction_T :=
        Differential.Transcript.Serverbound;
      Intent    : Adacraft.Protocol.State.Handshake_Intent := 0;
   end record;

   package Step_Vectors is new Ada.Containers.Vectors
     (Index_Type   => Positive,
      Element_Type => Scenario_Step);

   type Scenario is record
      Name  : String (1 .. 1) := " ";
      Steps : Step_Vectors.Vector;
   end record;

   Setup_Error : exception;

   procedure Run
     (S          : Scenario;
      Host       : String;
      Port       : Positive;
      Result     : out Differential.Transcript.Transcript);
end Differential.Capture;
