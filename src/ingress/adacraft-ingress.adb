with Ada.Streams;
with Adacraft.Auth;
with Adacraft.Kernel;
with Adacraft.Protocol.Frame;
with Adacraft.Protocol.Ids;
with Adacraft.Protocol.Login;
with Adacraft.Protocol.Packet_Encoder;
with Adacraft.Protocol.Packets;
with Adacraft.Protocol.State;

package body Adacraft.Ingress is
   use type Protocol.Status_Kind;
   use type Interfaces.Unsigned_32;
   use type Protocol.Octet;
   use type Ada.Streams.Stream_Element_Offset;
   use type Protocol.Login.Login_State;
   use type Protocol.Login.Ack_Outcome;

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

   procedure Append_Login_Packet
     (W : in out Protocol.Buffer.Writer;
      E : in out Protocol.Packet_Encoder.Encoder_Type)
   is
      Encoded : Ada.Streams.Stream_Element_Array (1 .. 1_024);
      Last    : Ada.Streams.Stream_Element_Offset;
      Bytes   : Protocol.Octets (1 .. 1_024) := (others => 0);
   begin
      Protocol.Packet_Encoder.Get_Framed (E, Encoded, Last);
      if Protocol.Packet_Encoder.Has_Failed (E) or else Last < Encoded'First then
         W.Failed := True;
         return;
      end if;
      for I in 1 .. Natural (Last) loop
         Bytes (I) := Protocol.Octet (Encoded (Ada.Streams.Stream_Element_Offset (I)));
      end loop;
      Protocol.Buffer.Put_Bytes (W, Bytes (1 .. Natural (Last)));
   end Append_Login_Packet;

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
                     Close_Now := True;
                  else
                     declare
                        Hello : constant Protocol.Packets.Handshake :=
                          Protocol.Packets.Decode_Handshake (Payload);
                     begin
                        if Hello.Status /= Protocol.Ok then
                           Close_Now := True;
                        elsif Hello.Intent = 1 then
                           S.State := Protocol.Status;
                           S.Version := Hello.Version;
                        elsif Hello.Intent = 2 and then Hello.Version = Adacraft.Protocol_Version then
                           S.State := Protocol.Login_Phase;
                           S.Version := Hello.Version;
                        elsif Hello.Intent = 2 then
                           S.State := Protocol.Login_Phase;
                           S.Version := Hello.Version;
                           Disconnect (Outgoing, "This server is Minecraft 26.3, protocol 777", Close_Now);
                        else
                           Close_Now := True;
                        end if;
                     end;
                  end if;

               when Protocol.Status =>
                  if Frame.Packet_Id = Protocol.Ids.Protocol_Id (Protocol.Ids.Sb_Status_Status_Request) then
                     declare
                        Body_W : Protocol.Buffer.Writer (512);
                        Framed : Protocol.Buffer.Writer (640);
                     begin
                        Protocol.Packets.Encode_Status_Response (Body_W);
                        if Protocol.Packets.Frame (Framed, Body_W) then
                           Append (Outgoing, Framed);
                        else
                           Close_Now := True;
                        end if;
                     end;
                  elsif Frame.Packet_Id = Protocol.Ids.Protocol_Id (Protocol.Ids.Sb_Status_Ping_Request) then
                     declare
                        Ping   : constant Protocol.Packets.Ping := Protocol.Packets.Decode_Ping (Payload);
                        Body_W : Protocol.Buffer.Writer (32);
                        Framed : Protocol.Buffer.Writer (48);
                     begin
                        if Ping.Status /= Protocol.Ok then
                           Close_Now := True;
                        else
                           Protocol.Packets.Encode_Pong (Body_W, Ping.Value);
                           if Protocol.Packets.Frame (Framed, Body_W) then
                              Append (Outgoing, Framed);
                           else
                              Close_Now := True;
                           end if;
                        end if;
                     end;
                  else
                     Close_Now := True;
                  end if;

               when Protocol.Login_Phase =>
                  declare
                     Dispatch_State : constant Protocol.State.Connection_State :=
                       (if S.Login_State.State = Protocol.Login.Success_Sent
                        then Protocol.State.Login_Awaiting_Ack
                        else Protocol.State.Login);
                     Dispatch : constant Protocol.State.Login_Dispatch :=
                       Protocol.State.Dispatch_Login
                         (Dispatch_State, Protocol.State.Serverbound,
                          Protocol.State.Packet_Id (Frame.Packet_Id));
                  begin
                     case Dispatch is
                        when Protocol.State.Dispatch_Start =>
                           declare
                              Mode : constant Auth.Server_Auth_Mode :=
                                (if Adacraft.Kernel.Online_Mode
                                 then Auth.Online else Auth.Offline);
                              Result : constant Protocol.Login.Start_Result :=
                                Protocol.Login.Handle_Start
                                  (S.Login_State, Payload, Mode);
                              Encoder : Protocol.Packet_Encoder.Encoder_Type
                                (Capacity => 512);
                           begin
                              case Result.Outcome is
                                 when Protocol.Login.Ready_Success =>
                                    S.Login_State := Result.Session;
                                    Protocol.Packet_Encoder.Encode_Login_Success
                                      (Encoder,
                                       Protocol.Octets (Result.Identity.UUID),
                                       Result.Identity.Name
                                         (1 .. Result.Identity.Name_Length));
                                    Append_Login_Packet (Outgoing, Encoder);
                                 when Protocol.Login.Need_Disconnect_Close
                                    | Protocol.Login.Refuse_Online =>
                                    S.Login_State := Result.Session;
                                    Protocol.Packet_Encoder.Encode_Login_Disconnect
                                      (Encoder,
                                       Result.Reason (1 .. Result.Reason_Len));
                                    Append_Login_Packet (Outgoing, Encoder);
                                    Close_Now := True;
                                 when Protocol.Login.Protocol_Error_Close =>
                                    S.Login_State := Result.Session;
                                    Close_Now := True;
                              end case;
                           end;

                        when Protocol.State.Dispatch_Acknowledged =>
                           declare
                              Result : constant Protocol.Login.Ack_Result :=
                                Protocol.Login.Handle_Acknowledged
                                  (S.Login_State, Payload);
                           begin
                              if Result.Outcome =
                                Protocol.Login.To_Configuration
                              then
                                 S.Login_State := Result.Session;
                                 S.State := Protocol.Configuration;
                              else
                                 S.Login_State := Result.Session;
                                 Close_Now := True;
                              end if;
                           end;

                        when Protocol.State.Dispatch_Reject =>
                           Close_Now := True;

                        when Protocol.State.Dispatch_Encryption_Response =>
                           Close_Now := True;
                     end case;
                  end;

               when Protocol.Configuration | Protocol.Play =>
                  Close_Now := True;
            end case;
         end;

         if not Close_Now then
            Cursor := Frame.Next;
            Consumed := Frame.Next - 1;
         else
            Consumed := Incoming'Last;
         end if;
      end loop;
   end Ingest;
end Adacraft.Ingress;
