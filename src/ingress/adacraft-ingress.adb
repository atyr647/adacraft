with Adacraft.Auth;
with Adacraft.Protocol.Buffer;
with Adacraft.Protocol.Frame;
with Adacraft.Protocol.Handshake_Exchange;
with Adacraft.Protocol.Ids;
with Adacraft.Protocol.Packets;
with Adacraft.Protocol.State;
with Adacraft.Protocol.Status_Exchange;

package body Adacraft.Ingress is
   use type Protocol.Status_Kind;
   use type Protocol.Octet;
   use type Protocol.State.Connection_State;
   use type Protocol.Handshake_Exchange.Disposition_Kind;
   use type Protocol.Status_Exchange.Disposition_Kind;

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
            Packet : constant Protocol.Octets :=
              Incoming (Frame.Payload_First .. Frame.Payload_Last);
         begin
            case S.State is
               when Protocol.State.Handshake =>
                  declare
                     Disposition : Protocol.Handshake_Exchange.Disposition_Kind;
                     Client_Version : Natural;
                  begin
                     Protocol.Handshake_Exchange.Handle
                       (Input => Packet,
                        Current_State => S.State,
                        Client_Version => Client_Version,
                        Disposition => Disposition,
                        Output => Outgoing);
                     if Disposition =
                       Protocol.Handshake_Exchange.Silent_Close
                     then
                        Close_Now := True;
                     else
                        S.Version := Client_Version;
                     end if;
                  end;

               when Protocol.State.Status =>
                  declare
                     Disposition : Protocol.Status_Exchange.Disposition_Kind;
                  begin
                     Protocol.Status_Exchange.Handle
                       (Input => Packet,
                        Current_State => S.State,
                        Status_Sent => S.Status_Sent,
                        Disposition => Disposition,
                        Output => Outgoing);
                     case Disposition is
                        when Protocol.Status_Exchange.Progress =>
                           null;
                        when Protocol.Status_Exchange.Close_After_Send =>
                           Close_Now := True;
                        when Protocol.Status_Exchange.Silent_Close =>
                           Close_Now := True;
                     end case;
                  end;

               when Protocol.State.Login =>
                  if Packet'Length = 0
                    or else Natural (Packet (Packet'First)) /=
                      Protocol.Ids.Protocol_Id (Protocol.Ids.Sb_Login_Hello)
                  then
                     Close_Now := True;
                  elsif Packet'Length = 1 then
                     Disconnect (Outgoing, "Malformed login", Close_Now);
                  else
                     declare
                        Payload : constant Protocol.Octets :=
                          Packet (Packet'First + 1 .. Packet'Last);
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

               when others =>
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
