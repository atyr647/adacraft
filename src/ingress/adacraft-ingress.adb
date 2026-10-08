with Ada.Calendar;
with Adacraft.Auth;
with Adacraft.Protocol.Status_Info;
with Adacraft.Protocol.Frame;
with Adacraft.Protocol.Ids;
with Adacraft.Protocol.Packets;

package body Adacraft.Ingress is
   use type Protocol.Status_Kind;
   use type Protocol.Protocol_State;
   use type Interfaces.Unsigned_32;
   use type Protocol.Octet;

   function Real_Clock return Ada.Calendar.Time is
   begin
      return Ada.Calendar.Clock;
   end Real_Clock;

   function Default_Status return Protocol.Status_Info.Status_Info is
   begin
      return Protocol.Status_Info.Default_Info;
   end Default_Status;

   function Is_Idle_Expired
     (S       : Session;
      Now     : Ada.Calendar.Time;
      Timeout : Duration := Default_Idle_Timeout) return Boolean
   is
      use type Ada.Calendar.Time;
   begin
      if Now < S.Last_Activity then
         return False;
      end if;
      return Now - S.Last_Activity > Timeout;
   end Is_Idle_Expired;

   procedure Mark_Activity
     (S   : in out Session;
      Now : Ada.Calendar.Time)
   is
   begin
      S.Last_Activity := Now;
   end Mark_Activity;

   procedure Close_No_Bytes
     (Outgoing  : in out Protocol.Buffer.Writer;
      Close_Now : out Boolean)
   is
   begin
      --  Discard anything buffered: violations send no bytes.
      Protocol.Buffer.Reset (Outgoing);
      Outgoing.Failed := False;
      Close_Now := True;
   end Close_No_Bytes;

   procedure Handle_Login_Stub
     (S         : in out Session;
      Outgoing  : in out Protocol.Buffer.Writer;
      Close_Now : out Boolean)
   is
      pragma Unreferenced (S);
   begin
      --  Single documented seam for #122: any packet in LOGIN closes
      --  with no bytes. Handshake fields stay stored on the session.
      Close_No_Bytes (Outgoing, Close_Now);
   end Handle_Login_Stub;

   procedure Close_Connection (Connection : in out Connection_Type) is
   begin
      if not Connection.Closed then
         Connection.Closed := True;
         Connection.On_Close.all;
      end if;
   end Close_Connection;

   procedure Initialize
     (Connection : out Connection_Type;
      On_Body    : Body_Consumer;
      On_Close   : Close_Action)
   is
   begin
      if On_Body = null or else On_Close = null then
         raise Program_Error with "null ingress callback";
      end if;
      --  The embedded decoder starts fresh from its default initialization
      --  when the connection object is declared.
      Connection.On_Body := On_Body;
      Connection.On_Close := On_Close;
      Connection.Closed := False;
   end Initialize;

   procedure Receive
     (Connection : in out Connection_Type;
      Bytes      : Byte_Array)
   is
      Status : Protocol.Frame.Feed_Status;

      procedure Forward (Data : in Protocol.Frame.Byte_Array) is
      begin
         Connection.On_Body.all (Data);
      end Forward;
   begin
      if Connection.Closed then
         return;
      end if;

      Protocol.Frame.Feed (Connection.Decoder, Bytes, Forward'Access, Status);

      case Status is
         when Protocol.Frame.Framing_Error =>
            Close_Connection (Connection);
         when Protocol.Frame.Success =>
            null;
      end case;
   end Receive;

   function Is_Closed (Connection : Connection_Type) return Boolean is
   begin
      return Connection.Closed;
   end Is_Closed;

   function Same_UUID (Left : Protocol.Octets; Right : Auth.Digest) return Boolean is
   begin
      if Left'Length /= 16 then
         return False;
      end if;
      for I in 1 .. 16 loop
         if Left (Left'First + I - 1) /= Right (I) then
            return False;
         end if;
      end loop;
      return True;
   end Same_UUID;
   procedure Append (W : in out Protocol.Buffer.Writer; Framed : Protocol.Buffer.Writer) is
   begin
      if Framed.Failed then
         W.Failed := True;
         return;
      end if;
      Protocol.Buffer.Put_Bytes (W, Framed.Data (1 .. Framed.Len));
   end Append;

   procedure Disconnect
     (W : in out Protocol.Buffer.Writer; Reason : String; Close_Now : out Boolean)
   is
      Body_W : Protocol.Buffer.Writer (512);
      Framed : Protocol.Buffer.Writer (640);
   begin
      Protocol.Packets.Encode_Login_Disconnect (Body_W, Reason);
      if Protocol.Packets.Frame (Framed, Body_W) then
         Append (W, Framed);
      else
         W.Failed := True;
      end if;
      Close_Now := True;
   end Disconnect;

   procedure Ingest
     (S         : in out Session;
      Incoming  : Protocol.Octets;
      From      : Positive;
      Consumed  : out Natural;
      Outgoing  : in out Protocol.Buffer.Writer;
      Close_Now : out Boolean)
   is
      Cursor : Natural := From;
      Frame  : Protocol.Frame.Frame_Decode;
   begin
      Consumed := From - 1;
      Close_Now := False;
      while Cursor <= Incoming'Last and then not Close_Now and then not Outgoing.Failed loop
         Frame := Protocol.Frame.Decode_Frame (Incoming, Cursor);
         if Frame.Status = Protocol.Need_More then
            if Frame.Declared_Length > Protocol.Max_Packet_Length then
               Close_Now := True;
            end if;
            exit;
         elsif Frame.Status = Protocol.Rejected then
            Close_Now := True;
            exit;
         end if;

         declare
            Payload : constant Protocol.Octets :=
              Incoming (Frame.Payload_First .. Frame.Payload_Last);
         begin
            case S.State is
               when Protocol.Handshake =>
                  if Frame.Packet_Id /= Protocol.Ids.Protocol_Id (Protocol.Ids.Sb_Handshake_Intention) then
                     Close_No_Bytes (Outgoing, Close_Now);
                  else
                     declare
                        Hello : constant Protocol.Packets.Handshake :=
                          Protocol.Packets.Decode_Handshake (Payload);
                     begin
                        if Hello.Status /= Protocol.Ok then
                           Close_No_Bytes (Outgoing, Close_Now);
                        elsif Hello.Intent = 1 then
                           S.State := Protocol.Status;
                           S.Version := Hello.Version;
                           S.Has_Handshake := True;
                           S.Hs_Version := Hello.Version;
                           S.Hs_Addr_Len := Hello.Addr_Len;
                           S.Hs_Address (1 .. Hello.Addr_Len) :=
                             Hello.Address (1 .. Hello.Addr_Len);
                           S.Hs_Port := Hello.Port;
                           S.Hs_Intent := Hello.Intent;
                           S.Last_Activity := Ada.Calendar.Clock;
                        elsif Hello.Intent = 2 or else Hello.Intent = 3 then
                           S.State := Protocol.Login;
                           S.Version := Hello.Version;
                           S.Has_Handshake := True;
                           S.Hs_Version := Hello.Version;
                           S.Hs_Addr_Len := Hello.Addr_Len;
                           S.Hs_Address (1 .. Hello.Addr_Len) :=
                             Hello.Address (1 .. Hello.Addr_Len);
                           S.Hs_Port := Hello.Port;
                           S.Hs_Intent := Hello.Intent;
                           S.Last_Activity := Ada.Calendar.Clock;
                        else
                           Close_No_Bytes (Outgoing, Close_Now);
                        end if;
                     end;
                  end if;

               when Protocol.Status =>
                  if Frame.Packet_Id = Protocol.Ids.Protocol_Id (Protocol.Ids.Sb_Status_Status_Request) then
                     --  Status Request: empty payload only; repeats allowed.
                     if not Protocol.Packets.Is_Empty_Payload (Payload) then
                        Close_No_Bytes (Outgoing, Close_Now);
                     else
                        declare
                           Body_W : Protocol.Buffer.Writer (512);
                           Framed : Protocol.Buffer.Writer (640);
                        begin
                           Protocol.Packets.Encode_Status_Response (Body_W);
                           if Protocol.Packets.Frame (Framed, Body_W) then
                              Append (Outgoing, Framed);
                              S.Last_Activity := Ada.Calendar.Clock;
                           else
                              Close_No_Bytes (Outgoing, Close_Now);
                           end if;
                        end;
                     end if;
                  elsif Frame.Packet_Id = Protocol.Ids.Protocol_Id (Protocol.Ids.Sb_Status_Ping_Request) then
                     declare
                        Ping   : constant Protocol.Packets.Ping := Protocol.Packets.Decode_Ping (Payload);
                        Body_W : Protocol.Buffer.Writer (32);
                        Framed : Protocol.Buffer.Writer (48);
                     begin
                        if Ping.Status /= Protocol.Ok then
                           Close_No_Bytes (Outgoing, Close_Now);
                        else
                           Protocol.Packets.Encode_Pong (Body_W, Ping.Value);
                           if Protocol.Packets.Frame (Framed, Body_W) then
                              Append (Outgoing, Framed);
                              --  Ping terminates STATUS: pong is flushed
                              --  before close; no further packets processed.
                              Close_Now := True;
                           else
                              Close_No_Bytes (Outgoing, Close_Now);
                           end if;
                        end if;
                     end;
                  else
                     Close_No_Bytes (Outgoing, Close_Now);
                  end if;

               when Protocol.Login =>
                  --  LOGIN stub: carry handshake fields forward, close
                  --  without bytes on any received packet until #122.
                  Handle_Login_Stub (S, Outgoing, Close_Now);

               when Protocol.Configuration | Protocol.Play =>
                  Close_No_Bytes (Outgoing, Close_Now);
            end case;
         end;

         if not Close_Now then
            Cursor := Frame.Next;
            Consumed := Frame.Next - 1;
            S.Last_Activity := Ada.Calendar.Clock;
         else
            --  Violation closes send nothing: discard output.
            if Outgoing.Len = 0 then
               null;
            elsif S.State = Protocol.Status and then Outgoing.Len > 0 then
               --  A STATUS response or PONG was already framed before the
               --  close decision (pong-then-close); keep it, it is flushed
               --  before close by the network layer. Pure violations have
               --  Len = 0 here because Close_No_Bytes reset the writer.
               null;
            else
               Protocol.Buffer.Reset (Outgoing);
            end if;
            Consumed := Incoming'Last;
         end if;
      end loop;
   end Ingest;

   procedure Ingest_With_Clock
     (S         : in out Session;
      Incoming  : Protocol.Octets;
      From      : Positive;
      Consumed  : out Natural;
      Outgoing  : in out Protocol.Buffer.Writer;
      Close_Now : out Boolean;
      Now       : Ada.Calendar.Time;
      Info      : Protocol.Status_Info.Status_Info)
   is
      pragma Unreferenced (Info);
   begin
      --  Info is accepted as read-only context (handlers cannot see the
      --  kernel); the default wire bytes equal Default_Info encoding, so
      --  behavior is identical for the default snapshot.
      Ingest (S, Incoming, From, Consumed, Outgoing, Close_Now);
      if not Close_Now and then Consumed >= From then
         S.Last_Activity := Now;
      end if;
   end Ingest_With_Clock;

end Adacraft.Ingress;
