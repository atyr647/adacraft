--  Login encryption handshake (server side to shared-secret check).
--  One-shot 1024-bit RSA keypair, cached DER SPKI, verify-token issue,
--  Encryption Request encode and Encryption Response decode/verify.
--  Unit-tested only; no network, framing, cipher or world mutation here.
with System;
with Adacraft.Protocol.State;

package Adacraft.Protocol.Login_Encryption is

   RSA_Bits          : constant := 1_024;
   RSA_Exponent      : constant := 65_537;
   RSA_Size_Bytes    : constant := 128;
   Secret_Length     : constant := 16;
   Token_Length      : constant := 4;
   Max_Der_Length    : constant := 2_048;
   Max_Request_Length : constant := 2_080;
   Max_Response_Length : constant := 270;

   subtype Token_Bytes is State.Verify_Token_Bytes;
   subtype Secret_Bytes is Octets (1 .. Secret_Length);
   subtype Cipher_Bytes is Octets (1 .. RSA_Size_Bytes);

   subtype Der_Index is Positive range 1 .. Max_Der_Length;
   type Der_Store is array (Der_Index) of Octet;

   --  Keypair lifetime --------------------------------------------------------

   function Is_Initialized return Boolean;

   --  Generate the 1024-bit keypair once and cache the DER SPKI.
   --  Returns True on success; False leaves no half-initialised state.
   --  Never raises.
   function Ensure_Initialized return Boolean;

   function Public_Der_Length return Natural;

   --  Copy the cached DER bytes out.  Success is False when not
   --  initialised or Der cannot hold the bytes.
   procedure Get_Public_DER
     (Der     : out Octets;
      Len     : out Natural;
      Success : out Boolean);

   --  Private handle for Verify_Response / tests.  Null when not
   --  initialised.  Never logged, packetised or persisted by this package.
   function Private_Handle_Address return System.Address;

   --  Verify token ------------------------------------------------------------

   --  Fresh 4 CSPRNG bytes via RAND_bytes.  Success False on RNG failure.
   --  Never raises.
   procedure Generate_Verify_Token
     (Token   : out Token_Bytes;
      Success : out Boolean);

   --  Request encode ----------------------------------------------------------

   type Encode_Status is
     (Encode_Ok,
      Not_Initialized,
      Wrong_State_Or_Direction,
      Bad_Argument,
      Output_Too_Small);

   type Encode_Result (Status : Encode_Status := Encode_Ok) is record
      case Status is
         when Encode_Ok =>
            Length : Natural := 0;
            Data   : Octets (1 .. Max_Request_Length) := [others => 0];
         when others =>
            null;
      end case;
   end record;

   --  Packet body (packet-ID + fields) for Encryption Request.
   --  Fields: String("") + VarInt(len)+DER + VarInt(4)+token + Boolean.
   --  Packet ID is the pinned Cb_Login_Hello id.  Requires
   --  State = Login and Direction = Clientbound, else
   --  Wrong_State_Or_Direction.  Never raises.
   function Encode_Encryption_Request
     (Der                 : Octets;
      Token               : Token_Bytes;
      Should_Authenticate : Boolean;
      Conn_State          : State.Connection_State;
      Direction           : State.Packet_Direction) return Encode_Result;

   --  Response decode ---------------------------------------------------------

   type Decode_Status is
     (Decode_Ok,
      Wrong_State_Or_Direction,
      Bad_Packet_Id,
      Truncated,
      Bad_Varint,
      Bad_Length,
      Trailing_Bytes);

   type Encryption_Response is record
      Secret_Cipher : Cipher_Bytes := [others => 0];
      Token_Cipher  : Cipher_Bytes := [others => 0];
   end record;

   type Decode_Result (Status : Decode_Status := Decode_Ok) is record
      case Status is
         when Decode_Ok =>
            Response : Encryption_Response;
         when others =>
            null;
      end case;
   end record;

   --  Parse packet body (packet-ID + two VarInt-prefixed 128-byte arrays).
   --  Requires State = Login, Direction = Serverbound, pinned
   --  Sb_Login_Key id, each length = 128 = RSA_size, no trailing bytes.
   --  Every malformed input maps to a Decode_Status; never raises.
   function Decode_Encryption_Response
     (Payload    : Octets;
      Conn_State : State.Connection_State;
      Direction  : State.Packet_Direction) return Decode_Result;

   --  Response verification (R5) ----------------------------------------------

   type Verify_Status is
     (Verify_Ok,
      Not_Initialized,
      Decryption_Padding_Failure,
      Verify_Token_Mismatch,
      Wrong_Shared_Secret_Length);

   type Verify_Result (Status : Verify_Status := Verify_Ok) is record
      case Status is
         when Verify_Ok =>
            Secret : Secret_Bytes := [others => 0];
         when others =>
            null;
      end case;
   end record;

   --  RSA_private_decrypt (PKCS#1 v1.5) both fields, constant-time 4-byte
   --  token compare, decrypted secret must be exactly 16 bytes.
   --  Pure: no connection/world mutation.  Never raises; on any failure
   --  no secret is returned (discriminant selects the failure kind).
   function Verify_Response
     (Decoded        : Encryption_Response;
      Expected_Token : Token_Bytes) return Verify_Result;

   --  Test hook: encrypt with the live public key (acts as client).
   --  Used to prove wire compatibility without network.
   type Encrypt_Status is
     (Encrypt_Ok,
      Not_Initialized,
      Bad_Argument,
      Operation_Failed);

   type Encrypt_Result (Status : Encrypt_Status := Encrypt_Ok) is record
      case Status is
         when Encrypt_Ok =>
            Length : Natural := 0;
            Data   : Cipher_Bytes := [others => 0];
         when others =>
            null;
      end case;
   end record;

   function Test_Encrypt_With_Public_Key
     (Plain : Octets) return Encrypt_Result;

end Adacraft.Protocol.Login_Encryption;
