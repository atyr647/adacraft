with Ada.Streams;
with GNAT.Sockets;
with Interfaces;
with Adacraft.Ingress;
with Adacraft.Protocol.Frame;
with Adacraft.Protocol.Varnum;

package body Differential.Capture.Wire is
   use type Adacraft.Protocol.State.Connection_State;
   use type Adacraft.Protocol.Status_Kind;
   use type Adacraft.Protocol.Varnum.Status_Type;
   use type Adacraft.Protocol.Frame.Encode_Status;
   use type Adacraft.Protocol.Frame.Feed_Status;
   use type Ada.Streams.Stream_Element;
   use type Ada.Streams.Stream_Element_Offset;
   use type Interfaces.Unsigned_32;

   --  First body collected from the Ingress #204 callback during one
   --  Receive_Packet call.  Single-threaded driver: one active receive at
   --  a time, so a package-level buffer is sufficient.
   Pending_Buf    : Ada.Streams.Stream_Element_Array (1 .. Max_Body);
   Pending_Len    : Natural := 0;
   Pending_Count  : Natural := 0;
   Pending_Closed : Boolean := False;

   procedure On_Body (Data : Adacraft.Ingress.Byte_Array) is
      Len : constant Natural := Data'Length;
   begin
      if Pending_Count = 0 and then Len <= Max_Body then
         Pending_Count := 1;
         Pending_Len := Len;
         if Len > 0 then
            declare
               J : Ada.Streams.Stream_Element_Offset := Pending_Buf'First;
            begin
               for E of Data loop
                  Pending_Buf (J) := E;
                  J := J + 1;
               end loop;
            end;
         end if;
      end if;
   end On_Body;

   procedure On_Close is
   begin
      Pending_Closed := True;
   end On_Close;

   procedure Update_State
     (C   : in out Connection;
      Dir : in     Adacraft.Protocol.State.Packet_Direction;
      Id  : in     Adacraft.Protocol.State.Packet_Id)
   is
      use Adacraft.Protocol.State;
      Ev : constant Packet_Event := (Direction => Dir, Id => Id, Intent => 0);
      R  : constant Transition_Result := Transition (C.State, Ev);
   begin
      if R.Kind = Accepted_Transition then
         C.State := R.Next_State;
      end if;
   end Update_State;

   procedure Connect
     (C    : in out Connection;
      Host : in     String;
      Port : in     Positive)
   is
      use GNAT.Sockets;
      Addr : Sock_Addr_Type;
   begin
      Close (C);
      Create_Socket (C.Sock);
      Addr.Addr := Inet_Addr (Host);
      Addr.Port := Port_Type (Port);
      Connect_Socket (C.Sock, Addr);
      C.Open := True;
      C.State := Adacraft.Protocol.State.Initial_State;
      Adacraft.Ingress.Initialize
        (C.Ingress_Conn, On_Body'Access, On_Close'Access);
      C.Ingress_Ready := True;
   end Connect;

   procedure Close (C : in out Connection) is
      use GNAT.Sockets;
   begin
      if C.Open then
         begin
            Close_Socket (C.Sock);
         exception
            when Socket_Error =>
               null;
         end;
         C.Sock := No_Socket;
         C.Open := False;
      end if;
      C.Ingress_Ready := False;
   end Close;

   function Is_Open (C : Connection) return Boolean is
   begin
      return C.Open;
   end Is_Open;

   function Current_State
     (C : Connection) return Adacraft.Protocol.State.Connection_State
   is
   begin
      return C.State;
   end Current_State;

   procedure Send_All
     (Sock : in out GNAT.Sockets.Socket_Type;
      Data : in     Ada.Streams.Stream_Element_Array)
   is
      use GNAT.Sockets;
      Sent : Ada.Streams.Stream_Element_Offset;
      From : Ada.Streams.Stream_Element_Offset := Data'First;
   begin
      while From <= Data'Last loop
         Send_Socket (Sock, Data (From .. Data'Last), Sent);
         exit when Sent < From;
         From := Sent + 1;
      end loop;
   end Send_All;

   procedure Send_Packet
     (C       : in out Connection;
      Id      : in     Adacraft.Protocol.State.Packet_Id;
      Payload : in     Adacraft.Protocol.Octets)
   is
      use Adacraft.Protocol;
      use Adacraft.Protocol.State;
      Id_Buf  : Octets (1 .. Max_Varint_Bytes) := (others => 0);
      Written : Natural;
      Vstat   : Adacraft.Protocol.Varnum.Status_Type;
      Body_Len   : Natural;
      Frame_Body : Ada.Streams.Stream_Element_Array (1 .. Max_Body);
      Out_Buf    : Ada.Streams.Stream_Element_Array (1 .. Max_Body + 3);
      Last     : Ada.Streams.Stream_Element_Offset;
      Estat    : Adacraft.Protocol.Frame.Encode_Status;
   begin
      Adacraft.Protocol.Varnum.Encode
        (Interfaces.Integer_32 (Integer (Id)), Id_Buf, 1, Written, Vstat);
      if Vstat /= Adacraft.Protocol.Varnum.Ok then
         raise Constraint_Error with "packet id encode failed";
      end if;
      Body_Len := Written + Payload'Length;
      for I in 1 .. Written loop
         Frame_Body (Ada.Streams.Stream_Element_Offset (I)) :=
           Ada.Streams.Stream_Element (Id_Buf (I));
      end loop;
      for I in Payload'Range loop
         Frame_Body (Ada.Streams.Stream_Element_Offset
                 (Written + I - Payload'First + 1)) :=
           Ada.Streams.Stream_Element (Payload (I));
      end loop;
      Adacraft.Protocol.Frame.Encode
        (Frame_Body (1 .. Ada.Streams.Stream_Element_Offset (Body_Len)),
         Out_Buf, Last, Estat);
      if Estat /= Adacraft.Protocol.Frame.Ok then
         raise Constraint_Error with "frame encode failed";
      end if;
      Send_All (C.Sock, Out_Buf (Out_Buf'First .. Last));
      Update_State (C, Serverbound, Id);
   end Send_Packet;

   procedure Receive_Packet
     (C      : in out Connection;
      Id     :    out Adacraft.Protocol.State.Packet_Id;
      Status :    out Receive_Status)
   is
      use Adacraft.Protocol;
      use Adacraft.Protocol.State;
      Chunk : Ada.Streams.Stream_Element_Array (1 .. 4096);
      Last  : Ada.Streams.Stream_Element_Offset;
      Oct   : Octets (1 .. Max_Body);
      Fr    : Adacraft.Protocol.Frame.Frame_Decode;
   begin
      Id := 0;
      if not C.Open or else not C.Ingress_Ready then
         Status := Framing_Error;
         return;
      end if;
      Pending_Count := 0;
      Pending_Len := 0;
      Pending_Closed := False;
      begin
         GNAT.Sockets.Receive_Socket (C.Sock, Chunk, Last);
      exception
         when GNAT.Sockets.Socket_Error =>
            Status := Peer_Closed;
            return;
      end;
      if Last < Chunk'First then
         Status := Peer_Closed;
         return;
      end if;
      Adacraft.Ingress.Receive (C.Ingress_Conn, Chunk (Chunk'First .. Last));
      if Adacraft.Ingress.Is_Closed (C.Ingress_Conn) then
         Status := Framing_Error;
         return;
      end if;
      if Pending_Count = 0 then
         if Pending_Closed then
            Status := Peer_Closed;
         else
            Status := No_Data;
         end if;
         return;
      end if;
      if Pending_Len = 0 then
         Status := Framing_Error;
         return;
      end if;
      for I in 1 .. Pending_Len loop
         Oct (I) :=
           Octet (Pending_Buf (Ada.Streams.Stream_Element_Offset (I)));
      end loop;
      Fr := Adacraft.Protocol.Frame.Decode_Frame (Oct (1 .. Pending_Len), 1);
      if Fr.Status /= Ok then
         Status := Framing_Error;
         return;
      end if;
      Id := Packet_Id (Fr.Packet_Id);
      Update_State (C, Clientbound, Id);
      Status := Ok;
   end Receive_Packet;

end Differential.Capture.Wire;
