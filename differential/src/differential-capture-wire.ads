with Ada.Streams;
with GNAT.Sockets;
with Adacraft.Protocol.Frame;
with Differential.Transcript;

package Differential.Capture.Wire is

   --  Socket I/O plus shipped framing calls.
   --  Outgoing via Frame Encoder (#202), incoming via Frame Decoder (#203)
   --  and Ingress framing (#204), VarInts via (#208).
   --  No own length-VarInt reader, no packet-ID parse, no D_Net.

   Read_Timeout : constant Duration := 2.0;

   type Wire_Connection is limited private;

   procedure Open
     (C       : in out Wire_Connection;
      Host    : in String;
      Port    : in Natural;
      Outcome : out Differential.Transcript.Terminal_Outcome);
   --  Connect to Host:Port. On failure Outcome is Connect_Failed and
   --  the connection must not be used except for Close.
   --  On success Outcome is Completed.

   function Is_Open (C : Wire_Connection) return Boolean;

   procedure Send_Packet
     (C         : in out Wire_Connection;
      Packet_Id : in Natural;
      Payload   : in Ada.Streams.Stream_Element_Array;
      Outcome   : out Differential.Transcript.Terminal_Outcome);
   --  Frame Packet_Id || Payload via #202 and send it.
   --  Outcome is Completed, Peer_Closed, or Protocol_Error.

   procedure Receive_Frame
     (C          : in out Wire_Connection;
      Frame_Data : out Ada.Streams.Stream_Element_Array;
      Last       : out Ada.Streams.Stream_Element_Offset;
      Got        : out Boolean;
      Outcome    : out Differential.Transcript.Terminal_Outcome);
   --  Wait up to Read_Timeout for one frame body via #203 + #204.
   --  Got True means Frame_Data (Frame_Data'First .. Last) holds the body.
   --  Outcome is Completed (Got True), Timeout, Peer_Closed,
   --  or Protocol_Error on decode/framing rejection.

   procedure Close (C : in out Wire_Connection);

private

   type Wire_Connection is limited record
      Sock    : GNAT.Sockets.Socket_Type := GNAT.Sockets.No_Socket;
      Decoder : Adacraft.Protocol.Frame.Decoder_Type;
      Opened  : Boolean := False;
   end record;

end Differential.Capture.Wire;
