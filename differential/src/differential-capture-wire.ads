--  Lab-only socket + framing adapter for the differential harness.
--  Socket + framing only: GNAT.Sockets plus Frame Encoder #202,
--  VarInt #208, Ingress #204, Frame Decoder #203, State Machine #118.
--  No orchestration / transcript logic beyond the I/O primitives.

with GNAT.Sockets;
with Adacraft.Ingress;
with Adacraft.Protocol;
with Adacraft.Protocol.State;

package Differential.Capture.Wire is
   pragma Elaborate_Body;

   Max_Body : constant := Adacraft.Protocol.Max_Packet_Length;

   type Receive_Status is (Ok, No_Data, Peer_Closed, Framing_Error);

   type Connection is limited private;

   procedure Connect
     (C    : in out Connection;
      Host : in     String;
      Port : in     Positive);

   procedure Close (C : in out Connection);

   function Is_Open (C : Connection) return Boolean;

   function Current_State
     (C : Connection) return Adacraft.Protocol.State.Connection_State;

   procedure Send_Packet
     (C       : in out Connection;
      Id      : in     Adacraft.Protocol.State.Packet_Id;
      Payload : in     Adacraft.Protocol.Octets);

   procedure Receive_Packet
     (C      : in out Connection;
      Id     :    out Adacraft.Protocol.State.Packet_Id;
      Status :    out Receive_Status);

private

   type Connection is limited record
      Sock          : GNAT.Sockets.Socket_Type;
      Open          : Boolean := False;
      State         : Adacraft.Protocol.State.Connection_State :=
        Adacraft.Protocol.State.Handshake;
      Ingress_Conn  : Adacraft.Ingress.Connection_Type;
      Ingress_Ready : Boolean := False;
   end record;

end Differential.Capture.Wire;
