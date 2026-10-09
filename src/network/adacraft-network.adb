with Ada.Calendar;
with Ada.Exceptions;
with Ada.Streams;
with Ada.Unchecked_Deallocation;
with Ada.Text_IO;
with GNAT.Sockets;
with Interfaces;
with Adacraft.Auth;
with Adacraft.Protocol.Buffer;
with Adacraft.Protocol.Frame;
with Adacraft.Protocol.Handshake_Exchange;
with Adacraft.Protocol.Login;
with Adacraft.Protocol.State;
with Adacraft.Protocol.State.Table;
with Adacraft.Protocol.Status_Exchange;
with Adacraft.Protocol.Varnum;

package body Adacraft.Network is
   use type Ada.Calendar.Time;
   use type Ada.Streams.Stream_Element_Offset;
   use type Adacraft.Protocol.Frame.Feed_Status;
   use type Adacraft.Protocol.Status_Exchange.Handle_Result;
   use type GNAT.Sockets.Selector_Status;

   function Fd_Of (S : GNAT.Sockets.Socket_Type) return Integer is
   begin
      return GNAT.Sockets.To_C (S);
   end Fd_Of;

   function Slot_For_Fd (Fd : Integer) return Positive is
   begin
      return Positive ((abs Fd mod Max_Conns) + 1);
   end Slot_For_Fd;

   function Find_Free_Slot return Natural is
   begin
      for I in 1 .. Max_Conns loop
         if Conn_Table (I) = null then
            return I;
         end if;
      end loop;
      return 0;
   end Find_Free_Slot;

   function Find_Slot_For_Sock (S : GNAT.Sockets.Socket_Type) return Natural is
      Fd : constant Integer := Fd_Of (S);
   begin
      for I in 1 .. Max_Conns loop
         if Conn_Table (I) /= null
           and then Conn_Table (I).Has_Sock
           and then Conn_Table (I).Fd_Key = Fd
         then
            return I;
         end if;
      end loop;
      return 0;
   end Find_Slot_For_Sock;

   procedure Parse_Port (Image : String; Port : out GNAT.Sockets.Port_Type) is
      use GNAT.Sockets;
      V : Natural := 0;
   begin
      if Image'Length = 0 then
         raise Constraint_Error with "empty port";
      end if;
      for I in Image'Range loop
         if Image (I) < '0' or else Image (I) > '9' then
            raise Constraint_Error with "non-digit port";
         end if;
         V := V * 10 + (Character'Pos (Image (I)) - Character'Pos ('0'));
         if V > 65535 then
            raise Constraint_Error with "port too large";
         end if;
      end loop;
      if V < 1 or else V > 65535 then
         raise Constraint_Error with "port out of range";
      end if;
      Port := Port_Type (V);
   end Parse_Port;

   procedure Log_One_Line (Msg : String) is
   begin
      Ada.Text_IO.Put_Line (Ada.Text_IO.Standard_Error, Msg);
   exception
      when others => null;
   end Log_One_Line;

   procedure Close_Conn (Idx : Positive; Reason : String := "") is
      C : Conn_Access;
   begin
      if Idx < 1 or else Idx > Max_Conns then
         return;
      end if;
      C := Conn_Table (Idx);
      if C = null then
         return;
      end if;
      if Reason'Length > 0 then
         begin
            Log_One_Line ("adacraft_server: closing connection: " & Reason);
         exception
            when others => null;
         end;
      end if;
      if C.Has_Sock then
         begin
            GNAT.Sockets.Shutdown_Socket (C.Sock);
         exception
            when others => null;
         end;
         begin
            GNAT.Sockets.Close_Socket (C.Sock);
         exception
            when others => null;
         end;
         C.Has_Sock := False;
      end if;
      C.Recv_Len := 0;
      C.Send_Pos := 1;
      C.Send_Len := 0;
      C.Closing := True;
      C.In_Use := False;
      C.Fd_Key := -1;
      Conn_Table (Idx) := null;
      begin
         --  Release per-connection resources (unconstrained deallocation).
         declare
            procedure Free_Conn is new Ada.Unchecked_Deallocation
              (Conn, Conn_Access);
            Tmp : Conn_Access := C;
         begin
            Free_Conn (Tmp);
         end;
      exception
         when others => null;
      end;
   end Close_Conn;

   procedure Set_Non_Blocking (S : GNAT.Sockets.Socket_Type) is
      Req : GNAT.Sockets.Request_Type (GNAT.Sockets.Non_Blocking_IO);
   begin
      Req.Enabled := True;
      GNAT.Sockets.Control_Socket (S, Req);
   end Set_Non_Blocking;

   function Msg_Is_Again (Msg : String) return Boolean;

   function Is_Would_Block (E : Ada.Exceptions.Exception_Occurrence) return Boolean is
   begin
      --  EAGAIN / EWOULDBLOCK surface here as Socket_Error with assorted
      --  messages by platform; treat them as "try later", not fatal.
      return Msg_Is_Again (Ada.Exceptions.Exception_Message (E));
   end Is_Would_Block;

   function Msg_Is_Again (Msg : String) return Boolean is
   begin
      --  Case-insensitive substring scan for would-block markers.
      if Msg'Length = 0 then
         return False;
      end if;
      declare
         Needle1 : constant String := "again";
         Needle2 : constant String := "WOULD";
         Needle3 : constant String := "would";
         Needle4 : constant String := "BLOCK";
         Needle5 : constant String := "Block";
      begin
         for I in Msg'Range loop
            if I + 4 <= Msg'Last then
               if Msg (I .. I + 4) = "again"
                 or else Msg (I .. I + 4) = "Again"
                 or else Msg (I .. I + 4) = "AGAIN"
               then
                  return True;
               end if;
            end if;
            if I + 4 <= Msg'Last then
               if Msg (I .. I + 4) = "would"
                 or else Msg (I .. I + 4) = "WOULD"
                 or else Msg (I .. I + 4) = "Would"
               then
                  return True;
               end if;
            end if;
            if I + 4 <= Msg'Last then
               if Msg (I .. I + 4) = "Block"
                 or else Msg (I .. I + 4) = "BLOCK"
                 or else Msg (I .. I + 4) = "block"
               then
                  return True;
               end if;
            end if;
         end loop;
         return False;
      end;
   end Msg_Is_Again;

   procedure Queue_Bytes
     (C    : Conn_Access;
      Data : Adacraft.Protocol.Frame.Byte_Array)
   is
      Room : Natural;
   begin
      if C = null or else Data'Length = 0 then
         return;
      end if;
      --  Compact pending region first.
      if C.Send_Len > 0 and then C.Send_Pos > 1 then
         declare
            N : constant Natural := C.Send_Len;
         begin
            for I in 1 .. N loop
               C.Send_Buf (Ada.Streams.Stream_Element_Offset (I)) :=
                 C.Send_Buf (Ada.Streams.Stream_Element_Offset (C.Send_Pos + I - 1));
            end loop;
            C.Send_Pos := 1;
         end;
      elsif C.Send_Len = 0 then
         C.Send_Pos := 1;
      end if;
      Room := Send_Capacity - C.Send_Len;
      if Data'Length > Room then
         --  No room: drop (caller closes after flush attempt).
         return;
      end if;
      declare
         Dst : constant Natural := C.Send_Pos + C.Send_Len;
         K   : Natural := 0;
      begin
         for I in Data'Range loop
            C.Send_Buf (Ada.Streams.Stream_Element_Offset (Dst + K)) := Data (I);
            K := K + 1;
         end loop;
         C.Send_Len := C.Send_Len + Data'Length;
      end;
      C.Last_Activity := Ada.Calendar.Clock;
   end Queue_Bytes;

   procedure Queue_Response
     (C           : Conn_Access;
      Response_Id : Natural;
      Resp        : Adacraft.Protocol.Octets;
      Resp_Len    : Natural)
   is
      Body_W : Adacraft.Protocol.Buffer.Writer (33_000 + 8);
      Prefix : Adacraft.Protocol.Frame.Prefix_Buffer;
      Prefix_Last : Ada.Streams.Stream_Element_Offset;
      Body_Len : Natural;
      Wire : Adacraft.Protocol.Frame.Byte_Array (1 .. Send_Capacity);
      WLast : Ada.Streams.Stream_Element_Offset := 0;
   begin
      if C = null or else Resp_Len = 0 then
         return;
      end if;
      Adacraft.Protocol.Buffer.Reset (Body_W);
      Adacraft.Protocol.Buffer.Put_Varint
        (Body_W, Interfaces.Unsigned_32 (Response_Id));
      for I in 1 .. Resp_Len loop
         Adacraft.Protocol.Buffer.Put_Octet
           (Body_W, Resp (Resp'First + I - 1));
      end loop;
      if Body_W.Failed then
         return;
      end if;
      Body_Len := Body_W.Len;
      Adacraft.Protocol.Frame.Write_Length_Prefix
        (Adacraft.Protocol.Frame.Frame_Body_Length (Body_Len),
         Prefix, Prefix_Last);
      for I in 1 .. Prefix_Last loop
         WLast := WLast + 1;
         Wire (WLast) := Prefix (Integer (I));
      end loop;
      for I in 1 .. Body_Len loop
         exit when WLast >= Send_Capacity;
         WLast := WLast + 1;
         Wire (WLast) :=
           Ada.Streams.Stream_Element (Body_W.Data (I));
      end loop;
      Queue_Bytes (C, Wire (1 .. WLast));
   end Queue_Response;

   procedure Handle_Frame_Body (C : Conn_Access; Frame_Data : Adacraft.Protocol.Frame.Byte_Array) is
      use type Adacraft.Protocol.Status_Kind;
      Blen : Natural := Frame_Data'Length;
      VR   : Adacraft.Protocol.Varnum.Varint_Result;
      Pid  : Natural;
      Pay_First : Positive;
      Resp_Id  : Natural := 0;
      Resp_Len : Natural := 0;
      Want_Close : Boolean := False;
      use type Adacraft.Protocol.State.Connection_State;
      use type Adacraft.Protocol.Handshake_Exchange.Handle_Result;
      Oct : Adacraft.Protocol.Octets (1 .. Frame_Data'Length);
   begin
      if C = null then
         return;
      end if;
      if Frame_Data'Length = 0 then
         raise Constraint_Error with "empty frame";
      end if;
      Blen := Frame_Data'Length;
      declare
         K : Natural := 0;
      begin
         for I in Frame_Data'Range loop
            K := K + 1;
            Oct (K) := Adacraft.Protocol.Octet (Frame_Data (I));
         end loop;
      end;
      --  Packet id is a VarInt of at most 5 bytes; enforced by decoder.
      VR := Adacraft.Protocol.Varnum.Decode_Varint (Oct (1 .. Blen), 1);
      if VR.Status /= Adacraft.Protocol.Ok then
         raise Constraint_Error with "bad packet id";
      end if;
      Pid := Natural (VR.Value);
      Pay_First := VR.Next;
      if C.Proto_State = Adacraft.Protocol.State.Handshake then
         declare
            H_Res : Adacraft.Protocol.Handshake_Exchange.Handle_Result;
            Empty : constant Adacraft.Protocol.Octets (2 .. 1) := (others => <>);
         begin
            if Pay_First > Blen then
               Adacraft.Protocol.Handshake_Exchange.Handle
                 (Packet_Id => Pid, Payload => Empty,
                  Current => C.Proto_State, Stored => C.Stored, Result => H_Res);
            else
               Adacraft.Protocol.Handshake_Exchange.Handle
                 (Packet_Id => Pid, Payload => Oct (Pay_First .. Blen),
                  Current => C.Proto_State, Stored => C.Stored, Result => H_Res);
            end if;
            if H_Res /= Adacraft.Protocol.Handshake_Exchange.Accepted_Status
              and then H_Res /= Adacraft.Protocol.Handshake_Exchange.Accepted_Login
            then
               raise Constraint_Error with "handshake rejected";
            end if;
         end;
      elsif C.Proto_State = Adacraft.Protocol.State.Status then
         declare
            S_Res : Adacraft.Protocol.Status_Exchange.Handle_Result;
            Resp_Buf : Adacraft.Protocol.Octets (1 .. 33_008) := (others => 0);
            Empty : constant Adacraft.Protocol.Octets (2 .. 1) := (others => <>);
         begin
            if Pay_First > Blen then
               Adacraft.Protocol.Status_Exchange.Handle
                 (Packet_Id => Pid,
                  Payload => Empty,
                  Current => C.Proto_State, Session_State => C.Sess,
                  Result => S_Res, Response_Id => Resp_Id,
                  Response_Data => Resp_Buf, Response_Len => Resp_Len,
                  Close_Connection => Want_Close);
            else
               Adacraft.Protocol.Status_Exchange.Handle
                 (Packet_Id => Pid,
                  Payload => Oct (Pay_First .. Blen),
                  Current => C.Proto_State, Session_State => C.Sess,
                  Result => S_Res, Response_Id => Resp_Id,
                  Response_Data => Resp_Buf, Response_Len => Resp_Len,
                  Close_Connection => Want_Close);
            end if;
            if Resp_Len > 0 then
               Queue_Response (C, Resp_Id, Resp_Buf, Resp_Len);
            end if;
            if Want_Close and then C.Send_Len = 0 then
               raise Constraint_Error with "status close";
            elsif Want_Close then
               C.Closing := True;
            end if;
            if S_Res = Adacraft.Protocol.Status_Exchange.Rejected_Close
              and then Resp_Len = 0
            then
               raise Constraint_Error with "status rejected";
            end if;
         end;
      elsif C.Proto_State = Adacraft.Protocol.State.Login then
         --  Handle_Login (single-shot): Frame body already fed by
         --  Service_Readable via Frame.Feed.  Path:
         --  Frame body -> Varnum packet id -> State.Table validity
         --  -> Login.Decode_Login_Start -> Packet_Encoder Disconnect.
         declare
            LS  : Adacraft.Protocol.Login.Login_Start;
            Reason : String (1 .. 256) := (others => ' ');
            Reason_Len : Natural := 0;
            use type Adacraft.Protocol.State.Connection_State;
            use type Adacraft.Protocol.Login.Login_Start_Status;
         begin
            --  Duplicate Start in same connection: a queued Disconnect
            --  means Start was already seen -> close, no second reply.
            if C.Closing or else C.Send_Len > 0 then
               raise Constraint_Error with "duplicate login start";
            end if;
            --  Per-state validity (§19): only serverbound Login rows pass.
            --  Status/Ping, Handshake, early Ack, unknown id, wrong
            --  direction -> close, no reply.
            if Adacraft.Protocol.State.Table.Find
              (State => Adacraft.Protocol.State.Login,
               Dir   => Adacraft.Protocol.State.Serverbound,
               Id    => Adacraft.Protocol.State.Packet_Id (Pid)) = 0
            then
               raise Constraint_Error with "invalid in login";
            end if;
            if not Adacraft.Protocol.State.Table.Is_Login_Start_Id
              (Adacraft.Protocol.State.Packet_Id (Pid))
            then
               raise Constraint_Error with "not login start";
            end if;
            --  Decode Login Start on the bytes after the packet id.
            if Pay_First <= Blen then
               LS := Adacraft.Protocol.Login.Decode_Login_Start
                 (Oct (Pay_First .. Blen));
            else
               declare
                  Empty : constant Adacraft.Protocol.Octets (2 .. 1) :=
                    (others => <>);
               begin
                  LS :=
                    Adacraft.Protocol.Login.Decode_Login_Start (Empty);
               end;
            end if;
            --  Login Start outcome in Login_State (in place, no second
            --  handler). Malformed -> close, no reply. Decodable but
            --  invalid name -> one Disconnect, close. Valid -> offline
            --  UUID via existing policy, one Success, await Ack.
            --  Invalid-state reject above (Ack before Start) untouched.
            if LS.Status = Adacraft.Protocol.Login.Malformed then
               --  Truncated / length mismatch -> close, no reply, no raise.
               C.Closing := True;
               C.Last_Activity := Ada.Calendar.Clock;
               return;
            end if;
            if LS.Status = Adacraft.Protocol.Login.Invalid_Name then
               --  Decodable but invalid name: single Disconnect, close.
               --  No Success, no state change.
               declare
                  Disc : Adacraft.Protocol.Octets :=
                    Adacraft.Protocol.Login.Build_Login_Disconnect
                      (Adacraft.Protocol.Login.Invalid_Name_Reason);
                  Prefix : Adacraft.Protocol.Frame.Prefix_Buffer;
                  P_Last : Ada.Streams.Stream_Element_Offset;
                  Wire : Adacraft.Protocol.Frame.Byte_Array (1 .. 512) :=
                    (others => 0);
                  W_Last : Ada.Streams.Stream_Element_Offset := 0;
               begin
                  Adacraft.Protocol.Frame.Write_Length_Prefix
                    (Adacraft.Protocol.Frame.Frame_Body_Length (Disc'Length),
                     Prefix, P_Last);
                  for I in 1 .. P_Last loop
                     W_Last := W_Last + 1;
                     Wire (W_Last) := Prefix (Integer (I));
                  end loop;
                  for I in Disc'Range loop
                     W_Last := W_Last + 1;
                     Wire (W_Last) :=
                       Ada.Streams.Stream_Element (Disc (I));
                  end loop;
                  Queue_Bytes (C, Wire (1 .. W_Last));
               end;
               C.Closing := True;
               C.Last_Activity := Ada.Calendar.Clock;
               return;
            end if;
            --  Well-formed Start with valid name (LS.Status = Ok):
            --  offline-identified only; Online_Authenticated concept does
            --  not exist on this Conn (stays offline), one framed Login
            --  Success via Encode_Login_Success, then Login_Awaiting_Ack.
            declare
               Name_Str : constant String := LS.Name (1 .. LS.Name_Len);
               Ident : constant Adacraft.Auth.Player_Identity :=
                 Adacraft.Protocol.Login.Offline_Identity (Name_Str);
               W : Adacraft.Protocol.Buffer.Writer (64);
               Prefix : Adacraft.Protocol.Frame.Prefix_Buffer;
               P_Last : Ada.Streams.Stream_Element_Offset;
               Wire : Adacraft.Protocol.Frame.Byte_Array (1 .. 512) :=
                 (others => 0);
               W_Last : Ada.Streams.Stream_Element_Offset := 0;
            begin
               Adacraft.Protocol.Buffer.Reset (W);
               Adacraft.Protocol.Login.Encode_Login_Success (W, Ident);
               if not W.Failed and then W.Len > 0 then
                  Adacraft.Protocol.Frame.Write_Length_Prefix
                    (Adacraft.Protocol.Frame.Frame_Body_Length (W.Len),
                     Prefix, P_Last);
                  for I in 1 .. P_Last loop
                     W_Last := W_Last + 1;
                     Wire (W_Last) := Prefix (Integer (I));
                  end loop;
                  for I in 1 .. W.Len loop
                     W_Last := W_Last + 1;
                     Wire (W_Last) :=
                       Ada.Streams.Stream_Element (W.Data (I));
                  end loop;
                  Queue_Bytes (C, Wire (1 .. W_Last));
               end if;
            end;
            C.Proto_State := Adacraft.Protocol.State.Login_Awaiting_Ack;
            C.Last_Activity := Ada.Calendar.Clock;
            return;
         end;
      elsif C.Proto_State = Adacraft.Protocol.State.Login_Awaiting_Ack then
         --  Login_Awaiting_Ack dispatch (in place, same dispatcher, no
         --  second handler). Second Login Start (0x00) -> one framed
         --  Login Disconnect, close. Login Acknowledged (0x03) with
         --  empty payload -> Configuration, no reply. Non-empty Ack
         --  -> one framed Login Disconnect, close, no state change.
         --  Offline only; no Online_Authenticated flag exists or is set.
         --  Explicit close path only (C.Closing), no raise.
         declare
            use type Adacraft.Protocol.State.Packet_Id;
            Start_Id : constant Adacraft.Protocol.State.Packet_Id :=
              Adacraft.Protocol.State.Packet_Id (0);
            Ack_Id   : constant Adacraft.Protocol.State.Packet_Id :=
              Adacraft.Protocol.State.Packet_Id (3);
            Got_Id   : constant Adacraft.Protocol.State.Packet_Id :=
              Adacraft.Protocol.State.Packet_Id (Pid);
            Is_Start : constant Boolean :=
              Adacraft.Protocol.State.Table.Is_Login_Start_Id (Got_Id)
              or else Got_Id = Start_Id;
            Is_Ack   : constant Boolean :=
              Adacraft.Protocol.State.Table.Is_Login_Ack_Id (Got_Id)
              or else Got_Id = Ack_Id;
         begin
            if Is_Start then
               declare
                  Disc : Adacraft.Protocol.Octets :=
                    Adacraft.Protocol.Login.Build_Login_Disconnect
                      (Adacraft.Protocol.Login.Default_Disconnect_Reason);
                  Prefix : Adacraft.Protocol.Frame.Prefix_Buffer;
                  P_Last : Ada.Streams.Stream_Element_Offset;
                  Wire : Adacraft.Protocol.Frame.Byte_Array (1 .. 512) :=
                    (others => 0);
                  W_Last : Ada.Streams.Stream_Element_Offset := 0;
               begin
                  Adacraft.Protocol.Frame.Write_Length_Prefix
                    (Adacraft.Protocol.Frame.Frame_Body_Length (Disc'Length),
                     Prefix, P_Last);
                  for I in 1 .. P_Last loop
                     W_Last := W_Last + 1;
                     Wire (W_Last) := Prefix (Integer (I));
                  end loop;
                  for I in Disc'Range loop
                     W_Last := W_Last + 1;
                     Wire (W_Last) :=
                       Ada.Streams.Stream_Element (Disc (I));
                  end loop;
                  Queue_Bytes (C, Wire (1 .. W_Last));
               end;
               C.Closing := True;
               C.Last_Activity := Ada.Calendar.Clock;
               return;
            elsif Is_Ack then
               if Pay_First > Blen then
                  C.Proto_State := Adacraft.Protocol.State.Configuration;
                  C.Last_Activity := Ada.Calendar.Clock;
                  return;
               else
                  declare
                     Disc : Adacraft.Protocol.Octets :=
                       Adacraft.Protocol.Login.Build_Login_Disconnect
                         (Adacraft.Protocol.Login.Default_Disconnect_Reason);
                     Prefix : Adacraft.Protocol.Frame.Prefix_Buffer;
                     P_Last : Ada.Streams.Stream_Element_Offset;
                     Wire : Adacraft.Protocol.Frame.Byte_Array (1 .. 512) :=
                       (others => 0);
                     W_Last : Ada.Streams.Stream_Element_Offset := 0;
                  begin
                     Adacraft.Protocol.Frame.Write_Length_Prefix
                       (Adacraft.Protocol.Frame.Frame_Body_Length
                          (Disc'Length),
                        Prefix, P_Last);
                     for I in 1 .. P_Last loop
                        W_Last := W_Last + 1;
                        Wire (W_Last) := Prefix (Integer (I));
                     end loop;
                     for I in Disc'Range loop
                        W_Last := W_Last + 1;
                        Wire (W_Last) :=
                          Ada.Streams.Stream_Element (Disc (I));
                     end loop;
                     Queue_Bytes (C, Wire (1 .. W_Last));
                  end;
                  C.Closing := True;
                  C.Last_Activity := Ada.Calendar.Clock;
                  return;
               end if;
            else
               C.Closing := True;
               C.Last_Activity := Ada.Calendar.Clock;
               return;
            end if;
         end;
      else
         --  Configuration onward: not implemented; plain close.
         raise Constraint_Error with "configuration not implemented";
      end if;
      C.Last_Activity := Ada.Calendar.Clock;
   end Handle_Frame_Body;

   procedure Service_Readable (Idx : Positive) is
      C    : Conn_Access;
      Item : Adacraft.Protocol.Frame.Byte_Array (1 .. 2048);
      Last : Ada.Streams.Stream_Element_Offset;
   begin
      if Idx < 1 or else Idx > Max_Conns then
         return;
      end if;
      C := Conn_Table (Idx);
      if C = null or else not C.Has_Sock then
         return;
      end if;
      begin
         GNAT.Sockets.Receive_Socket (C.Sock, Item, Last);
      exception
         when E : GNAT.Sockets.Socket_Error =>
            if Msg_Is_Again (Ada.Exceptions.Exception_Message (E)) then
               return;
            else
               Close_Conn (Idx, "read error");
               return;
            end if;
         when others =>
            Close_Conn (Idx, "read error");
            return;
      end;
      if Last < Item'First then
         --  EOF mid-frame or clean EOF: plain close.
         Close_Conn (Idx, "eof");
         return;
      end if;
      declare
         Got : constant Adacraft.Protocol.Frame.Byte_Array :=
           Item (Item'First .. Last);
         FS : Adacraft.Protocol.Frame.Feed_Status;
         C_Copy : constant Conn_Access := C;
         Idx_Copy : constant Positive := Idx;
         procedure On_Frame (Frame : Adacraft.Protocol.Frame.Byte_Array) is
         begin
            Handle_Frame_Body (C_Copy, Frame);
         end On_Frame;
      begin
         Adacraft.Protocol.Frame.Feed (C.Frame_State, Got, On_Frame'Access, FS);
         --  Feed enforces: VarInt/length prefix <= 3 bytes,
         --  frame <= 2_097_151; overlong/over-max => Framing_Error.
         if FS /= Adacraft.Protocol.Frame.Success then
            Close_Conn (Idx_Copy, "framing error");
            return;
         end if;
      exception
         when E_Info : others =>
            --  Malformed/unknown-id/bad-next-state/truncated => plain close
            --  of only this connection; log the real cause, not a tag.
            Log_One_Line
              ("adacraft_server: closing connection: "
               & Ada.Exceptions.Exception_Information (E_Info));
            if Conn_Table (Idx_Copy) /= null then
               --  Flush any queued reply before closing if present.
               if C_Copy /= null and then C_Copy.Send_Len > 0 then
                  begin
                     Service_Writable (Idx_Copy);
                  exception
                     when others => null;
                  end;
               end if;
               Close_Conn (Idx_Copy, "closing");
            end if;
            return;
      end;
      --  If handler marked closing and everything flushed, close now;
      --  otherwise the writable path / timeout path finishes it.
      if Conn_Table (Idx) /= null and then C.Closing and then C.Send_Len = 0 then
         Close_Conn (Idx, "closing");
      end if;
   end Service_Readable;

   procedure Service_Writable (Idx : Positive) is
      C    : Conn_Access;
      Sent : Ada.Streams.Stream_Element_Offset;
   begin
      if Idx < 1 or else Idx > Max_Conns then
         return;
      end if;
      C := Conn_Table (Idx);
      if C = null or else not C.Has_Sock then
         return;
      end if;
      if C.Send_Len = 0 then
         if C.Closing then
            Close_Conn (Idx, "closing");
         end if;
         return;
      end if;
      declare
         First : constant Ada.Streams.Stream_Element_Offset :=
           Ada.Streams.Stream_Element_Offset (C.Send_Pos);
         Last_I : constant Ada.Streams.Stream_Element_Offset :=
           Ada.Streams.Stream_Element_Offset (C.Send_Pos + C.Send_Len - 1);
      begin
         GNAT.Sockets.Send_Socket (C.Sock, C.Send_Buf (First .. Last_I), Sent);
         if Sent >= First and then Sent <= Last_I then
            declare
               N : constant Natural := Natural (Sent - First + 1);
            begin
               C.Send_Pos := C.Send_Pos + N;
               C.Send_Len := C.Send_Len - N;
               if C.Send_Len = 0 then
                  C.Send_Pos := 1;
               end if;
               C.Last_Activity := Ada.Calendar.Clock;
            end;
         end if;
      exception
         when E : GNAT.Sockets.Socket_Error =>
            if Msg_Is_Again (Ada.Exceptions.Exception_Message (E)) then
               return;
            else
               Close_Conn (Idx, "write error");
               return;
            end if;
         when others =>
            Close_Conn (Idx, "write error");
            return;
      end;
      if C.Send_Len = 0 and then C.Closing then
         Close_Conn (Idx, "closing");
      end if;
   end Service_Writable;

   procedure Accept_Ready (Listener : GNAT.Sockets.Socket_Type) is
      use GNAT.Sockets;
      Client : Socket_Type;
      Peer   : Sock_Addr_Type;
      Slot   : Natural;
   begin
      Accept_Socket (Listener, Client, Peer);
      Slot := Find_Free_Slot;
      if Slot = 0 then
         begin
            Close_Socket (Client);
         exception
            when others => null;
         end;
         return;
      end if;
      begin
         Set_Non_Blocking (Client);
      exception
         when others => null;
      end;
      declare
         C : constant Conn_Access := new Conn;
      begin
         C.Sock := Client;
         C.Has_Sock := True;
         C.Fd_Key := Fd_Of (Client);
         C.Recv_Len := 0;
         C.Proto_State := Adacraft.Protocol.State.Initial_State;
         C.Stored := (others => <>);
         Adacraft.Protocol.Status_Exchange.Reset (C.Sess);
         C.Last_Activity := Ada.Calendar.Clock;
         C.Send_Pos := 1;
         C.Send_Len := 0;
         C.Closing := False;
         C.In_Use := True;
         Conn_Table (Slot) := C;
      exception
         when others =>
            begin
               Close_Socket (Client);
            exception
               when others => null;
            end;
      end;
   exception
      when E : GNAT.Sockets.Socket_Error =>
         if Msg_Is_Again (Ada.Exceptions.Exception_Message (E)) then
            null;
         else
            Log_One_Line ("adacraft_server: accept error");
         end if;
      when others =>
         Log_One_Line ("adacraft_server: accept error");
   end Accept_Ready;

   procedure Initialize_Listener
     (Port     : GNAT.Sockets.Port_Type;
      Listener : out GNAT.Sockets.Socket_Type)
   is
      use GNAT.Sockets;
      Addr : Sock_Addr_Type;
   begin
      Create_Socket (Listener);
      Set_Socket_Option (Listener, Socket_Level, (Reuse_Address, True));
      Addr.Addr := Any_Inet_Addr;
      Addr.Port := Port;
      Bind_Socket (Listener, Addr);
      Listen_Socket (Listener);
   end Initialize_Listener;

   procedure Run_Event_Loop (Listener : GNAT.Sockets.Socket_Type) is
      use GNAT.Sockets;
      Selector : Selector_Type;
      R_Set, W_Set, E_Set : Socket_Set_Type;
      Status : Selector_Status;
      Now    : Ada.Calendar.Time;
   begin
      Create_Selector (Selector);
      loop
         Empty (R_Set);
         Empty (W_Set);
         Empty (E_Set);
         Set (R_Set, Listener);
         for I in 1 .. Max_Conns loop
            if Conn_Table (I) /= null and then Conn_Table (I).Has_Sock then
               begin
                  Set (R_Set, Conn_Table (I).Sock);
                  if Conn_Table (I).Send_Len > 0 then
                     Set (W_Set, Conn_Table (I).Sock);
                  end if;
               exception
                  when others => null;
               end;
            end if;
         end loop;
         begin
            Check_Selector
              (Selector, R_Set, W_Set, E_Set, Status,
               Timeout => Selector_Duration (Selector_Tick));
         exception
            when others =>
               Status := Expired;
         end;
         if Status = Completed then
            if Is_Set (R_Set, Listener) then
               begin
                  Accept_Ready (Listener);
               exception
                  when E : others =>
                     Log_One_Line
                       ("adacraft_server: accept fault: "
                        & Ada.Exceptions.Exception_Name (E));
               end;
            end if;
            for I in 1 .. Max_Conns loop
               if Conn_Table (I) /= null and then Conn_Table (I).Has_Sock then
                  declare
                     S : constant Socket_Type := Conn_Table (I).Sock;
                     R_Hit : Boolean := False;
                     W_Hit : Boolean := False;
                  begin
                     begin
                        R_Hit := Is_Set (R_Set, S);
                     exception
                        when others => R_Hit := False;
                     end;
                     begin
                        W_Hit := Is_Set (W_Set, S);
                     exception
                        when others => W_Hit := False;
                     end;
                     if R_Hit then
                        begin
                           Service_Readable (I);
                        exception
                           when E : others =>
                              begin
                                 Close_Conn (I, "read fault");
                              exception
                                 when others => null;
                              end;
                        end;
                     end if;
                     if Conn_Table (I) /= null
                       and then Conn_Table (I).Has_Sock
                       and then W_Hit
                     then
                        begin
                           Service_Writable (I);
                        exception
                           when E : others =>
                              begin
                                 Close_Conn (I, "write fault");
                              exception
                                 when others => null;
                              end;
                        end;
                     end if;
                  end;
               end if;
            end loop;
         end if;
         --  Reap idle and half-frame conns under the single Read_Timeout.
         Now := Ada.Calendar.Clock;
         for I in 1 .. Max_Conns loop
            if Conn_Table (I) /= null and then Conn_Table (I).Has_Sock then
               begin
                  if Now - Conn_Table (I).Last_Activity > Read_Timeout then
                     Close_Conn (I, "read timeout");
                  end if;
               exception
                  when others => null;
               end;
            end if;
         end loop;
      end loop;
   exception
      when others =>
         --  Selector itself failed; keep process alive by retrying.
         begin
            Close_Selector (Selector);
         exception
            when others => null;
         end;
         Log_One_Line ("adacraft_server: selector fault, restarting loop");
         Run_Event_Loop (Listener);
   end Run_Event_Loop;

   procedure Serve (Port : GNAT.Sockets.Port_Type) is
      use GNAT.Sockets;
      Listener : Socket_Type;
   begin
      Initialize_Listener (Port, Listener);
      Run_Event_Loop (Listener);
   end Serve;

end Adacraft.Network;
