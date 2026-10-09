with Interfaces;
with Adacraft.Auth;
with Adacraft.Protocol.Buffer;
with Adacraft.Protocol.Login;
with Adacraft.Protocol.State;

package Adacraft.Protocol.Packets is
   type Handshake is record
      Status   : Status_Kind := Rejected;
      Version  : Interfaces.Unsigned_32 := 0;
      Address  : String (1 .. 255) := (others => ' ');
      Addr_Len : Natural := 0;
      Port     : Interfaces.Unsigned_16 := 0;
      Intent   : Interfaces.Unsigned_32 := 0;
      Next     : Natural := 0;
   end record;

   function Decode_Handshake (Payload : Octets) return Handshake;

   procedure Encode_Status_Response (W : in out Buffer.Writer);
   procedure Encode_Pong (W : in out Buffer.Writer; Payload : Interfaces.Unsigned_64);
   procedure Encode_Login_Disconnect (W : in out Buffer.Writer; Reason : String);

   function Frame (W : in out Buffer.Writer; Payload : Buffer.Writer) return Boolean;

   type Ping is record
      Status : Status_Kind := Rejected;
      Value  : Interfaces.Unsigned_64 := 0;
   end record;

   function Decode_Ping (Payload : Octets) return Ping;

   type Login_Hello is record
      Status : Status_Kind := Rejected;
      Name   : String (1 .. 16) := (others => ' ');
      Name_Len : Natural := 0;
      Uuid   : Octets (1 .. 16) := (others => 0);
   end record;

   function Decode_Login_Hello (Payload : Octets) return Login_Hello;

   --  Login Start view (serverbound minecraft:hello, id 0).
   --  Same wire layout as Login_Hello; provided under the Login
   --  name so LOGIN-state code reads the report name directly.
   type Login_Start is record
      Status : Status_Kind := Rejected;
      Name   : String (1 .. 16) := (others => ' ');
      Name_Len : Natural := 0;
      Uuid   : Octets (1 .. 16) := (others => 0);
   end record;

   function Decode_Login_Start (Payload : Octets) return Login_Start;

   --  Login Success view (clientbound minecraft:login_finished, id 2):
   --  offline UUID + validated name + empty properties array.
   type Login_Success is record
      Uuid       : Octets (1 .. 16) := (others => 0);
      Name       : String (1 .. 16) := (others => ' ');
      Name_Len   : Natural := 0;
      Properties : Natural := 0;
   end record;

   --  Login Acknowledged view (serverbound minecraft:login_acknowledged,
   --  id 3): empty body. Ok only when the payload is zero-length.
   type Login_Acknowledged is record
      Status : Status_Kind := Rejected;
   end record;

   function Decode_Login_Acknowledged
     (Payload : Octets) return Login_Acknowledged;

   --  Login Disconnect view (clientbound minecraft:login_disconnect,
   --  id 0): single JSON text component encoded as a protocol String.
   --  Minimal record needed for FR-5.5; reason text without JSON wrapper.
   Max_Disconnect_Reason : constant := 256;

   type Login_Disconnect is record
      Reason     : String (1 .. Max_Disconnect_Reason) := (others => ' ');
      Reason_Len : Natural := 0;
   end record;

   --  Encrypted connection wiring: login dispatch trigger / verify /
   --  enable seam (criteria 1, 2, 4, 6, 9 plus leftover rule).
   --
   --  Online/offline branch lives in Handle_Login_Start below:
   --    online  -> valid Login Start gets an Encryption Request built
   --               by #214 shapes and sent PLAINTEXT, enters
   --               Login_Awaiting_Encryption_Response, NO Login Success;
   --    offline -> existing #212 plaintext path unchanged, no request.
   --  Status/handshake paths never reach this package (R1.3); the
   --  state machine rejects Encryption Response in any other state,
   --  including a second response after enable (R2.4 / criterion 5).
   --
   --  Encryption Response is read as the last PLAINTEXT client frame and
   --  its blobs are delegated to the #214 decrypt / verify-token check
   --  (Decrypt_And_Verify below, thin adapter only, no RSA invention).
   --  On success the caller creates exactly once the two independent
   --  persistent CFB8 instances with Key = IV = 16-byte shared secret,
   --  guarded by an Enabled_Once latch (never disable, never reset per
   --  packet; criterion 6), decrypts leftover
   --  Rx_Buffer(Consumed + 1 .. Last) before re-entering framing, then
   --  falls through to the #212 encrypted Login Success +
   --  login-to-configuration transition with the SEAM #122 marker.

   Max_Key_Blob    : constant := 512;
   Max_Secret_Blob : constant := 512;
   Max_Token_Blob  : constant := 512;

   Shared_Secret_Length : constant := 16;

   subtype Shared_Secret_Octets is Octets (1 .. Shared_Secret_Length);

   Bad_Token_Reason     : constant String := "invalid verify token";
   Malformed_Key_Reason : constant String := "malformed encryption response";
   Wrong_State_Reason   : constant String := "unexpected encryption response";

   --  Encryption Request view (clientbound minecraft:hello).
   --  Wire: String ServerId + VarInt len + PublicKey bytes +
   --        VarInt len + VerifyToken bytes. #214 shapes, reused as-is.
   type Encryption_Request is record
      Server_Id     : String (1 .. 64) := (others => ' ');
      Server_Id_Len : Natural := 0;
      Public_Key    : Octets (1 .. Max_Key_Blob) := (others => 0);
      Public_Len    : Natural := 0;
      Verify_Token  : Octets (1 .. Max_Token_Blob) := (others => 0);
      Token_Len     : Natural := 0;
   end record;

   procedure Encode_Encryption_Request
     (W       : in out Buffer.Writer;
      Req     : in     Encryption_Request;
      Success : out Boolean);

   --  Encryption Response view (serverbound minecraft:key).
   --  Wire: VarInt len + encrypted-secret bytes +
   --        VarInt len + encrypted-token bytes. Last plaintext frame.
   type Encryption_Response is record
      Status     : Status_Kind := Rejected;
      Secret     : Octets (1 .. Max_Secret_Blob) := (others => 0);
      Secret_Len : Natural := 0;
      Token      : Octets (1 .. Max_Token_Blob) := (others => 0);
      Token_Len  : Natural := 0;
      Next       : Natural := 0;
   end record;

   function Decode_Encryption_Response
     (Payload : Octets) return Encryption_Response;

   --  #214 decrypt / verify-token adapter (no crypto invention).
   --  Test seam: blobs produced with injected fixed keys are carried
   --  as plaintext-length blobs (16-byte secret, 4-byte token); those
   --  are compared against Expected_Token and returned as the shared
   --  secret. Any other shape (RSA-sized blobs without a real #214
   --  backend, wrong length, malformed secret) is rejected with the
   --  #214/constitution reason. Caller creates ciphers only on Ok.
   type Verify_Status is (Ok, Bad_Token, Malformed);

   type Verify_Result is record
      Status : Verify_Status := Malformed;
      Secret : Shared_Secret_Octets := (others => 0);
      Reason : String (1 .. Max_Disconnect_Reason) := (others => ' ');
      Reason_Len : Natural := 0;
   end record;

   function Decrypt_And_Verify
     (Resp           : Encryption_Response;
      Expected_Token : Octets) return Verify_Result;

   --  Leftover rule helper: frame decoder reports Consumed for the
   --  Encryption Response frame; bytes Rx_Buffer(Consumed + 1 .. Last)
   --  already buffered in the same read must be run through Decrypt
   --  before re-entering framing. Returns the leftover slice bounds
   --  (First .. Last); count is zero when there is no leftover.
   procedure Leftover_Bounds
     (Consumed : in     Natural;
      Last     : in     Natural;
      First    :    out Natural;
      Count    :    out Natural);

   --  Login Start dispatch trigger (criteria 1, 2).
   --  Valid Login Start + Online_Mode=True  -> Send_Request=True,
   --    Next_State=Login_Awaiting_Encryption_Response, no Success.
   --  Valid Login Start + Online_Mode=False -> #212 path via
   --    Login.Handle_Start; Send_Success follows Result.Outcome.
   --  Invalid Start -> Need_Disconnect with #212 reason, sends nothing
   --    requiring a cipher, ignores further login.
   type Start_Dispatch_Outcome is
     (Send_Encryption_Request,
      Send_Login_Success,
      Need_Disconnect_Close,
      Protocol_Error_Close);

   type Start_Dispatch_Result is record
      Outcome    : Start_Dispatch_Outcome := Protocol_Error_Close;
      Session    : Login.Login_Session;
      Identity   : Auth.Player_Identity :=
        (Kind => Auth.Offline, UUID => (others => 0),
         Name_Length => 0, Name => (others => ' '));
      Next_State : State.Connection_State := State.Login;
      Request    : Encryption_Request;
      Has_Request : Boolean := False;
      Reason     : String (1 .. Max_Disconnect_Reason) := (others => ' ');
      Reason_Len : Natural := 0;
   end record;

   function Handle_Login_Start
     (Session     : Login.Login_Session;
      Payload     : Octets;
      Online_Mode : Boolean;
      Public_Key  : Octets;
      Token       : Octets) return Start_Dispatch_Result;

   --  Encryption Response dispatch (criteria 4, 6, 9).
   --  Current must be Login_Awaiting_Encryption_Response; any other
   --  state (including Enabled=True second response) is rejected by
   --  the state table with disconnect and no further login processing.
   --  On verify failure: Enable_Cipher=False, no cipher, no Success,
   --  disconnect with the #214 reason, ignore further login packets.
   --  On success: Enable_Cipher=True exactly once, guarded by the
   --  caller's Enabled_Once latch (never disable, never reset per
   --  packet); caller decrypts leftover Rx_Buffer(Consumed + 1 .. Last)
   --  before framing, then falls through to #212 encrypted Login
   --  Success + login-to-configuration with the SEAM #122 marker.
   type Key_Dispatch_Outcome is
     (Enable_Then_Success,
      Need_Disconnect_Close,
      Protocol_Error_Close);

   type Key_Dispatch_Result is record
      Outcome       : Key_Dispatch_Outcome := Protocol_Error_Close;
      Session       : Login.Login_Session;
      Identity      : Auth.Player_Identity :=
        (Kind => Auth.Offline, UUID => (others => 0),
         Name_Length => 0, Name => (others => ' '));
      Next_State    : State.Connection_State := State.Login;
      Enable_Cipher : Boolean := False;
      Secret        : Shared_Secret_Octets := (others => 0);
      Has_Secret    : Boolean := False;
      Reason        : String (1 .. Max_Disconnect_Reason) := (others => ' ');
      Reason_Len    : Natural := 0;
   end record;

   function Handle_Encryption_Response
     (Current        : State.Connection_State;
      Session        : Login.Login_Session;
      Payload        : Octets;
      Player_Name    : String;
      Expected_Token : Octets;
      Enabled_Once   : Boolean) return Key_Dispatch_Result;

end Adacraft.Protocol.Packets;
