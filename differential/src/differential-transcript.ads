--  Lab-only transcript foundation for the differential harness.
--  Types reuse Adacraft.Protocol.State and are never redeclared here.
--  No payload storage; ordered comparison happens in Differential.Compare.

with Ada.Containers.Vectors;
with Adacraft.Protocol.State;

package Differential.Transcript is
   pragma Elaborate_Body;

   --  How a single target run over one scenario terminated.
   --  Exactly one value applies per Target_Result.
   type Terminal_Outcome is
     (Completed,
      Peer_Closed,
      Protocol_Error,
      Driver_Error,
      Timed_Out);

   --  One observed packet: state at send/receive time plus direction
   --  and packet identifier. Payload bytes are never stored.
   type Transcript_Entry is record
      State     : Adacraft.Protocol.State.Connection_State;
      Direction : Adacraft.Protocol.State.Packet_Direction;
      Packet_Id : Adacraft.Protocol.State.Packet_Id;
   end record;

   package Transcript_Vectors is new Ada.Containers.Vectors
     (Index_Type   => Natural,
      Element_Type => Transcript_Entry);

   subtype Transcript is Transcript_Vectors.Vector;

   --  Full observation for one target on one scenario.
   type Target_Result is record
      Entries : Transcript;
      Outcome : Terminal_Outcome;
   end record;

end Differential.Transcript;
