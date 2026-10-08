with GNAT.Sockets;
with Adacraft.Protocol.Frame;
with Adacraft.Protocol.State;
with Differential.Args;
with Differential.Transcript;

package Differential.Capture.Wire is

   Read_Timeout_Secs : constant Duration := 2.0;

   type Session is limited private;

   procedure Connect
     (S      : in out Session;
      Target : Args.Endpoint);
   --  Propagates GNAT.Sockets.Socket_Error on failure.

   procedure Send_Packet
     (S         : in out Session;
      Packet_Id : Natural;
      T         : in out Transcript.Transcript);

   function Recv_Packet
     (S : in out Session;
      T : in out Transcript.Transcript) return Boolean;
   --  False when a terminal outcome was recorded.

   procedure Close (S : in out Session);

private

   type Session is limited record
      Sock      : GNAT.Sockets.Socket_Type;
      Connected : Boolean := False;
      State     : Adacraft.Protocol.State.Connection_State :=
        Adacraft.Protocol.State.Handshake;
      Decoder   : Adacraft.Protocol.Frame.Decoder_Type;
      Has_Sock  : Boolean := False;
   end record;

end Differential.Capture.Wire;
