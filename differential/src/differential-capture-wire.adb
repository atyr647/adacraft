with Ada.Streams;
with Adacraft.Ingress;
with Adacraft.Protocol;
with Adacraft.Protocol.Frame;
with Adacraft.Protocol.State;
with Adacraft.Protocol.Varnum;
with Differential.Transcript;
with GNAT.Sockets;

package body Differential.Capture.Wire is

   use type Ada.Streams.Stream_Element_Offset;

   procedure Open
     (Host : String;
      Port : Natural;
      Sock : out GNAT.Sockets.Socket_Type;
      Ok   : out Boolean)
   is
      Addr : GNAT.Sockets.Sock_Addr_Type;
   begin
      Ok := False;
      GNAT.Sockets.Create_Socket (Sock);
      GNAT.Sockets.Set_Socket_Option
        (Sock, GNAT.Sockets.Socket_Level,
         (GNAT.Sockets.Receive_Timeout, Read_Timeout));
      Addr.Addr := GNAT.Sockets.Inet_Addr (Host);
      Addr.Port := GNAT.Sockets.Port_Type (Port);
      GNAT.Sockets.Connect_Socket (Sock, Addr);
      Ok := True;
   exception
      when others =>
         Ok := False;
   end Open;

   procedure Close (Sock : in out GNAT.Sockets.Socket_Type) is
   begin
      GNAT.Sockets.Close_Socket (Sock);
   exception
      when others =>
         null;
   end Close;

   procedure Send_Body
     (Sock    : GNAT.Sockets.Socket_Type;
      Payload : Adacraft.Protocol.Frame.Byte_Array;
      Ok      : out Boolean)
   is
      Wire : Adacraft.Protocol.Frame.Byte_Array (1 .. 8_192);
      Last : Ada.Streams.Stream_Element_Offset;
      Enc  : Adacraft.Protocol.Frame.Encode_Status;
      Sent : Ada.Streams.Stream_Element_Offset;
      From : Ada.Streams.Stream_Element_Offset;
   begin
      Ok := False;
      Adacraft.Protocol.Frame.Encode (Payload, Wire, Last, Enc);
      if Enc /= Adacraft.Protocol.Frame.Ok then
         return;
      end if;
      From := Wire'First;
      while From <= Last loop
         GNAT.Sockets.Send_Socket (Sock, Wire (From .. Last), Sent);
         exit when Sent <= 0;
         From := From + Sent;
      end loop;
      Ok := From > Last;
   exception
      when others =>
         Ok := False;
   end Send_Body;

   procedure Recv_Until_Terminal
     (Sock : GNAT.Sockets.Socket_Type;
      Data : out Recv_Data)
   is
      Conn  : Adacraft.Ingress.Connection_Type;
      Chunk : Ada.Streams.Stream_Element_Array (1 .. 2_048);
      Last  : Ada.Streams.Stream_Element_Offset;
      Hold  : Adacraft.Protocol.Octets (1 .. 8_192) := (others => 0);
      Used  : Natural := 0;
      procedure On_Body (Item : Adacraft.Protocol.Frame.Byte_Array) is
         pragma Unreferenced (Item);
      begin
         null;
      end On_Body;
      procedure On_Close is
      begin
         null;
      end On_Close;
   begin
      Data := (others => <>);
      Adacraft.Ingress.Initialize
        (Conn, On_Body'Access, On_Close'Access);
      loop
         begin
            GNAT.Sockets.Receive_Socket (Sock, Chunk, Last);
         exception
            when GNAT.Sockets.Socket_Error =>
               Data.Outcome := Differential.Transcript.Timeout;
               return;
         end;
         exit when Last < Chunk'First;
         declare
            Bytes : Adacraft.Protocol.Frame.Byte_Array (1 .. Last - Chunk'First + 1);
         begin
            for I in Bytes'Range loop
               Bytes (Positive (I)) :=
                 Chunk (Chunk'First + Ada.Streams.Stream_Element_Offset (I) - 1);
            end loop;
            Adacraft.Ingress.Receive (Conn, Bytes);
            if Adacraft.Ingress.Is_Closed (Conn) then
               Data.Outcome := Differential.Transcript.Protocol_Error;
               return;
            end if;
            for I in Bytes'Range loop
               exit when Used = Hold'Last;
               Used := Used + 1;
               Hold (Used) := Adacraft.Protocol.Octet (Bytes (I));
            end loop;
         end;
         while Used > 0 loop
            declare
               D : constant Adacraft.Protocol.Frame.Frame_Decode :=
                 Adacraft.Protocol.Frame.Decode_Frame (Hold (1 .. Used), 1);
            begin
               if D.Status = Adacraft.Protocol.Need_More then
                  exit;
               elsif D.Status /= Adacraft.Protocol.Ok then
                  Data.Outcome := Differential.Transcript.Protocol_Error;
                  return;
               else
                  Data.Ids.Append (D.Packet_Id);
                  if D.Next > Used then
                     Used := 0;
                  else
                     Hold (1 .. Used - D.Next + 1) := Hold (D.Next .. Used);
                     Used := Used - D.Next + 1;
                  end if;
               end if;
            end;
         end loop;
      end loop;
      if Used > 0 then
         Data.Outcome := Differential.Transcript.Peer_Closed;
      else
         Data.Outcome := Differential.Transcript.Completed;
      end if;
   exception
      when others =>
         Data.Outcome := Differential.Transcript.Protocol_Error;
   end Recv_Until_Terminal;

end Differential.Capture.Wire;
