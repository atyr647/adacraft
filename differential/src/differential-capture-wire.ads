--  Lab-only wire layer. Sole place with socket I/O and calls into
--  shipped framing units (#202/#203/#204/#208/#118). No local VarInt
--  or length reader; no D_Net.
with Adacraft.Protocol.State;
with Differential.Args;
with GNAT.Sockets;

package Differential.Capture.Wire is

   type Session is limited private;

   --  Connect to Target. Ok is False when unreachable (pre-run).
   procedure Open
     (Target : in Differential.Args.Endpoint;
      S      : in out Session;
      Ok     : out Boolean);

   procedure Close (S : in out Session);

   function Is_Open (S : Session) return Boolean;

   function Current_State (S : Session) return Adacraft.Protocol.State.Connection_State;

   --  Send one empty serverbound packet with current state.
   procedure Send_Serverbound
     (S         : in out Session;
      Packet_Id : in Adacraft.Protocol.State.Packet_Id;
      Ok        : out Boolean);

   --  Blocking single read with Timeout. Exactly one flag group holds:
   --  a decoded clientbound packet, Timed_Out, Peer_Closed, or Malformed.
   procedure Receive_One
     (S            : in out Session;
      Timeout      : in Duration;
      Present      : out Boolean;
      Timed_Out    : out Boolean;
      Peer_Closed  : out Boolean;
      Malformed    : out Boolean;
      Direction    : out Adacraft.Protocol.State.Packet_Direction;
      Packet_Id    : out Adacraft.Protocol.State.Packet_Id;
      State_Valid  : out Boolean);

private

   type Session is limited record
      Socket  : GNAT.Sockets.Socket_Type := GNAT.Sockets.No_Socket;
      Opened  : Boolean := False;
      State   : Adacraft.Protocol.State.Connection_State :=
        Adacraft.Protocol.State.Handshake;
   end record;

end Differential.Capture.Wire;
