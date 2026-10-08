with Ada.Calendar;
with Ada.Streams;
with Adacraft.Ingress;
with Adacraft.Protocol.Buffer;

package body Adacraft.Network is
   use type GNAT.Sockets.Selector_Status;
   procedure Flush_And_Send
     (Client : GNAT.Sockets.Socket_Type;
      Out_W  : in out Protocol.Buffer.Writer)
   is
      use type Ada.Streams.Stream_Element_Offset;
   begin
      --  Flush-before-close: pong / status bytes are fully sent before
      --  the socket close is initiated. Violation paths have Len = 0
      --  (Close_No_Bytes discarded output) so nothing is sent.
      if Out_W.Len > 0 and then not Out_W.Failed then
         declare
            Msg  : Ada.Streams.Stream_Element_Array
              (1 .. Ada.Streams.Stream_Element_Offset (Out_W.Len));
            Sent : Ada.Streams.Stream_Element_Offset;
            From : Ada.Streams.Stream_Element_Offset := Msg'First;
         begin
            for I in Msg'Range loop
               Msg (I) := Ada.Streams.Stream_Element (Out_W.Data (Positive (I)));
            end loop;
            --  Loop until fully flushed (half-duplex friendly).
            while From <= Msg'Last loop
               GNAT.Sockets.Send_Socket (Client, Msg (From .. Msg'Last), Sent);
               exit when Sent < From;
               From := Sent + 1;
            end loop;
         end;
      end if;
      Protocol.Buffer.Reset (Out_W);
   end Flush_And_Send;

   procedure Close_Without_Flush
     (Client : GNAT.Sockets.Socket_Type;
      Out_W  : in out Protocol.Buffer.Writer)
   is
   begin
      --  Violation close: discard any buffered input, send nothing.
      Protocol.Buffer.Reset (Out_W);
      Out_W.Failed := False;
      GNAT.Sockets.Close_Socket (Client);
   end Close_Without_Flush;

   procedure Serve_Client (Client : GNAT.Sockets.Socket_Type) is
      use type Ada.Streams.Stream_Element_Offset;
      Cap    : constant := 8192;
      Hold   : Protocol.Octets (1 .. Cap) := (others => 0);
      Used   : Natural := 0;
      Item   : Ada.Streams.Stream_Element_Array (1 .. 2048);
      Last   : Ada.Streams.Stream_Element_Offset;
      Out_W  : Protocol.Buffer.Writer (4096);
      S      : Ingress.Session;
      Sel    : GNAT.Sockets.Selector_Type;
      R_Set  : GNAT.Sockets.Socket_Set_Type;
      W_Set  : GNAT.Sockets.Socket_Set_Type;
      E_Set  : GNAT.Sockets.Socket_Set_Type;
      Status : GNAT.Sockets.Selector_Status;
   begin
      GNAT.Sockets.Create_Selector (Sel);
      loop
         --  Idle timeout: wait at most Default_Idle_Timeout for input.
         --  Reset after each successfully completed inbound packet
         --  (S.Last_Activity is stamped by Ingest). Timeout closure
         --  sends no bytes.
         GNAT.Sockets.Empty (R_Set);
         GNAT.Sockets.Empty (W_Set);
         GNAT.Sockets.Empty (E_Set);
         GNAT.Sockets.Set (R_Set, Client);
         GNAT.Sockets.Check_Selector
           (Sel, R_Set, W_Set, E_Set, Status,
            Timeout => Ingress.Default_Idle_Timeout);
         if Status /= GNAT.Sockets.Completed then
            --  No input within the idle window: check the stamp so a
            --  connection that just made progress does not close early.
            if Ingress.Is_Idle_Expired (S, Ada.Calendar.Clock) then
               Protocol.Buffer.Reset (Out_W);
               exit;
            else
               goto Next_Ready;
            end if;
         end if;
         GNAT.Sockets.Receive_Socket (Client, Item, Last);
         exit when Last < Item'First;
         if Used > Cap - Natural (Last - Item'First + 1) then
            Protocol.Buffer.Reset (Out_W);
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
            if Close_Now then
               if Out_W.Len > 0 and then not Out_W.Failed then
                  --  Pong-then-close (or status reply tied to the close):
                  --  flush fully before closing.
                  Flush_And_Send (Client, Out_W);
               else
                  --  Violation / timeout path: close without flushing.
                  Protocol.Buffer.Reset (Out_W);
               end if;
            else
               Flush_And_Send (Client, Out_W);
            end if;
            if Consumed > 0 and then Consumed <= Used then
               if Consumed < Used then
                  Hold (1 .. Used - Consumed) := Hold (Consumed + 1 .. Used);
               end if;
               Used := Used - Consumed;
            end if;
            exit when Close_Now or else Out_W.Failed;
         end;
         <<Next_Ready>>
         null;
      end loop;
      GNAT.Sockets.Close_Selector (Sel);
   exception
      when GNAT.Sockets.Socket_Error =>
         null;
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
