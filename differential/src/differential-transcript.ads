with Ada.Containers.Vectors;
with Adacraft.Protocol.State;

package Differential.Transcript is
   type Direction_T is (Serverbound, Clientbound);

   type Terminal_Outcome is
     (Completed, Closed_By_Peer, Decode_Error, Timeout);

   type Transcript_Entry is record
      State     : Adacraft.Protocol.State.Connection_State;
      Direction : Direction_T;
      Packet_Id : Adacraft.Protocol.State.Packet_Id;
   end record;

   package Entry_Vectors is new Ada.Containers.Vectors
     (Index_Type   => Positive,
      Element_Type => Transcript_Entry);

   type Transcript is record
      Entries : Entry_Vectors.Vector;
      Outcome : Terminal_Outcome := Completed;
   end record;
end Differential.Transcript;
