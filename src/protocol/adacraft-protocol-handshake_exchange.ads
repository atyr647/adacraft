--  Single-state dispatch: connection state lives only in
--  Adacraft.Protocol.State.Connection_State; no duplicate
--  state type or To_State/From_State/Convert here.
with Adacraft.Protocol.State;

package Adacraft.Protocol.Handshake_Exchange with SPARK_Mode => Off is
   type Handle_Result is
     (Accepted_Status, Accepted_Login, Rejected_No_Change,
      Refused_By_Transition);

   type Connection_Data is record
      Version  : Integer := 0;
      Addr_Len : Natural := 0;
      Address  : String (1 .. 255) := (others => ' ');
      Port     : Natural := 0;
      Have_Stored : Boolean := False;
   end record;

   procedure Handle
     (Packet_Id : in     Natural;
      Payload   : in     Octets;
      Current   : in out State.Connection_State;
      Stored    : in out Connection_Data;
      Result    :    out Handle_Result);

   function Last_Protocol_Version (Stored : Connection_Data) return Integer;
   function Last_Server_Address (Stored : Connection_Data) return String;
   function Last_Server_Port (Stored : Connection_Data) return Natural;
end Adacraft.Protocol.Handshake_Exchange;
