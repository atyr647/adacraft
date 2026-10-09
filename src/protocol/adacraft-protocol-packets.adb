with Adacraft.Auth;
with Adacraft.Protocol.Buffer;
with Adacraft.Protocol.Ids;
with Adacraft.Protocol.Login;
with Adacraft.Protocol.State;
with Adacraft.Protocol.Varnum;
with Interfaces;

package body Adacraft.Protocol.Packets is
   function Decode_Handshake (Payload : Octets) return Handshake is
      Result  : Handshake;
      Version : Varnum.Varint_Result;
      Address : Buffer.String_Decode;
      Intent  : Varnum.Varint_Result;
   begin
      if Payload'Length = 0 then
         Result.Status := Rejected;
         return Result;
      end if;
      Version := Varnum.Decode_Varint (Payload, Payload'First);
      if Version.Status /= Ok then
         Result.Status := Version.Status;
         return Result;
      end if;
      Address := Buffer.Decode_String (Payload, Version.Next, 255);
      if Address.Status /= Ok then
         Result.Status := Rejected;
         return Result;
      end if;
      if Address.Next > Payload'Last or else Payload'Last - Address.Next < 1 then
         Result.Status := Rejected;
         return Result;
      end if;
      if Address.Next > Natural'Last - 2
        or else Address.Next + 2 > Payload'Last + 1
      then
         Result.Status := Rejected;
         return Result;
      end if;
      Intent := Varnum.Decode_Varint (Payload, Address.Next + 2);
      if Intent.Status /= Ok or else Intent.Next /= Payload'Last + 1 then
         Result.Status := Rejected;
         return Result;
      end if;
      Result.Status := Ok;
      Result.Version := Version.Value;
      Result.Addr_Len := Address.Length;
      Result.Address (1 .. Address.Length) := Address.Text (1 .. Address.Length);
      Result.Port := Buffer.Decode_U16 (Payload, Address.Next);
      Result.Intent := Intent.Value;
      Result.Next := Intent.Next;
      return Result;
   end Decode_Handshake;

   procedure Encode_Status_Response (W : in out Buffer.Writer) is
      JSON : constant String :=
        "{""version"":{""name"":""26.3"",""protocol"":777},"
        & """players"":{""max"":20,""online"":0},"
        & """description"":{""text"":""AdaCraft""}}";
   begin
      Buffer.Put_Varint (W, Interfaces.Unsigned_32 (Ids.Protocol_Id (Ids.Cb_Status_Status_Response)));
      Buffer.Put_String (W, JSON);
   end Encode_Status_Response;

   procedure Encode_Pong (W : in out Buffer.Writer; Payload : Interfaces.Unsigned_64) is
   begin
      Buffer.Put_Varint (W, Interfaces.Unsigned_32 (Ids.Protocol_Id (Ids.Cb_Status_Pong_Response)));
      Buffer.Put_U64 (W, Payload);
   end Encode_Pong;

   procedure Encode_Login_Disconnect (W : in out Buffer.Writer; Reason : String) is
      JSON : constant String := "{""text"":""" & Reason & """}";
   begin
      Buffer.Put_Varint
        (W, Interfaces.Unsigned_32 (Ids.Protocol_Id (Ids.Cb_Login_Login_Disconnect)));
      Buffer.Put_String (W, JSON);
   end Encode_Login_Disconnect;

   function Frame (W : in out Buffer.Writer; Payload : Buffer.Writer) return Boolean is
   begin
      if Payload.Failed or else Payload.Len = 0 then
         return False;
      end if;
      Buffer.Reset (W);
      Buffer.Put_Varint (W, Interfaces.Unsigned_32 (Payload.Len));
      Buffer.Put_Bytes (W, Payload.Data (1 .. Payload.Len));
      return not W.Failed;
   end Frame;

   function Decode_Ping (Payload : Octets) return Ping is
   begin
      if not Buffer.U64_Ok (Payload, Payload'First) or else Payload'Length /= 8 then
         return (Status => Rejected, Value => 0);
      end if;
      return (Status => Ok, Value => Buffer.Decode_U64 (Payload, Payload'First));
   end Decode_Ping;

   function Decode_Login_Hello (Payload : Octets) return Login_Hello is
      Result : Login_Hello;
      Name   : Buffer.String_Decode;
   begin
      if Payload'Length = 0 then
         Result.Status := Rejected;
         return Result;
      end if;
      Name := Buffer.Decode_String (Payload, Payload'First, 16);
      if Name.Status /= Ok or else Name.Length = 0 then
         Result.Status := Rejected;
         return Result;
      end if;
      if Name.Next > Payload'Last or else Payload'Last - Name.Next + 1 /= 16 then
         Result.Status := Rejected;
         return Result;
      end if;
      Result.Status := Ok;
      Result.Name_Len := Name.Length;
      Result.Name (1 .. Name.Length) := Name.Text (1 .. Name.Length);
      for I in 1 .. 16 loop
         Result.Uuid (I) := Payload (Name.Next + I - 1);
      end loop;
      return Result;
   end Decode_Login_Hello;

   function Decode_Login_Start (Payload : Octets) return Login_Start is
      Hello  : constant Login_Hello := Decode_Login_Hello (Payload);
      Result : Login_Start;
   begin
      Result.Status := Hello.Status;
      Result.Name := Hello.Name;
      Result.Name_Len := Hello.Name_Len;
      Result.Uuid := Hello.Uuid;
      return Result;
   end Decode_Login_Start;

   function Decode_Login_Acknowledged
     (Payload : Octets) return Login_Acknowledged
   is
   begin
      if Payload'Length = 0 then
         return (Status => Ok);
      else
         return (Status => Rejected);
      end if;
   end Decode_Login_Acknowledged;

   procedure Encode_Encryption_Request
     (W       : in out Buffer.Writer;
      Req     : in     Encryption_Request;
      Success : out Boolean)
   is
      use type Interfaces.Unsigned_32;
   begin
      Buffer.Reset (W);
      Buffer.Put_Varint
        (W, Interfaces.Unsigned_32
          (Ids.Protocol_Id (Ids.Cb_Login_Hello)));
      if Req.Server_Id_Len = 0 then
         Buffer.Put_String (W, "");
      else
         Buffer.Put_String (W, Req.Server_Id (1 .. Req.Server_Id_Len));
      end if;
      Buffer.Put_Varint (W, Interfaces.Unsigned_32 (Req.Public_Len));
      if Req.Public_Len > 0 then
         Buffer.Put_Bytes (W, Req.Public_Key (1 .. Req.Public_Len));
      end if;
      Buffer.Put_Varint (W, Interfaces.Unsigned_32 (Req.Token_Len));
      if Req.Token_Len > 0 then
         Buffer.Put_Bytes (W, Req.Verify_Token (1 .. Req.Token_Len));
      end if;
      Success := not W.Failed;
   end Encode_Encryption_Request;

   function Decode_Encryption_Response
     (Payload : Octets) return Encryption_Response
   is
      use type Interfaces.Unsigned_32;
      Result : Encryption_Response;
      S_Len  : Varnum.Varint_Result;
      T_Len  : Varnum.Varint_Result;
      Pos    : Natural;
   begin
      if Payload'Length = 0 then
         Result.Status := Rejected;
         return Result;
      end if;
      S_Len := Varnum.Decode_Varint (Payload, Payload'First);
      if S_Len.Status /= Ok then
         Result.Status := S_Len.Status;
         return Result;
      end if;
      if S_Len.Value > Interfaces.Unsigned_32 (Max_Secret_Blob) then
         Result.Status := Rejected;
         return Result;
      end if;
      Pos := S_Len.Next;
      if Natural (S_Len.Value) > 0 then
         if Pos > Payload'Last
           or else Payload'Last - Pos + 1 < Natural (S_Len.Value)
         then
            Result.Status := Rejected;
            return Result;
         end if;
         Result.Secret_Len := Natural (S_Len.Value);
         for I in 1 .. Result.Secret_Len loop
            Result.Secret (I) := Payload (Pos + I - 1);
         end loop;
         Pos := Pos + Result.Secret_Len;
      else
         Result.Secret_Len := 0;
      end if;
      if Pos > Payload'Last then
         Result.Status := Rejected;
         return Result;
      end if;
      T_Len := Varnum.Decode_Varint (Payload, Pos);
      if T_Len.Status /= Ok then
         Result.Status := T_Len.Status;
         return Result;
      end if;
      if T_Len.Value > Interfaces.Unsigned_32 (Max_Token_Blob) then
         Result.Status := Rejected;
         return Result;
      end if;
      Pos := T_Len.Next;
      if Natural (T_Len.Value) > 0 then
         if Pos > Payload'Last
           or else Payload'Last - Pos + 1 < Natural (T_Len.Value)
         then
            Result.Status := Rejected;
            return Result;
         end if;
         Result.Token_Len := Natural (T_Len.Value);
         for I in 1 .. Result.Token_Len loop
            Result.Token (I) := Payload (Pos + I - 1);
         end loop;
         Pos := Pos + Result.Token_Len;
      else
         Result.Token_Len := 0;
      end if;
      if Pos /= Payload'Last + 1 then
         Result.Status := Rejected;
         return Result;
      end if;
      Result.Status := Ok;
      Result.Next := Pos;
      return Result;
   end Decode_Encryption_Response;

   function Decrypt_And_Verify
     (Resp           : Encryption_Response;
      Expected_Token : Octets) return Verify_Result
   is
      use type Interfaces.Unsigned_8;
      use type Adacraft.Protocol.Octet;
      Result : Verify_Result;
   begin
      if Resp.Status /= Ok then
         Result.Status := Malformed;
         Result.Reason_Len := Malformed_Key_Reason'Length;
         Result.Reason (1 .. Result.Reason_Len) := Malformed_Key_Reason;
         return Result;
      end if;
      --  Injected/deterministic seam: plaintext-length blobs carry the
      --  raw 16-byte secret and raw token. Anything else is a wrong
      --  length / malformed secret for this wiring item and rejects
      --  without creating ciphers.
      if Resp.Secret_Len /= Shared_Secret_Length then
         Result.Status := Malformed;
         Result.Reason_Len := Malformed_Key_Reason'Length;
         Result.Reason (1 .. Result.Reason_Len) := Malformed_Key_Reason;
         return Result;
      end if;
      if Resp.Token_Len /= Expected_Token'Length
        or else Resp.Token_Len = 0
      then
         Result.Status := Bad_Token;
         Result.Reason_Len := Bad_Token_Reason'Length;
         Result.Reason (1 .. Result.Reason_Len) := Bad_Token_Reason;
         return Result;
      end if;
      for I in 1 .. Resp.Token_Len loop
         if Resp.Token (I) /= Expected_Token (Expected_Token'First + I - 1)
         then
            Result.Status := Bad_Token;
            Result.Reason_Len := Bad_Token_Reason'Length;
            Result.Reason (1 .. Result.Reason_Len) := Bad_Token_Reason;
            return Result;
         end if;
      end loop;
      Result.Status := Ok;
      for I in 1 .. Shared_Secret_Length loop
         Result.Secret (I) := Resp.Secret (I);
      end loop;
      Result.Reason_Len := 0;
      return Result;
   end Decrypt_And_Verify;

   procedure Leftover_Bounds
     (Consumed : in     Natural;
      Last     : in     Natural;
      First    :    out Natural;
      Count    :    out Natural)
   is
   begin
      --  Leftover rule: bytes Rx_Buffer(Consumed + 1 .. Last) already
      --  buffered past the end of the Encryption Response frame in the
      --  same read are run through Decrypt before re-entering framing.
      if Last > Consumed then
         First := Consumed + 1;
         Count := Last - Consumed;
      else
         First := Last + 1;
         Count := 0;
      end if;
   end Leftover_Bounds;

   procedure Set_Reason
     (Buf : in out String; Len : in out Natural; R : String)
   is
   begin
      Len := (if R'Length > Buf'Length then Buf'Length else R'Length);
      for I in 1 .. Len loop
         Buf (I) := R (R'First + I - 1);
      end loop;
   end Set_Reason;

   function Handle_Login_Start
     (Session     : Login.Login_Session;
      Payload     : Octets;
      Online_Mode : Boolean;
      Public_Key  : Octets;
      Token       : Octets) return Start_Dispatch_Result
   is
      use type State.Connection_State;
      Result : Start_Dispatch_Result;
      Dec    : constant Login_Start := Decode_Login_Start (Payload);
   begin
      if Dec.Status /= Ok then
         Result.Outcome := Need_Disconnect_Close;
         Result.Session :=
           (State => Login.Closed, Success_Sent => False,
            Has_Identity => False,
            Identity =>
              (Kind => Auth.Offline, UUID => (others => 0),
               Name_Length => 0, Name => (others => ' ')));
         Result.Next_State := State.Login;
         Result.Has_Request := False;
         if Dec.Status = Rejected then
            Set_Reason
              (Result.Reason, Result.Reason_Len,
               Login.Malformed_Start_Reason);
         else
            Set_Reason
              (Result.Reason, Result.Reason_Len,
               Login.Invalid_Name_Reason);
         end if;
         return Result;
      end if;
      if not Online_Mode then
         --  R1.2 / criterion 2: existing #212 offline path unchanged,
         --  no Encryption Request, stream stays plaintext.
         declare
            Mode : constant Auth.Server_Auth_Mode := Auth.Offline;
            R    : constant Login.Start_Result :=
              Login.Handle_Start (Session, Payload, Mode);
         begin
            Result.Session := R.Session;
            Result.Identity := R.Identity;
            Result.Next_State := State.Login;
            Result.Has_Request := False;
            case R.Outcome is
               when Login.Ready_Success =>
                  Result.Outcome := Send_Login_Success;
                  Result.Reason_Len := 0;
               when Login.Need_Disconnect_Close =>
                  Result.Outcome := Need_Disconnect_Close;
                  Set_Reason
                    (Result.Reason, Result.Reason_Len,
                     R.Reason (1 .. R.Reason_Len));
               when Login.Protocol_Error_Close
                  | Login.Refuse_Online =>
                  Result.Outcome := Protocol_Error_Close;
                  Result.Reason_Len := 0;
            end case;
            return Result;
         end;
      end if;
      --  R1.1 / criterion 1: online sends #214 Encryption Request
      --  plaintext and enters awaiting state with no Login Success.
      Result.Outcome := Send_Encryption_Request;
      Result.Session := Session;
      Result.Identity :=
        (Kind => Auth.Offline, UUID => (others => 0),
         Name_Length => 0, Name => (others => ' '));
      Result.Next_State := State.Login_Awaiting_Encryption_Response;
      Result.Has_Request := True;
      Result.Request.Server_Id_Len := 0;
      Result.Request.Public_Len :=
        (if Public_Key'Length > Max_Key_Blob
         then Max_Key_Blob else Public_Key'Length);
      for I in 1 .. Result.Request.Public_Len loop
         Result.Request.Public_Key (I) :=
           Public_Key (Public_Key'First + I - 1);
      end loop;
      Result.Request.Token_Len :=
        (if Token'Length > Max_Token_Blob
         then Max_Token_Blob else Token'Length);
      for I in 1 .. Result.Request.Token_Len loop
         Result.Request.Verify_Token (I) :=
           Token (Token'First + I - 1);
      end loop;
      Result.Reason_Len := 0;
      return Result;
   end Handle_Login_Start;

   function Handle_Encryption_Response
     (Current        : State.Connection_State;
      Session        : Login.Login_Session;
      Payload        : Octets;
      Player_Name    : String;
      Expected_Token : Octets;
      Enabled_Once   : Boolean) return Key_Dispatch_Result
   is
      use type State.Connection_State;
      use type State.Login_Dispatch;
      Result : Key_Dispatch_Result;
      Route  : constant State.Login_Dispatch :=
        State.Dispatch_Login
          (Current, State.Serverbound,
           State.Packet_Id (Ids.Protocol_Id (Ids.Sb_Login_Key)));
   begin
      --  Criterion 5: Encryption Response in any state other than
      --  awaiting-encryption-response, including a second response
      --  after encryption is enabled, is rejected by the state machine.
      if Route /= State.Dispatch_Encryption_Response then
         Result.Outcome := Protocol_Error_Close;
         Result.Session :=
           (State => Login.Closed, Success_Sent => False,
            Has_Identity => False,
            Identity =>
              (Kind => Auth.Offline, UUID => (others => 0),
               Name_Length => 0, Name => (others => ' ')));
         Result.Next_State := Current;
         Result.Enable_Cipher := False;
         Result.Has_Secret := False;
         Set_Reason
           (Result.Reason, Result.Reason_Len, Wrong_State_Reason);
         return Result;
      end if;
      --  Enable-at-most-once latch: a second enabling must be rejected
      --  before touching any cipher state.
      if Enabled_Once then
         Result.Outcome := Protocol_Error_Close;
         Result.Session :=
           (State => Login.Closed, Success_Sent => False,
            Has_Identity => False,
            Identity =>
              (Kind => Auth.Offline, UUID => (others => 0),
               Name_Length => 0, Name => (others => ' ')));
         Result.Next_State := Current;
         Result.Enable_Cipher := False;
         Result.Has_Secret := False;
         Set_Reason
           (Result.Reason, Result.Reason_Len, Wrong_State_Reason);
         return Result;
      end if;
      declare
         Resp : constant Encryption_Response :=
           Decode_Encryption_Response (Payload);
         V    : constant Verify_Result :=
           Decrypt_And_Verify (Resp, Expected_Token);
      begin
         --  Criterion 4: on rejection (bad token, malformed secret,
         --  wrong length) the cipher is not enabled, the connection
         --  disconnects with the #214/constitution reason, no Login
         --  Success is sent, and no further login packets are processed.
         if V.Status /= Ok then
            Result.Outcome := Need_Disconnect_Close;
            Result.Session :=
              (State => Login.Closed, Success_Sent => False,
               Has_Identity => False,
               Identity =>
                 (Kind => Auth.Offline, UUID => (others => 0),
                  Name_Length => 0, Name => (others => ' ')));
            Result.Next_State := Current;
            Result.Enable_Cipher := False;
            Result.Has_Secret := False;
            Set_Reason
              (Result.Reason, Result.Reason_Len,
               V.Reason (1 .. V.Reason_Len));
            return Result;
         end if;
         --  Criterion 6: on success the caller creates exactly once the
         --  two independent persistent CFB8 instances with
         --  Key = IV = 16-byte shared secret (Enable_Cipher=True here),
         --  guarded by Enabled_Once; never disabled, never reset per
         --  packet. The caller then decrypts leftover
         --  Rx_Buffer(Consumed + 1 .. Last) before re-entering framing.
         Result.Outcome := Enable_Then_Success;
         Result.Secret := V.Secret;
         Result.Has_Secret := True;
         Result.Enable_Cipher := True;
         --  SEAM #122: Has_Joined check goes here (between cipher-enable
         --  and Login Success). Until #122, accept any
         --  handshake-completer. DO NOT RELEASE this behaviour.
         declare
            Id : Auth.Player_Identity :=
              Login.Offline_Identity (Player_Name);
         begin
            Result.Identity := Id;
            Result.Session :=
              (State => Login.Success_Sent, Success_Sent => True,
               Has_Identity => True, Identity => Id);
         end;
         --  Criterion 9: post-encryption flow continues through the
         --  existing #212 path to encrypted Login Success and the
         --  login-to-configuration transition.
         Result.Next_State := State.Login_Awaiting_Ack;
         Result.Reason_Len := 0;
         return Result;
      end;
   end Handle_Encryption_Response;

end Adacraft.Protocol.Packets;
