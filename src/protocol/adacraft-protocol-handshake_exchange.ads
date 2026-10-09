with Adacraft.Protocol.State;

package Adacraft.Protocol.Handshake_Exchange with SPARK_Mode => Off is
   type Handle_Result is
     (Accepted_Status, Accepted_Login, Rejected_No_Change,
      Refused_By_Transition);

   procedure Handle
     (Packet_Id : in     Natural;
      Payload   : in     Octets;
      Current   : in out State.Connection_State;
      Result    :    out Handle_Result);

   function Last_Protocol_Version return Integer;
   function Last_Server_Address return String;
   function Last_Server_Port return Natural;
end Adacraft.Protocol.Handshake_Exchange;
