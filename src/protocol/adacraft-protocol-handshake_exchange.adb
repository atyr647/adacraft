with Interfaces;
with Adacraft.Protocol.Ids;
with Adacraft.Protocol.Packets;
with Adacraft.Protocol.State;

package body Adacraft.Protocol.Handshake_Exchange is
   use type Adacraft.Protocol.Status_Kind;
   use type Interfaces.Unsigned_32;
   use type State.Connection_State;
   use type State.Result_Kind;

   procedure Handle
     (Input          : Adacraft.Protocol.Octets;
      Current_State  : in out State.Connection_State;
      Client_Version : out Natural;
      Disposition    : out Disposition_Kind;
      Output         : in out Buffer.Writer)
   is
      Packet_Id : constant Natural :=
        Adacraft.Protocol.Ids.Protocol_Id
          (Adacraft.Protocol.Ids.Sb_Handshake_Intention);
   begin
      Client_Version := 0;
      Disposition := Silent_Close;
      Buffer.Reset (Output);

      if Current_State /= State.Handshake
        or else Input'Length < 1
        or else Natural (Input (Input'First)) /= Packet_Id
      then
         return;
      end if;

      declare
         Payload : constant Adacraft.Protocol.Octets :=
           Input (Input'First + 1 .. Input'Last);
         Handshake : constant Adacraft.Protocol.Packets.Handshake :=
           Adacraft.Protocol.Packets.Decode_Handshake (Payload);
      begin
         if Handshake.Status /= Adacraft.Protocol.Ok
           or else Handshake.Version > Interfaces.Unsigned_32 (Natural'Last)
         then
            return;
         end if;

         declare
            Event : constant State.Packet_Event :=
              (Direction => State.Serverbound,
               Id        => State.Packet_Id (Packet_Id),
               Intent    => State.Handshake_Intent (Handshake.Intent));
            Result : constant State.Transition_Result :=
              State.Transition (Current_State, Event);
         begin
            if Result.Kind /= State.Accepted_Transition then
               return;
            end if;

            Current_State := Result.Next_State;
            Client_Version := Natural (Handshake.Version);
            Disposition := Progress;
         end;
      end;
   end Handle;
end Adacraft.Protocol.Handshake_Exchange;
