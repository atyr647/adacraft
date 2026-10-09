with Adacraft.Protocol.State;
with Adacraft.Protocol.Packets;
with Interfaces;

package body Adacraft.Protocol.Handshake_Exchange with SPARK_Mode => Off is
   use Adacraft.Protocol;
   use type Interfaces.Unsigned_32;
   use type State.Connection_State;
   use type State.Result_Kind;
   use type State.Rejection_Reason;

   procedure Handle
     (Packet_Id : in     Natural;
      Payload   : in     Octets;
      Current   : in out State.Connection_State;
      Stored    : in out Connection_Data;
      Result    :    out Handle_Result)
   is
      Dec : Packets.Handshake;
      Ev  : State.Packet_Event;
      TR  : State.Transition_Result;
   begin
      if Current /= State.Handshake then
         Result := Rejected_No_Change;
         return;
      end if;
      if Packet_Id /= 0 then
         Result := Rejected_No_Change;
         return;
      end if;
      Dec := Packets.Decode_Handshake (Payload);
      if Dec.Status /= Ok then
         Result := Rejected_No_Change;
         return;
      end if;
      if Dec.Intent /= 1 and then Dec.Intent /= 2 and then Dec.Intent /= 3 then
         Result := Rejected_No_Change;
         return;
      end if;
      Ev := (Direction => State.Serverbound,
             Id        => State.Packet_Id (0),
             Intent    => State.Handshake_Intent (Dec.Intent));
      TR := State.Transition (Current, Ev);
      if TR.Kind /= State.Accepted_Transition then
         if TR.Reason = State.Invalid_Handshake_Intent then
            Result := Rejected_No_Change;
         else
            Result := Refused_By_Transition;
         end if;
         return;
      end if;
      Stored.Version := Integer (Dec.Version);
      Stored.Addr_Len := Dec.Addr_Len;
      if Dec.Addr_Len > 0 then
         Stored.Address (1 .. Dec.Addr_Len) :=
           Dec.Address (1 .. Dec.Addr_Len);
      end if;
      Stored.Port := Natural (Dec.Port);
      Stored.Have_Stored := True;
      Current := TR.Next_State;
      if TR.Next_State = State.Status then
         Result := Accepted_Status;
      elsif TR.Next_State = State.Login then
         Result := Accepted_Login;
      else
         Result := Refused_By_Transition;
      end if;
   end Handle;

   function Last_Protocol_Version (Stored : Connection_Data) return Integer is
   begin
      return Stored.Version;
   end Last_Protocol_Version;

   function Last_Server_Address (Stored : Connection_Data) return String is
   begin
      if Stored.Addr_Len = 0 then
         return "";
      end if;
      return Stored.Address (1 .. Stored.Addr_Len);
   end Last_Server_Address;

   function Last_Server_Port (Stored : Connection_Data) return Natural is
   begin
      return Stored.Port;
   end Last_Server_Port;

end Adacraft.Protocol.Handshake_Exchange;
