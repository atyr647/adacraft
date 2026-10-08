with Ada.Streams;
with Adacraft.Protocol.Frame;
with Adacraft.Protocol.Handshake_Exchange;
with Adacraft.Protocol.State;
with Adacraft.Protocol.Status_Exchange;

package body Adacraft.Network is
   type Conn_Session is record
      Current        : Adacraft.Protocol.State.Connection_State :=
        Adacraft.Protocol.State.Handshake;
      Config         : Adacraft.Protocol.Status_Exchange.Status_Config;
      Status_Sent    : Boolean := False;
      Client_Version : Integer := 0;
   end record;

   procedure Close_Silently (Socket : GNAT.Sockets.Socket_Type) is
   begin
      GNAT.Sockets.Close_Socket (Socket);
   exception
      when others =>
         null;
   end Close_Silently;

   procedure Send_Reply
     (Socket    : GNAT.Sockets.Socket_Type;
      Data      : Adacraft.Protocol.Octets;
      Close_Now : out Boolean)
   is
      use type Ada.Streams.Stream_Element_Offset;
      use type Adacraft.Protocol.Frame.Encode_Status;
      Body_Msg : Ada.Streams.Stream_Element_Array
        (1 .. Ada.Streams.Stream_Element_Offset (Data'Length));
      Idx : Natural := 0;
      Frame_Out : Ada.Streams.Stream_Element_Array
        (1 .. Ada.Streams.Stream_Element_Offset
           (Adacraft.Protocol.Status_Exchange.Max_Reply_Bytes + 3));
      Last : Ada.Streams.Stream_Element_Offset;
      Enc  : Adacraft.Protocol.Frame.Encode_Status;
      Sent : Ada.Streams.Stream_Element_Offset;
      Next : Ada.Streams.Stream_Element_Offset;
   begin
      Close_Now := False;
      if Data'Length = 0 then
         return;
      end if;
      for B of Data loop
         Idx := Idx + 1;
         Body_Msg (Ada.Streams.Stream_Element_Offset (Idx)) :=
           Ada.Streams.Stream_Element (B);
      end loop;
      Adacraft.Protocol.Frame.Encode (Body_Msg, Frame_Out, Last, Enc);
      if Enc /= Adacraft.Protocol.Frame.Ok then
         Close_Silently (Socket);
         Close_Now := True;
         return;
      end if;
      Next := Frame_Out'First;
      while Next <= Last loop
         GNAT.Sockets.Send_Socket (Socket, Frame_Out (Next .. Last), Sent);
         exit when Sent >= Last;
         exit when Sent < Next;
         Next := Sent + 1;
      end loop;
   exception
      when others =>
         Close_Silently (Socket);
         Close_Now := True;
   end Send_Reply;

   procedure Dispatch_Handshake
     (Socket         : GNAT.Sockets.Socket_Type;
      Current        : in out Adacraft.Protocol.State.Connection_State;
      Packet_Id      : Integer;
      Payload        : Adacraft.Protocol.Octets;
      Client_Version : in out Integer;
      Close_Now      : out Boolean)
   is
      H_Outcome : Adacraft.Protocol.Handshake_Exchange.Outcome :=
        Adacraft.Protocol.Handshake_Exchange.Handle
          (Current, Packet_Id, Payload);
   begin
      if H_Outcome.Accepted then
         Client_Version := H_Outcome.Client_Version;
      end if;
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
      Send_Failed : Boolean := False;
   begin
      Adacraft.Protocol.Status_Exchange.Handle
        (Current, Packet_Id, Payload, Config, Status_Sent, S_Outcome);
      if S_Outcome.Has_Reply and then S_Outcome.Reply_Length > 0 then
         Send_Reply
           (Socket,
            S_Outcome.Reply_Data (1 .. S_Outcome.Reply_Length),
            Send_Failed);
      end if;
      Close_Now :=
        S_Outcome.Close_Requested or else not S_Outcome.Accepted
        or else Send_Failed;
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
      Client_Version : in out Integer;
      Close_Now      : out Boolean)
   is
      use type Adacraft.Protocol.State.Connection_State;
   begin
      if Current = Adacraft.Protocol.State.Handshake then
         Dispatch_Handshake
           (Socket, Current, Packet_Id, Payload, Client_Version, Close_Now);
      elsif Current = Adacraft.Protocol.State.Status then
         Dispatch_Status
           (Socket, Current, Packet_Id, Payload, Config, Status_Sent,
            Close_Now);
      else
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
      Frame      : Adacraft.Protocol.Frame.Frame_Decode;
      Close_Flag : Boolean := False;
      Client_Ver : Integer := S.Client_Version;
      use type Adacraft.Protocol.Status_Kind;
   begin
      Consumed := 0;
      Close_Now := False;
      if From > Buf'Last then
         return;
      end if;
      Frame := Adacraft.Protocol.Frame.Decode_Frame (Buf, From);
      if Frame.Status = Adacraft.Protocol.Need_More then
         if Frame.Declared_Length > Adacraft.Protocol.Max_Packet_Length then
            Close_Silently (Socket);
            Close_Now := True;
            Consumed := Buf'Last - From + 1;
         end if;
         return;
      elsif Frame.Status /= Adacraft.Protocol.Ok then
         Close_Silently (Socket);
         Close_Now := True;
         Consumed := Buf'Last - From + 1;
         return;
      end if;
      if Frame.Payload_First > Frame.Payload_Last then
         declare
            Empty : constant Adacraft.Protocol.Octets (1 .. 0) :=
              (1 .. 0 => <>);
         begin
            Dispatch_Packet
              (Socket, S.Current, Frame.Packet_Id, Empty, S.Config,
               S.Status_Sent, Client_Ver, Close_Flag);
         end;
      else
         Dispatch_Packet
           (Socket, S.Current, Frame.Packet_Id,
            Buf (Frame.Payload_First .. Frame.Payload_Last), S.Config,
            S.Status_Sent, Client_Ver, Close_Flag);
      end if;
      S.Client_Version := Client_Ver;
      Consumed := Frame.Next - From;
      Close_Now := Close_Flag;
   end Serve_Packet;

   procedure Serve_Client (Client : GNAT.Sockets.Socket_Type) is
      use type Ada.Streams.Stream_Element_Offset;
      Cap  : constant := 8192;
      Hold : Protocol.Octets (1 .. Cap) := (others => 0);
      Used : Natural := 0;
      Item : Ada.Streams.Stream_Element_Array (1 .. 2048);
      Last : Ada.Streams.Stream_Element_Offset;
      S    : Conn_Session;
      Done : Boolean := False;
   begin
      S.Config := Adacraft.Protocol.Status_Exchange.Default_Config;
      loop
         begin
            GNAT.Sockets.Receive_Socket (Client, Item, Last);
         exception
            when others =>
               Close_Silently (Client);
               exit;
         end;
         exit when Last < Item'First;
         if Used + Natural (Last - Item'First + 1) > Cap then
            Close_Silently (Client);
            exit;
         end if;
         for I in Item'First .. Last loop
            Used := Used + 1;
            Hold (Used) := Protocol.Octet (Item (I));
         end loop;
         loop
            declare
               Consumed  : Natural := 0;
               Close_Now : Boolean := False;
            begin
               Serve_Packet (Client, S, Hold (1 .. Used), 1, Consumed, Close_Now);
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
      Close_Silently (Client);
   end Serve_Client;

   procedure Serve (Port : GNAT.Sockets.Port_Type) is
      use GNAT.Sockets;
      Server  : Socket_Type;
      Client  : Socket_Type;
      Address : Sock_Addr_Type;
      Peer    : Sock_Addr_Type;
   begin
      Create_Socket (Server);
      Set_Socket_Option (Server, Socket_Level, (Reuse_Address, True));
      Address.Addr := Any_Inet_Addr;
      Address.Port := Port;
      Bind_Socket (Server, Address);
      Listen_Socket (Server);
      loop
         Accept_Socket (Server, Client, Peer);
         Serve_Client (Client);
         Close_Silently (Client);
      end loop;
   end Serve;
end Adacraft.Network;
