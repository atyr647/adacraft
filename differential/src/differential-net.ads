with Ada.Streams;
with GNAT.Sockets;
with Adacraft.Protocol.Frame;
with Differential.Obs;

package Differential.Net is

   Max_Frame : constant := Adacraft.Protocol.Frame.Max_Frame_Body_Length;

   type Connection is limited private;

   procedure Connect
     (Conn       : out Connection;
      Host       : String;
      Port       : Natural;
      Timeout_Ms : Natural;
      Ok         : out Boolean);
   --  Never raises. On Ok = False the connection is unusable.

   function Send
     (Conn : Connection; Data : Ada.Streams.Stream_Element_Array)
      return Boolean;
   --  Sends every byte; False on any failure.

   type Receive_Kind is (Frame_Received, Closed, Timed_Out, Bad_Frame);

   type Receive_Result (Kind : Receive_Kind := Closed) is record
      case Kind is
         when Frame_Received =>
            Packet_Id : Natural;
         when Bad_Frame =>
            Reason : Obs.Malformed_Reason;
         when Closed | Timed_Out =>
            null;
      end case;
   end record;

   procedure Receive_Frame
     (Conn       : in out Connection;
      Timeout_Ms : Natural;
      Result     : out Receive_Result);
   --  Never raises. The payload is dropped; only the packet ID is returned.

   procedure Close (Conn : in out Connection);

private

   type Decoder_Access is access Adacraft.Protocol.Frame.Decoder_Type;

   Pending_Size : constant := 4096;

   type Connection is limited record
      Sock      : GNAT.Sockets.Socket_Type := GNAT.Sockets.No_Socket;
      Open      : Boolean := False;
      Decoder   : Decoder_Access := null;
      Pending   : Ada.Streams.Stream_Element_Array (1 .. Pending_Size);
      Pos       : Ada.Streams.Stream_Element_Offset := 1;
      Last      : Ada.Streams.Stream_Element_Offset := 0;
      In_Prefix : Boolean := True;
      Pfx_Count : Natural := 0;
      Failed    : Boolean := False;
      Fail_Why  : Obs.Malformed_Reason := Obs.Oversized_Length;
   end record;

end Differential.Net;
