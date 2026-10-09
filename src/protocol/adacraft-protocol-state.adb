with Adacraft.Protocol.Ids;
with Adacraft.Protocol.State.Table;

package body Adacraft.Protocol.State
  with SPARK_Mode => On
is
   use type Ids.Packet_Name;

   function Is_Packet_Valid
     (State : Connection_State;
      Dir   : Packet_Direction;
      Id    : Packet_Id) return Boolean
   is (Table.Find (State, Dir, Id) /= 0);

   type Trigger is record
      Dir  : Packet_Direction;
      Name : Ids.Packet_Name;
      From : Connection_State;
      To   : Connection_State;
   end record;

   Triggers : constant array (1 .. 8) of Trigger :=
     ((Serverbound, Ids.Sb_Handshake_Intention, Handshake, Handshake),
      (Clientbound, Ids.Cb_Login_Login_Finished, Login, Login_Awaiting_Ack),
      (Serverbound, Ids.Sb_Login_Login_Acknowledged, Login_Awaiting_Ack,
       Configuration),
      (Clientbound, Ids.Cb_Configuration_Finish_Configuration,
       Configuration, Configuration_Awaiting_Ack),
      (Serverbound, Ids.Sb_Configuration_Finish_Configuration,
       Configuration_Awaiting_Ack, Play),
      (Clientbound, Ids.Cb_Play_Start_Configuration, Play,
       Play_Awaiting_Config_Ack),
      (Serverbound, Ids.Sb_Play_Configuration_Acknowledged,
       Play_Awaiting_Config_Ack, Configuration),
      (Serverbound, Ids.Sb_Handshake_Intention, Handshake, Handshake));

   function Parent_Of (S : Connection_State) return Parent_State is
     (case S is
         when Login_Awaiting_Ack         => Login,
         when Configuration_Awaiting_Ack => Configuration,
         when Play_Awaiting_Config_Ack   => Play,
         when Handshake                  => Handshake,
         when Status                     => Status,
         when Login                      => Login,
         when Configuration              => Configuration,
         when Play                       => Play);

   function Reject
     (Current : Connection_State; R : Rejection_Reason)
      return Transition_Result
   is (Kind => Rejected, Next_State => Current, Reason => R);

   Login_Start_Id : constant Packet_Id :=
     Packet_Id (Ids.Protocol_Id (Ids.Sb_Login_Hello));
   Login_Ack_Id : constant Packet_Id :=
     Packet_Id (Ids.Protocol_Id (Ids.Sb_Login_Login_Acknowledged));

   function Dispatch_Login
     (Current : Connection_State;
      Dir     : Packet_Direction;
      Id      : Packet_Id) return Login_Dispatch
   is
   begin
      --  Direction check first: LOGIN dispatch is serverbound only.
      if Dir /= Serverbound then
         return Dispatch_Reject;
      end if;
      --  Route serverbound LOGIN ids to login handlers with a
      --  direction + state check: Start only in LOGIN, Ack only in
      --  LOGIN_AWAITING_ACK.  Any LOGIN packet after the transition
      --  to CONFIGURATION (or in any other state) rejects.
      if Id = Login_Start_Id then
         if Current = Login then
            return Dispatch_Start;
         else
            return Dispatch_Reject;
         end if;
      end if;
      if Id = Login_Ack_Id then
         if Current = Login_Awaiting_Ack then
            return Dispatch_Acknowledged;
         else
            return Dispatch_Reject;
         end if;
      end if;
      --  Other serverbound LOGIN ids (cookie response, key, custom
      --  query answer) reject; STATUS/HANDSHAKE/CONFIGURATION
      --  behaviour is unchanged. Any LOGIN packet after the
      --  transition to CONFIGURATION also rejects via the state
      --  checks above.
      return Dispatch_Reject;
   end Dispatch_Login;

   function Login_Ack_Allowed
     (Current      : Connection_State;
      Success_Sent : Boolean) return Boolean
   is
   begin
      return Current = Login_Awaiting_Ack and then Success_Sent;
   end Login_Ack_Allowed;

   --  Is_Login_State is a pure expression function in the spec; no body
   --  needed. LOGIN send-once sequencing lives in Adacraft.Network.
   --  Send_Set_Compression guards on Is_Login_State (State = Login),
   --  Threshold >= 0, and not already sent.

   function Transition
     (Current : Connection_State;
      Event   : Packet_Event) return Transition_Result
   is
      Other : constant Packet_Direction :=
        (if Event.Direction = Serverbound then Clientbound else Serverbound);
   begin
      if not Is_Packet_Valid (Current, Event.Direction, Event.Id) then
         if not Table.Is_Known_Id (Event.Id) then
            return Reject (Current, Unknown_Packet_Id);
         elsif Is_Packet_Valid (Current, Other, Event.Id) then
            return Reject (Current, Wrong_Direction);
         else
            return Reject (Current, Packet_Not_Valid_In_State);
         end if;
      end if;

      for T of Triggers loop
         if T.Dir = Event.Direction
           and then Packet_Id (Ids.Protocol_Id (T.Name)) = Event.Id
           and then Parent_Of (T.From) = Parent_Of (Current)
         then
            if T.From /= Current then
               return Reject (Current, Invalid_Transition);
            elsif T.Name = Ids.Sb_Handshake_Intention then
               case Event.Intent is
                  when 1 =>
                     return (Accepted_Transition, Status, No_Rejection);
                  when 2 | 3 =>
                     return (Accepted_Transition, Login, No_Rejection);
                  when others =>
                     return Reject (Current, Invalid_Handshake_Intent);
               end case;
            else
               return (Accepted_Transition, T.To, No_Rejection);
            end if;
         end if;
      end loop;

      return (Accepted_No_Transition, Current, No_Rejection);
   end Transition;
end Adacraft.Protocol.State;
