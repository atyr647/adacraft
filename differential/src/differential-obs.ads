with Ada.Containers.Vectors;
with Adacraft.Protocol.State;

package Differential.Obs is

   type Event_Kind is
     (Packet_Obs, Connect_Failed, Closed_By_Peer, Receive_Timeout,
      Malformed, Invalid_In_State);

   type Malformed_Reason is
     (Oversized_Length, Overlong_Length, Truncated_Frame, Bad_Packet_Id);

   --  Payload bytes are never stored, so they cannot be compared.
   type Observation (Kind : Event_Kind := Connect_Failed) is record
      case Kind is
         when Packet_Obs =>
            State     : Adacraft.Protocol.State.Connection_State;
            Direction : Adacraft.Protocol.State.Packet_Direction;
            Id        : Adacraft.Protocol.State.Packet_Id;
         when Malformed =>
            Reason    : Malformed_Reason;
         when Invalid_In_State =>
            Bad_State : Adacraft.Protocol.State.Connection_State;
            Bad_Id    : Adacraft.Protocol.State.Packet_Id;
         when Connect_Failed | Closed_By_Peer | Receive_Timeout =>
            null;
      end case;
   end record;
   --  Predefined "=" compares kind and all stored components only.

   package Observation_Vectors is new Ada.Containers.Vectors
     (Positive, Observation);

   function To_String (O : Observation) return String;

end Differential.Obs;
