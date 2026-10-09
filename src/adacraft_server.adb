with Ada.Command_Line;
with Ada.Streams;
with Ada.Text_IO;
with GNAT.Sockets;
with Interfaces;
with Adacraft;
with Adacraft.Protocol;
with Adacraft.Protocol.Buffer;
with Adacraft.Protocol.State;
with Adacraft.Protocol.Frame;
with Adacraft.Protocol.Handshake_Exchange;
with Adacraft.Protocol.Status_Exchange;

procedure Adacraft_Server is
   Port   : GNAT.Sockets.Port_Type := 25565;
   Config : Adacraft.Server_Config := Adacraft.Default_Server_Config;

   procedure Dispatch_Decoded_Frame
     (Current          : in out Adacraft.Protocol.State.Connection_State;
      Packet_Id        : in     Natural;
      Payload          : in     Adacraft.Protocol.Octets;
      Stored           : in out Adacraft.Protocol.Handshake_Exchange.Connection_Data;
      Sess             : in out Adacraft.Protocol.Status_Exchange.Session;
      Response_Id      :    out Natural;
      Response_Data    : in out Adacraft.Protocol.Octets;
      Response_Len     :    out Natural;
      Close_Connection :    out Boolean)
   is
      use type Adacraft.Protocol.State.Connection_State;
      use type Adacraft.Protocol.Handshake_Exchange.Handle_Result;
   begin
      case Current is
         when Adacraft.Protocol.State.Handshake =>
            declare
               H_Res : Adacraft.Protocol.Handshake_Exchange.Handle_Result;
            begin
               Adacraft.Protocol.Handshake_Exchange.Handle
                 (Packet_Id => Packet_Id,
                  Payload   => Payload,
                  Current   => Current,
                  Stored    => Stored,
                  Result    => H_Res);
               Response_Id := 0;
               Response_Len := 0;
               for I in Response_Data'Range loop
                  Response_Data (I) := 0;
               end loop;
               if H_Res = Adacraft.Protocol.Handshake_Exchange.Accepted_Status
                 or else H_Res = Adacraft.Protocol.Handshake_Exchange.Accepted_Login
               then
                  Close_Connection := False;
               else
                  Close_Connection := True;
               end if;
            end;
         when Adacraft.Protocol.State.Status =>
            declare
               S_Res : Adacraft.Protocol.Status_Exchange.Handle_Result;
            begin
               Adacraft.Protocol.Status_Exchange.Handle
                 (Packet_Id        => Packet_Id,
                  Payload          => Payload,
                  Current          => Current,
                  Session_State    => Sess,
                  Result           => S_Res,
                  Response_Id      => Response_Id,
                  Response_Data    => Response_Data,
                  Response_Len     => Response_Len,
                  Close_Connection => Close_Connection);
            end;
         when others =>
            --  Login onward: not yet implemented; close without Login logic.
            Response_Id := 0;
            Response_Len := 0;
            for I in Response_Data'Range loop
               Response_Data (I) := 0;
            end loop;
            Close_Connection := True;
      end case;
   end Dispatch_Decoded_Frame;

   procedure Dispatch_Raw_Buffer
     (Current          : in out Adacraft.Protocol.State.Connection_State;
      Buffer           : in     Adacraft.Protocol.Octets;
      From             : in     Positive;
      Stored           : in out Adacraft.Protocol.Handshake_Exchange.Connection_Data;
      Sess             : in out Adacraft.Protocol.Status_Exchange.Session;
      Response_Id      :    out Natural;
      Response_Data    : in out Adacraft.Protocol.Octets;
      Response_Len     :    out Natural;
      Close_Connection :    out Boolean)
   is
      use type Adacraft.Protocol.State.Connection_State;
      use type Adacraft.Protocol.Status_Kind;
      F : constant Adacraft.Protocol.Frame.Frame_Decode :=
        Adacraft.Protocol.Frame.Decode_Frame (Buffer, From);
   begin
      Response_Id := 0;
      Response_Len := 0;
      for I in Response_Data'Range loop
         Response_Data (I) := 0;
      end loop;
      Close_Connection := False;
      if F.Status /= Adacraft.Protocol.Ok then
         if Current = Adacraft.Protocol.State.Status then
            Close_Connection := True;
         end if;
         return;
      end if;
      if F.Payload_Last < F.Payload_First then
         declare
            Empty : constant Adacraft.Protocol.Octets (2 .. 1) :=
              (others => <>);
         begin
            Dispatch_Decoded_Frame
              (Current, F.Packet_Id, Empty, Stored, Sess,
               Response_Id, Response_Data, Response_Len, Close_Connection);
         end;
      else
         Dispatch_Decoded_Frame
           (Current, F.Packet_Id,
            Buffer (F.Payload_First .. F.Payload_Last),
            Stored, Sess,
            Response_Id, Response_Data, Response_Len, Close_Connection);
      end if;
   end Dispatch_Raw_Buffer;

   procedure Send_Response
     (Sock        : in GNAT.Sockets.Socket_Type;
      Response_Id : in Natural;
      Response_Data : in Adacraft.Protocol.Octets;
      Response_Len  : in Natural)
   is
      use type Ada.Streams.Stream_Element_Offset;
      Body_W : Adacraft.Protocol.Buffer.Writer (33_000 + 8);
      Wire   : Ada.Streams.Stream_Element_Array (1 .. 40_000);
      Wire_Last : Ada.Streams.Stream_Element_Offset;
      Sent   : Ada.Streams.Stream_Element_Offset;
      Prefix : Adacraft.Protocol.Frame.Prefix_Buffer;
      Prefix_Last : Ada.Streams.Stream_Element_Offset;
      Body_Len : Natural;
   begin
      if Response_Len = 0 then
         return;
      end if;
      Adacraft.Protocol.Buffer.Reset (Body_W);
      Adacraft.Protocol.Buffer.Put_Varint
        (Body_W, Interfaces.Unsigned_32 (Response_Id));
      for I in 1 .. Response_Len loop
         Adacraft.Protocol.Buffer.Put_Octet
           (Body_W, Response_Data (Response_Data'First + I - 1));
      end loop;
      if Body_W.Failed then
         return;
      end if;
      Body_Len := Body_W.Len;
      Adacraft.Protocol.Frame.Write_Length_Prefix
        (Adacraft.Protocol.Frame.Frame_Body_Length (Body_Len),
         Prefix, Prefix_Last);
      Wire_Last := 0;
      for I in 1 .. Prefix_Last loop
         Wire_Last := Wire_Last + 1;
         Wire (Wire_Last) := Prefix (Integer (I));
      end loop;
      for I in 1 .. Body_Len loop
         Wire_Last := Wire_Last + 1;
         Wire (Wire_Last) :=
           Ada.Streams.Stream_Element (Body_W.Data (I));
      end loop;
      GNAT.Sockets.Send_Socket
        (Sock, Wire (Wire'First .. Wire_Last), Sent);
   end Send_Response;

   procedure Serve_Client
     (Client      : in GNAT.Sockets.Socket_Type;
      Online_Mode : in Boolean := Adacraft.Default_Server_Config.Online_Mode)
   is
      use type Ada.Streams.Stream_Element_Offset;
      Current : Adacraft.Protocol.State.Connection_State :=
        Adacraft.Protocol.State.Initial_State;
      Stored : Adacraft.Protocol.Handshake_Exchange.Connection_Data;
      Sess   : Adacraft.Protocol.Status_Exchange.Session;
      --  Per-connection online/offline mode, copied from server config at
      --  accept time. No crypto, state-machine, or packet logic touches it
      --  here; later login wiring branches on this value (R1.1/R1.2).
      Connection_Online_Mode : constant Boolean := Online_Mode;
      pragma Unreferenced (Connection_Online_Mode);
      Cap    : constant := 8192;
      Hold   : Adacraft.Protocol.Octets (1 .. Cap) := (others => 0);
      Used   : Natural := 0;
      Item   : Ada.Streams.Stream_Element_Array (1 .. 2048);
      Last   : Ada.Streams.Stream_Element_Offset;
      Resp_Buf : Adacraft.Protocol.Octets (1 .. 33_008) := (others => 0);
   begin
      Adacraft.Protocol.Status_Exchange.Reset (Sess);
      loop
         GNAT.Sockets.Receive_Socket (Client, Item, Last);
         exit when Last < Item'First;
         if Used + Natural (Last - Item'First + 1) > Cap then
            exit;
         end if;
         for I in Item'First .. Last loop
            Used := Used + 1;
            Hold (Used) := Adacraft.Protocol.Octet (Item (I));
         end loop;
         --  Drain every complete frame in Hold in order.
         declare
            Pos : Positive := 1;
            Done : Boolean := False;
            Want_Close : Boolean := False;
         begin
            while not Done and then Pos <= Used loop
               declare
                  Response_Id : Natural := 0;
                  Response_Len : Natural := 0;
                  Close_Connection : Boolean := False;
                  F : constant Adacraft.Protocol.Frame.Frame_Decode :=
                    Adacraft.Protocol.Frame.Decode_Frame
                      (Hold (1 .. Used), Pos);
                  use type Adacraft.Protocol.Status_Kind;
               begin
                  if F.Status = Adacraft.Protocol.Need_More then
                     Done := True;
                  elsif F.Status /= Adacraft.Protocol.Ok then
                     Dispatch_Raw_Buffer
                       (Current, Hold (1 .. Used), Pos,
                        Stored, Sess,
                        Response_Id, Resp_Buf, Response_Len,
                        Close_Connection);
                     if Response_Len > 0 then
                        Send_Response
                          (Client, Response_Id, Resp_Buf, Response_Len);
                     end if;
                     Want_Close := Close_Connection;
                     Done := True;
                  else
                     Dispatch_Raw_Buffer
                       (Current, Hold (1 .. Used), Pos,
                        Stored, Sess,
                        Response_Id, Resp_Buf, Response_Len,
                        Close_Connection);
                     if Response_Len > 0 then
                        Send_Response
                          (Client, Response_Id, Resp_Buf, Response_Len);
                     end if;
                     if Close_Connection then
                        Used := 0;
                        Want_Close := True;
                        Done := True;
                     elsif F.Next > Used then
                        Used := 0;
                        Done := True;
                     else
                        Hold (1 .. Used - F.Next + 1) :=
                          Hold (F.Next .. Used);
                        Used := Used - F.Next + 1;
                        Pos := 1;
                     end if;
                  end if;
               end;
            end loop;
            if Want_Close then
               exit;
            end if;
         end;
      end loop;
   end Serve_Client;

   procedure Serve
     (Port        : in GNAT.Sockets.Port_Type;
      Online_Mode : in Boolean := Adacraft.Default_Server_Config.Online_Mode)
   is
      use GNAT.Sockets;
      Server : Socket_Type;
      Client : Socket_Type;
      Address : Sock_Addr_Type;
      Peer : Sock_Addr_Type;
   begin
      Create_Socket (Server);
      Set_Socket_Option (Server, Socket_Level, (Reuse_Address, True));
      Address.Addr := Any_Inet_Addr;
      Address.Port := Port;
      Bind_Socket (Server, Address);
      Listen_Socket (Server);
      loop
         Accept_Socket (Server, Client, Peer);
         Serve_Client (Client, Online_Mode);
         Close_Socket (Client);
      end loop;
   end Serve;

begin
   --  Ingress dispatch by current state: each received frame is decoded
   --  with Frame.Decode_Frame via Dispatch_Raw_Buffer, then dispatched
   --  by Current via Dispatch_Decoded_Frame: Handshake ->
   --  Handshake_Exchange.Handle, Status -> Status_Exchange.Handle
   --  (sending Response_Id/Response_Data (1 .. Response_Len) when
   --  Response_Len > 0 and closing when Close_Connection is set), Login
   --  onward -> not-yet-implemented close.  Per-connection handling keeps
   --  its own Current/Stored/Sess and follows that path for every frame.
   if Ada.Command_Line.Argument_Count >= 1 then
      Port := GNAT.Sockets.Port_Type'Value (Ada.Command_Line.Argument (1));
   end if;
   Ada.Text_IO.Put_Line
     ("AdaCraft " & Adacraft.Minecraft_Version
      & " protocol" & Adacraft.Protocol_Version'Image
      & " listening on" & Port'Image);
   Serve (Port, Config.Online_Mode);
end Adacraft_Server;
