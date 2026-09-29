with Ada.Streams;
with Adacraft.Ingress;
with Adacraft.Protocol.Buffer;

package body Adacraft.Network is
   procedure Serve_Client (Client : GNAT.Sockets.Socket_Type) is
      use type Ada.Streams.Stream_Element_Offset;
      Cap    : constant := 8192;
      Hold   : Protocol.Octets (1 .. Cap) := (others => 0);
      Used   : Natural := 0;
      Item   : Ada.Streams.Stream_Element_Array (1 .. 2048);
      Last   : Ada.Streams.Stream_Element_Offset;
      Out_W  : Protocol.Buffer.Writer (4096);
      S      : Ingress.Session;
   begin
      loop
         GNAT.Sockets.Receive_Socket (Client, Item, Last);
         exit when Last < Item'First;
         if Used > Cap - Natural (Last - Item'First + 1) then
            exit;
         end if;
         for I in Item'First .. Last loop
            Used := Used + 1;
            Hold (Used) := Protocol.Octet (Item (I));
         end loop;

         Protocol.Buffer.Reset (Out_W);
         declare
            Consumed  : Natural;
            Close_Now : Boolean;
         begin
            Ingress.Ingest (S, Hold (1 .. Used), 1, Consumed, Out_W, Close_Now);
            if Out_W.Len > 0 and then not Out_W.Failed then
               declare
                  Msg : Ada.Streams.Stream_Element_Array (1 .. Ada.Streams.Stream_Element_Offset (Out_W.Len));
                  Sent : Ada.Streams.Stream_Element_Offset;
               begin
                  for I in Msg'Range loop
                     Msg (I) := Ada.Streams.Stream_Element (Out_W.Data (Positive (I)));
                  end loop;
                  GNAT.Sockets.Send_Socket (Client, Msg, Sent);
               end;
            end if;
            if Consumed > 0 and then Consumed <= Used then
               if Consumed < Used then
                  Hold (1 .. Used - Consumed) := Hold (Consumed + 1 .. Used);
               end if;
               Used := Used - Consumed;
            end if;
            exit when Close_Now or else Out_W.Failed;
         end;
      end loop;
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
         Close_Socket (Client);
      end loop;
   end Serve;
end Adacraft.Network;
