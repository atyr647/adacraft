with Ada.Command_Line;
with Ada.Streams;
with Ada.Text_IO;
with GNAT.Sockets;
with Interfaces;
with Adacraft;
with Adacraft.Protocol;
with Adacraft.Protocol.State;
with Adacraft.Protocol.Handshake_Exchange;
with Adacraft.Protocol.Status_Exchange;

procedure Adacraft_Server is
   Port : GNAT.Sockets.Port_Type := 25565;

   type Conn_Session is record
      Current        : Adacraft.Protocol.State.Connection_State :=
        Adacraft.Protocol.State.Handshake;
      Config         : Adacraft.Protocol.Status_Exchange.Status_Config;
      Status_Sent    : Boolean := False;
      Client_Version : Integer := 0;
   end record;

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

   procedure Serve_Packet
     (Socket    : GNAT.Sockets.Socket_Type;
      S         : in out Conn_Session;
      Buf       : Adacraft.Protocol.Octets;
      From      : Positive;
      Consumed  : out Natural;
      Close_Now : out Boolean)
   is
      use type Interfaces.Unsigned_8;
      Pos      : Natural := From;
      Pkt_Len  : Natural := 0;
      Id       : Natural := 0;
      Id_End   : Natural := 0;
      Shift    : Natural := 0;
      B        : Adacraft.Protocol.Octet;
      Close_Flag : Boolean := False;
      Client_Ver : Integer := 0;
   begin
      Consumed := 0;
      Close_Now := False;
      if From > Buf'Last then
         return;
      end if;
      Pkt_Len := 0;
      Shift := 0;
      Pos := From;
      loop
         if Pos > Buf'Last then
            return;
         end if;
         B := Buf (Pos);
         if Shift >= 35 then
            Close_Silently (Socket);
            Close_Now := True;
            Consumed := Buf'Last - From + 1;
            return;
         end if;
         Pkt_Len := Pkt_Len + Natural (B and 16#7F#) * (2 ** Shift);
         Shift := Shift + 7;
         Pos := Pos + 1;
         exit when (B and 16#80#) = 0;
         if Shift > 28 then
            Close_Silently (Socket);
            Close_Now := True;
            Consumed := Buf'Last - From + 1;
            return;
         end if;
      end loop;
      if Pkt_Len = 0 or else Pkt_Len > Adacraft.Protocol.Max_Packet_Length then
         Close_Silently (Socket);
         Close_Now := True;
         Consumed := Pos - From;
         return;
      end if;
      if Buf'Last - Pos + 1 < Pkt_Len then
         return;
      end if;
      Id := 0;
      Shift := 0;
      Id_End := Pos;
      loop
         B := Buf (Id_End);
         if Shift >= 35 then
            Close_Silently (Socket);
            Close_Now := True;
            Consumed := (Pos - From) + Pkt_Len;
            return;
         end if;
         Id := Id + Natural (B and 16#7F#) * (2 ** Shift);
         Shift := Shift + 7;
         Id_End := Id_End + 1;
         exit when (B and 16#80#) = 0;
      end loop;
      declare
         Pay_First : constant Natural := Id_End;
         Pay_Last  : constant Natural := Pos + Pkt_Len - 1;
         Frame_End : constant Natural := Pos + Pkt_Len;
      begin
         if Pay_First > Pay_Last then
            declare
               Empty : constant Adacraft.Protocol.Octets (1 .. 0) :=
                 (1 .. 0 => <>);
            begin
               Dispatch_Packet
                 (Socket, S.Current, Id, Empty, S.Config,
                  S.Status_Sent, Client_Ver, Close_Flag);
            end;
         else
            Dispatch_Packet
              (Socket, S.Current, Id,
               Buf (Pay_First .. Pay_Last), S.Config,
               S.Status_Sent, Client_Ver, Close_Flag);
         end if;
         S.Client_Version := Client_Ver;
         Consumed := Frame_End - From;
         Close_Now := Close_Flag;
      end;
   end Serve_Packet;

   procedure Serve_Client (Socket : GNAT.Sockets.Socket_Type) is
      use type Ada.Streams.Stream_Element_Offset;
      use type Adacraft.Protocol.State.Connection_State;
      Cap  : constant := 8192;
      Hold : Adacraft.Protocol.Octets (1 .. Cap) := (others => 0);
      Used : Natural := 0;
      Item : Ada.Streams.Stream_Element_Array (1 .. 2048);
      Last : Ada.Streams.Stream_Element_Offset;
      S    : Conn_Session;
      Done : Boolean := False;
   begin
      S.Config := Adacraft.Protocol.Status_Exchange.Default_Config;
      loop
         GNAT.Sockets.Receive_Socket (Socket, Item, Last);
         exit when Last < Item'First;
         if Used + Natural (Last - Item'First + 1) > Cap then
            Close_Silently (Socket);
            exit;
         end if;
         for I in Item'First .. Last loop
            Used := Used + 1;
            Hold (Used) := Adacraft.Protocol.Octet (Item (I));
         end loop;
         loop
            declare
               Consumed  : Natural := 0;
               Close_Now : Boolean := False;
            begin
               Serve_Packet (Socket, S, Hold (1 .. Used), 1, Consumed, Close_Now);
               if Consumed = 0 then
                  exit;
               end if;
               if Consumed < Used then
                  Hold (1 .. Used - Consumed) :=
                    Hold (Consumed + 1 .. Used);
               end if;
               Used := Used - Consumed;
               if Close_Now then
                  Used := 0;
                  Done := True;
                  exit;
               end if;
               exit when Used = 0;
            end;
         end loop;
         exit when Done;
      end loop;
      Close_Silently (Socket);
   end Serve_Client;

   procedure Serve (Port : GNAT.Sockets.Port_Type) is
      use GNAT.Sockets;
      Server : Socket_Type;
      Client : Socket_Type;
      Addr   : Sock_Addr_Type;
      Peer   : Sock_Addr_Type;
   begin
      Create_Socket (Server);
      Set_Socket_Option (Server, Socket_Level, (Reuse_Address, True));
      Addr.Addr := Any_Inet_Addr;
      Addr.Port := Port;
      Bind_Socket (Server, Addr);
      Listen_Socket (Server);
      loop
         Accept_Socket (Server, Client, Peer);
         Serve_Client (Client);
         Close_Socket (Client);
      end loop;
   end Serve;

begin
   if Ada.Command_Line.Argument_Count >= 1 then
      Port := GNAT.Sockets.Port_Type'Value (Ada.Command_Line.Argument (1));
   end if;
   Ada.Text_IO.Put_Line
     ("AdaCraft " & Adacraft.Minecraft_Version
      & " protocol" & Adacraft.Protocol_Version'Image
      & " listening on" & Port'Image);
   Serve (Port);
end Adacraft_Server;
