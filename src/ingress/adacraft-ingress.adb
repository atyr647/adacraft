with Adacraft.Auth;
with Adacraft.Protocol.Frame;
with Adacraft.Protocol.Ids;
with Adacraft.Protocol.Packets;

package body Adacraft.Ingress is
   use type Protocol.Status_Kind;
   use type Interfaces.Unsigned_32;
   use type Protocol.Octet;

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
                           S.State := Protocol.Login;
                           S.Version := Hello.Version;
                        elsif Hello.Intent = 2 then
                           S.State := Protocol.Login;
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

               when Protocol.Login =>
                  if Frame.Packet_Id = Protocol.Ids.Protocol_Id (Protocol.Ids.Sb_Login_Hello) then
                     --  Second Login Start is always rejected, even after
                     --  Success was sent; no state change, no further bytes.
                     if S.Start_Seen or else S.Success_Sent then
                        Close_Now := True;
                     else
                        declare
                           Start : constant Protocol.Packets.Login_Start :=
                             Protocol.Packets.Decode_Login_Start (Payload);
                        begin
                           if Start.Status /= Protocol.Ok then
                              --  Truncated, bad length, or trailing bytes:
                              --  close with no Success.
                              Close_Now := True;
                           else
                              declare
                                 Name      : constant String :=
                                   Start.Name (1 .. Start.Name_Len);
                                 Name_Ok   : Boolean := True;
                                 Identity  : Auth.Digest;
                                 Body_W    : Protocol.Buffer.Writer (64);
                                 Framed    : Protocol.Buffer.Writer (96);
                                 Name_Copy : String (1 .. 16) := (others => ' ');
                              begin
                                 if Start.Name_Len < 1 or else Start.Name_Len > 16 then
                                    Name_Ok := False;
                                 else
                                    for Ch of Name loop
                                       if Character'Pos (Ch) < 16#21#
                                         or else Character'Pos (Ch) > 16#7E#
                                       then
                                          Name_Ok := False;
                                          exit;
                                       end if;
                                    end loop;
                                 end if;
                                 if not Name_Ok then
                                    Disconnect (Outgoing, "invalid player name", Close_Now);
                                 elsif Auth.Online_Mode then
                                    Disconnect
                                      (Outgoing,
                                       "online authentication is unavailable",
                                       Close_Now);
                                 else
                                    --  Offline mode: client UUID is decoded
                                    --  but never used. Derive vanilla
                                    --  UUIDv3 and send exactly one Success.
                                    --  No Encryption Request, no Set
                                    --  Compression. Record the identity as
                                    --  offline/unauthenticated.
                                    S.Identity := Auth.Offline_Identity_For_Name (Name);
                                    Identity := S.Identity.UUID;
                                    Name_Copy (1 .. Start.Name_Len) := Name;
                                    Protocol.Packets.Encode_Login_Success
                                      (Body_W,
                                       Protocol.Octets (Identity),
                                       Name_Copy (1 .. Start.Name_Len));
                                    if Body_W.Failed then
                                       Close_Now := True;
                                    elsif Protocol.Packets.Frame (Framed, Body_W) then
                                       Append (Outgoing, Framed);
                                       if Outgoing.Failed then
                                          Close_Now := True;
                                       else
                                          S.Start_Seen := True;
                                          S.Success_Sent := True;
                                       end if;
                                    else
                                       Close_Now := True;
                                    end if;
                                 end if;
                              end;
                           end if;
                        end;
                     end if;
                  elsif Frame.Packet_Id =
                    Protocol.Ids.Protocol_Id (Protocol.Ids.Sb_Login_Login_Acknowledged)
                  then
                     --  Ack is only valid after Success was sent.
                     if not S.Success_Sent then
                        Close_Now := True;
                     else
                        declare
                           Ack : constant Protocol.Packets.Login_Acknowledged :=
                             Protocol.Packets.Decode_Login_Acknowledged (Payload);
                        begin
                           if Ack.Status /= Protocol.Ok then
                              Close_Now := True;
                           else
                              --  Rest in CONFIGURATION; send nothing.
                              S.State := Protocol.Configuration;
                           end if;
                        end;
                     end if;
                  else
                     --  Wrong-state / unknown ID in LOGIN: close, no change.
                     Close_Now := True;
                  end if;

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
