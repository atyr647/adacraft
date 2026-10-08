with Adacraft.Protocol.State;

package Adacraft.Protocol.Handshake_Exchange is

   type Outcome is record
      Accepted        : Boolean := False;
      Has_Transition  : Boolean := False;
      Next_State      : State.Connection_State := State.Handshake;
      Client_Version  : Integer := 0;
      Close_Requested : Boolean := False;
      Reason          : State.Rejection_Reason := State.No_Rejection;
   end record;

   function Handle
     (Current_State : State.Connection_State;
      Packet_Id     : Integer;
      Payload       : Octets) return Outcome;

end Adacraft.Protocol.Handshake_Exchange;
