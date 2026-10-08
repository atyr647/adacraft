with Ada.Streams;
with GNAT.Sockets;
with Adacraft.Protocol;

package Differential.Capture.Wire is
   Read_Timeout : constant Duration := 5.0;

   type Connection is limited private;

   procedure Connect
     (Target : in out Connection;
      Host   : String;
      Port   : Positive);

   procedure Close (Target : in out Connection);

   procedure Send_Packet
     (Target   : in out Connection;
      Packet_Id : Adacraft.Protocol.Packet_Id;
      Payload   : Adacraft.Protocol.Octets);

   procedure Receive_Packet
     (Target    : in out Connection;
      Packet_Id : out Adacraft.Protocol.Packet_Id);

private
   type Connection is limited record
      Socket : GNAT.Sockets.Socket_Type;
      Open   : Boolean := False;
   end record;
end Differential.Capture.Wire;
