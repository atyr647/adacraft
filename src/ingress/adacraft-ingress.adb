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
                  if Frame.Packet_Id /= Protocol.Ids.Protocol_Id (Protocol.Ids.Sb_Login_Hello) then
                     Close_Now := True;
                  else
                     declare
                        Hello : constant Protocol.Packets.Login_Hello :=
                          Protocol.Packets.Decode_Login_Hello (Payload);
                        Expected : Auth.Digest;
                     begin
                        if Hello.Status /= Protocol.Ok then
                           Disconnect (Outgoing, "Malformed login", Close_Now);
                        else
                           Expected := Auth.Offline_UUID (Hello.Name (1 .. Hello.Name_Len));
                           if not Same_UUID (Hello.Uuid, Expected) then
                              Disconnect (Outgoing, "Offline UUID does not match the player name", Close_Now);
                           else
                              Disconnect
                                (Outgoing,
                                 "AdaCraft accepted the offline identity; play is not in this build",
                                 Close_Now);
                           end if;
                        end if;
                     end;
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
