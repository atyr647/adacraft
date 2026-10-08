--  Lab-only wire body. All GNAT.Sockets plus shipped framing/codec/
--  state calls live here. Uncompressed/unencrypted only.
with Ada.Streams;
with Ada.Strings.Unbounded;
with Adacraft.Ingress;
with Adacraft.Protocol.Frame;
with Adacraft.Protocol.Packet_Encoder;
with Adacraft.Protocol.Varnum;
with Adacraft.Protocol;

package body Differential.Capture.Wire is

   use Ada.Streams;
   use type Adacraft.Protocol.State.Connection_State;
   use type Adacraft.Protocol.Status_Kind;

   Got_Frame   : Boolean := False;
   Got_Closed  : Boolean := False;
   Last_Len    : Natural := 0;
   Last_Body   : Adacraft.Protocol.Frame.Byte_Array
     (1 .. Adacraft.Protocol.Frame.Max_Frame_Body_Length) :=
       [others => 0];

   procedure On_Body (Data : Adacraft.Protocol.Frame.Byte_Array) is
   begin
      if Data'Length <= Last_Body'Length then
         Last_Body (1 .. Data'Length) := Data;
         Last_Len := Data'Length;
         Got_Frame := True;
      end if;
   end On_Body;

   procedure On_Close is
   begin
      Got_Closed := True;
   end On_Close;

   procedure Open
     (Target : in Differential.Args.Endpoint;
      S      : in out Session;
      Ok     : out Boolean)
   is
      use GNAT.Sockets;
      use Ada.Strings.Unbounded;
      Addr : Sock_Addr_Type;
   begin
      Ok := False;
      S.Opened := False;
      S.State := Adacraft.Protocol.State.Initial_State;
      S.Socket := No_Socket;
      begin
         Create_Socket (S.Socket);
         Addr := (Family_Inet,
                  Inet_Addr (To_String (Target.Host)),
                  Port_Type (Target.Port));
         Connect_Socket (S.Socket, Addr);
      exception
         when Socket_Error | Constraint_Error =>
            if S.Socket /= No_Socket then
               begin
                  Close_Socket (S.Socket);
               exception
                  when others =>
                     null;
               end;
               S.Socket := No_Socket;
            end if;
            return;
      end;
      S.Opened := True;
      Ok := True;
   end Open;

   procedure Close (S : in out Session) is
      use GNAT.Sockets;
   begin
      if S.Socket /= No_Socket then
         begin
            Close_Socket (S.Socket);
         exception
            when others =>
               null;
         end;
         S.Socket := No_Socket;
      end if;
      S.Opened := False;
   end Close;

   function Is_Open (S : Session) return Boolean is
   begin
      return S.Opened;
   end Is_Open;

   function Current_State (S : Session) return Adacraft.Protocol.State.Connection_State is
   begin
      return S.State;
   end Current_State;

   procedure Send_Serverbound
     (S         : in out Session;
      Packet_Id : in Adacraft.Protocol.State.Packet_Id;
      Ok        : out Boolean)
   is
      use GNAT.Sockets;
      E    : Adacraft.Protocol.Packet_Encoder.Encoder_Type;
      Sent : Stream_Element_Offset;
      Out_Buf : Stream_Element_Array (1 .. 4_096);
      Last    : Stream_Element_Offset;
   begin
      Ok := False;
      if not S.Opened or else S.Socket = No_Socket then
         return;
      end if;
      Adacraft.Protocol.Packet_Encoder.Start_Packet (E, Natural (Packet_Id));
      if Adacraft.Protocol.Packet_Encoder.Has_Failed (E) then
         return;
      end if;
      Adacraft.Protocol.Packet_Encoder.Get_Framed (E, Out_Buf, Last);
      if Adacraft.Protocol.Packet_Encoder.Has_Failed (E) then
         return;
      end if;
      begin
         Send_Socket (S.Socket, Out_Buf (Out_Buf'First .. Last), Sent);
         Ok := Sent = Last;
      exception
         when Socket_Error =>
            Ok := False;
      end;
   end Send_Serverbound;

   procedure Receive_One
     (S            : in out Session;
      Timeout      : in Duration;
      Present      : out Boolean;
      Timed_Out    : out Boolean;
      Peer_Closed  : out Boolean;
      Malformed    : out Boolean;
      Direction    : out Adacraft.Protocol.State.Packet_Direction;
      Packet_Id    : out Adacraft.Protocol.State.Packet_Id;
      State_Valid  : out Boolean)
   is
      use GNAT.Sockets;
      Sel    : Selector_Type;
      R_Set  : Socket_Set_Type;
      W_Set  : Socket_Set_Type;
      Status : Selector_Status;
      Chunk  : Stream_Element_Array (1 .. 4_096);
      Last   : Stream_Element_Offset;
      Conn   : Adacraft.Ingress.Connection_Type;
   begin
      Present := False;
      Timed_Out := False;
      Peer_Closed := False;
      Malformed := False;
      Direction := Adacraft.Protocol.State.Clientbound;
      Packet_Id := 0;
      State_Valid := False;
      if not S.Opened or else S.Socket = No_Socket then
         Peer_Closed := True;
         return;
      end if;
      Got_Frame := False;
      Got_Closed := False;
      Last_Len := 0;
      Create_Selector (Sel);
      Empty (R_Set);
      Empty (W_Set);
      Set (R_Set, S.Socket);
      Check_Selector (Sel, R_Set, W_Set, Status, Timeout);
      Close_Selector (Sel);
      if Status = Expired then
         Timed_Out := True;
         return;
      elsif Status /= Completed then
         Peer_Closed := True;
         return;
      end if;
      begin
         Receive_Socket (S.Socket, Chunk, Last);
      exception
         when Socket_Error =>
            Peer_Closed := True;
            return;
      end;
      if Last < Chunk'First then
         Peer_Closed := True;
         return;
      end if;
      Adacraft.Ingress.Initialize (Conn, On_Body'Access, On_Close'Access);
      Adacraft.Ingress.Receive (Conn, Chunk (Chunk'First .. Last));
      if Adacraft.Ingress.Is_Closed (Conn) and then not Got_Frame then
         if Got_Closed then
            Malformed := True;
         else
            Peer_Closed := True;
         end if;
         return;
      end if;
      if not Got_Frame or else Last_Len = 0 then
         Timed_Out := True;
         return;
      end if;
      declare
         Oct : Adacraft.Protocol.Octets (1 .. Last_Len);
         Res : Adacraft.Protocol.Varnum.Varint_Result;
      begin
         for I in 1 .. Last_Len loop
            Oct (I) := Adacraft.Protocol.Octet (Last_Body (Stream_Element_Offset (I)));
         end loop;
         Res := Adacraft.Protocol.Varnum.Decode_Varint (Oct, 1);
         if Res.Status /= Adacraft.Protocol.Ok then
            Malformed := True;
            return;
         end if;
         Packet_Id := Adacraft.Protocol.State.Packet_Id (Res.Value);
         Direction := Adacraft.Protocol.State.Clientbound;
         State_Valid := Adacraft.Protocol.State.Is_Packet_Valid
           (S.State, Direction, Packet_Id);
         Present := True;
      end;
   end Receive_One;

end Differential.Capture.Wire;
