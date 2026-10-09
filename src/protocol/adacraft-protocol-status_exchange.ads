with Adacraft.Protocol.State;

package Adacraft.Protocol.Status_Exchange with SPARK_Mode => Off is

   type Handle_Result is (Responded, Pong_Ready_Close, Rejected_Close);

   type Session is record
      Request_Seen : Boolean := False;
   end record;

   procedure Reset (S : in out Session);

   procedure Handle
     (Packet_Id        : in     Natural;
      Payload          : in     Octets;
      Current          : in out State.Connection_State;
      Session_State    : in out Session;
      Result           :    out Handle_Result;
      Response_Id      :    out Natural;
      Response_Data    :    out Octets;
      Response_Len     :    out Natural;
      Close_Connection :    out Boolean);

end Adacraft.Protocol.Status_Exchange;
