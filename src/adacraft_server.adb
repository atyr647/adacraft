with Ada.Command_Line;
with Ada.Streams;
with Ada.Text_IO;
with GNAT.Sockets;
with Adacraft.Network;
with Adacraft.Protocol.State;
with Adacraft.Protocol.Handshake_Exchange;
with Adacraft.Protocol.Status_Exchange;

procedure Adacraft_Server is
   Port : GNAT.Sockets.Port_Type := 25565;

   procedure Send_Reply
     (Socket : GNAT.Sockets.Socket_Type;
      Data   : Adacraft.Protocol.Octets)
   is
      use type Ada.Streams.Stream_Element_Offset;
      Msg  : Ada.Streams.Stream_Element_Array
        (1 .. Ada.Streams.Stream_Element_Offset (Data'Length));
      Sent : Ada.Streams.Stream_Element_Offset;
      Idx  : Natural := 0;
   begin
      for B of Data loop
         Idx := Idx + 1;
         Msg (Ada.Streams.Stream_Element_Offset (Idx)) :=
           Ada.Streams.Stream_Element (B);
      end loop;
      GNAT.Sockets.Send_Socket (Socket, Msg, Sent);
   end Send_Reply;

   procedure Close_Silently (Socket : GNAT.Sockets.Socket_Type) is
   begin
      GNAT.Sockets.Close_Socket (Socket);
   exception
      when others =>
         null;
   end Close_Silently;

   procedure Dispatch_Handshake
     (Socket         : GNAT.Sockets.Socket_Type;
      Current        : in out Adacraft.Protocol.State.Connection_State;
      Packet_Id      : Integer;
      Payload        : Adacraft.Protocol.Octets;
      Client_Version : out Integer;
      Close_Now      : out Boolean)
   is
      use type Adacraft.Protocol.State.Connection_State;
      H_Outcome : Adacraft.Protocol.Handshake_Exchange.Outcome :=
        Adacraft.Protocol.Handshake_Exchange.Handle
          (Current, Packet_Id, Payload);
   begin
      Client_Version := H_Outcome.Client_Version;
      Close_Now := H_Outcome.Close_Requested or else not H_Outcome.Accepted;
      if H_Outcome.Accepted and then H_Outcome.Has_Transition then
         Current := H_Outcome.Next_State;
      end if;
      if Close_Now then
         Close_Silently (Socket);
      end if;
   end Dispatch_Handshake;

   procedure Dispatch_Status
     (Socket      : GNAT.Sockets.Socket_Type;
      Current     : in out Adacraft.Protocol.State.Connection_State;
      Packet_Id   : Integer;
      Payload     : Adacraft.Protocol.Octets;
      Config      : Adacraft.Protocol.Status_Exchange.Status_Config;
      Status_Sent : in out Boolean;
      Close_Now   : out Boolean)
   is
      S_Outcome : Adacraft.Protocol.Status_Exchange.Outcome;
   begin
      Adacraft.Protocol.Status_Exchange.Handle
        (Current, Packet_Id, Payload, Config, Status_Sent, S_Outcome);
      if S_Outcome.Has_Reply and then S_Outcome.Reply_Length > 0 then
         Send_Reply
           (Socket,
            S_Outcome.Reply_Data (1 .. S_Outcome.Reply_Length));
      end if;
      Close_Now := S_Outcome.Close_Requested or else not S_Outcome.Accepted;
      if Close_Now then
         Close_Silently (Socket);
      end if;
   end Dispatch_Status;

   procedure Dispatch_Packet
     (Socket         : GNAT.Sockets.Socket_Type;
      Current        : in out Adacraft.Protocol.State.Connection_State;
      Packet_Id      : Integer;
      Payload        : Adacraft.Protocol.Octets;
      Config         : Adacraft.Protocol.Status_Exchange.Status_Config;
      Status_Sent    : in out Boolean;
      Client_Version : out Integer;
      Close_Now      : out Boolean)
   is
      use type Adacraft.Protocol.State.Connection_State;
   begin
      if Current = Adacraft.Protocol.State.Handshake then
         Dispatch_Handshake
           (Socket, Current, Packet_Id, Payload, Client_Version, Close_Now);
      elsif Current = Adacraft.Protocol.State.Status then
         Client_Version := 0;
         Dispatch_Status
           (Socket, Current, Packet_Id, Payload, Config, Status_Sent,
            Close_Now);
      else
         Client_Version := 0;
         Close_Now := False;
      end if;
   end Dispatch_Packet;

   pragma Unreferenced (Send_Reply);
   pragma Unreferenced (Close_Silently);
   pragma Unreferenced (Dispatch_Handshake);
   pragma Unreferenced (Dispatch_Status);
   pragma Unreferenced (Dispatch_Packet);
begin
   if Ada.Command_Line.Argument_Count >= 1 then
      Port := GNAT.Sockets.Port_Type'Value (Ada.Command_Line.Argument (1));
   end if;
   Ada.Text_IO.Put_Line
     ("AdaCraft " & Adacraft.Minecraft_Version
      & " protocol" & Adacraft.Protocol_Version'Image
      & " listening on" & Port'Image);
   Adacraft.Network.Serve (Port);
end Adacraft_Server;
