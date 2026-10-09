with Interfaces;
with Adacraft.Protocol.State;
with Adacraft.Protocol.Packets;

package body Adacraft.Protocol.Handshake_Exchange with SPARK_Mode => Off is
   use Adacraft.Protocol;
   use type Interfaces.Unsigned_32;
   use type State.Connection_State;
   use type State.Result_Kind;
   use type State.Rejection_Reason;

   Stored_Version : Integer := 0;
   Stored_Addr_Len : Natural := 0;
   Stored_Address : String (1 .. 255) := (others => ' ');
   Stored_Port : Natural := 0;
   Have_Stored : Boolean := False;

   procedure Handle
     (Packet_Id : in     Natural;
      Payload   : in     Octets;
      Current   : in out State.Connection_State;
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
      if Dec.Intent > Interfaces.Unsigned_32 (Integer'Last) then
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
      Stored_Version := Integer (Dec.Version);
      Stored_Addr_Len := Dec.Addr_Len;
      if Dec.Addr_Len > 0 then
         Stored_Address (1 .. Dec.Addr_Len) := Dec.Address (1 .. Dec.Addr_Len);
      end if;
      Stored_Port := Natural (Dec.Port);
      Have_Stored := True;
      Current := TR.Next_State;
      if TR.Next_State = State.Status then
         Result := Accepted_Status;
      elsif TR.Next_State = State.Login then
         Result := Accepted_Login;
      else
         Result := Refused_By_Transition;
      end if;
   end Handle;

   function Last_Protocol_Version return Integer is
   begin
      return Stored_Version;
   end Last_Protocol_Version;

   function Last_Server_Address return String is
   begin
      if Stored_Addr_Len = 0 then
         return "";
      end if;
      return Stored_Address (1 .. Stored_Addr_Len);
   end Last_Server_Address;

   function Last_Server_Port return Natural is
   begin
      return Stored_Port;
   end Last_Server_Port;

end Adacraft.Protocol.Handshake_Exchange;
