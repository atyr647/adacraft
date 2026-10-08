with Interfaces;
with Adacraft.Protocol.Packets;

package body Adacraft.Protocol.Handshake_Exchange is

   function Rejected_Close
     (Reason : State.Rejection_Reason) return Outcome
   is
   begin
      return
        (Accepted        => False,
         Has_Transition  => False,
         Next_State      => State.Handshake,
         Client_Version  => 0,
         Close_Requested => True,
         Reason          => Reason);
   end Rejected_Close;

   function Handle
     (Current_State : State.Connection_State;
      Packet_Id     : Integer;
      Payload       : Octets) return Outcome
   is
      use type State.Connection_State;
      Decoded : Packets.Handshake;
      Event   : State.Packet_Event;
      Result  : State.Transition_Result;
      use type State.Result_Kind;
      use type Interfaces.Unsigned_32;
   begin
      if Current_State /= State.Handshake then
         return Rejected_Close (State.Packet_Not_Valid_In_State);
      end if;

      if Packet_Id /= 0 then
         return Rejected_Close (State.Packet_Not_Valid_In_State);
      end if;

      Decoded := Packets.Decode_Handshake (Payload);
      if Decoded.Status /= Ok then
         return Rejected_Close (State.Packet_Not_Valid_In_State);
      end if;

      if Decoded.Addr_Len > 255 then
         return Rejected_Close (State.Packet_Not_Valid_In_State);
      end if;

      if Decoded.Intent /= 1 and then Decoded.Intent /= 2 then
         return Rejected_Close (State.Invalid_Handshake_Intent);
      end if;

      Event :=
        (Direction => State.Serverbound,
         Id        => State.Packet_Id (Packet_Id),
         Intent    => State.Handshake_Intent (Decoded.Intent));

      Result := State.Transition (Current_State, Event);

      if Result.Kind /= State.Accepted_Transition then
         return Rejected_Close (Result.Reason);
      end if;

      return
        (Accepted        => True,
         Has_Transition  => True,
         Next_State      => Result.Next_State,
         Client_Version  => Integer (Decoded.Version),
         Close_Requested => False,
         Reason          => State.No_Rejection);
   end Handle;

end Adacraft.Protocol.Handshake_Exchange;
