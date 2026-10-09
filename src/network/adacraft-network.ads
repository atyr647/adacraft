with Ada.Streams;
with GNAT.Sockets;
with Adacraft.Protocol;

package Adacraft.Network is
   --  Connection crypto byte-stream stage (criteria 6, 7, 8 pipeline order).
   --
   --  Byte-stream, not packet-stage, encryption: both directions transform
   --  the whole wire stream including length prefix, packet ID and payload.
   --  Ingress decrypts before the frame decoder; egress encrypts the fully
   --  framed bytes as the last stage before the socket.
   --
   --  Pipeline order egress:
   --    Encode_Packet -> Compress_Passthrough -> Encrypt -> Socket_Send
   --  Compress_Passthrough is the identity today; #218 inserts compression
   --  between encoder and encryption with no reordering.
   --
   --  The cipher contexts below are placeholders with the exact shape the
   --  #215 AES-128/CFB8 package must fill: two independent persistent
   --  per-direction states, Key = IV = 16-byte shared secret, never reset
   --  per packet. When #215 lands, replace the private transform body only;
   --  do not change this spec shape. No login logic lives here.

   Shared_Secret_Length : constant := 16;
   Verify_Token_Length  : constant := 4;
   RSA_Modulus_Length   : constant := 256;

   subtype Shared_Secret_Bytes is Protocol.Octets (1 .. Shared_Secret_Length);
   subtype Verify_Token_Bytes is Protocol.Octets (1 .. Verify_Token_Length);
   subtype RSA_Modulus_Bytes is Protocol.Octets (1 .. RSA_Modulus_Length);

   type RSA_Keypair is record
      Present  : Boolean := False;
      Modulus  : RSA_Modulus_Bytes := (others => 0);
      Exponent : Protocol.Octet := 16#01#;
   end record;

   --  Placeholder for the #215 CFB8 context. One value per direction;
   --  state persists for the connection lifetime, never reset per packet.
   type Cipher_Context is record
      Initialized : Boolean := False;
      Key         : Shared_Secret_Bytes := (others => 0);
      Position    : Natural := 0;
   end record;

   procedure Cipher_Init
     (Ctx    : out Cipher_Context;
      Secret : in  Shared_Secret_Bytes);
   --  Key := Secret, IV := Secret (#215 contract); resets Position to 0.
   --  Called exactly once per direction at enable time, never per packet.

   procedure Cipher_Encrypt
     (Ctx  : in out Cipher_Context;
      Data : in out Ada.Streams.Stream_Element_Array);
   --  Egress stream transform. No-op on empty input or uninitialized ctx.

   procedure Cipher_Decrypt
     (Ctx  : in out Cipher_Context;
      Data : in out Ada.Streams.Stream_Element_Array);
   --  Ingress stream transform. No-op on empty input or uninitialized ctx.

   type Crypto_State is record
      Enabled      : Boolean := False;
      Enabled_Once : Boolean := False;
      --  Enable-at-most-once latch: once True, never cleared, never
      --  re-enabled; second enable attempts must be rejected by the
      --  caller (state machine) before touching the contexts.
      Decrypt_Ctx  : Cipher_Context;
      Encrypt_Ctx  : Cipher_Context;
   end record;

   type Connection_Context is record
      Crypto               : Crypto_State;
      Online_Mode          : Boolean := True;
      Injected_RSA         : RSA_Keypair := (Present => False, others => <>);
      Injected_Token       : Verify_Token_Bytes := (others => 0);
      Has_Injected_Token   : Boolean := False;
      Injected_Secret      : Shared_Secret_Bytes := (others => 0);
      Has_Injected_Secret  : Boolean := False;
   end record;
   --  Rx leftover uses the existing Hold/Used buffer indices in Serve_Client:
   --  bytes already buffered past the end of the Encryption Response frame
   --  in the same read are run through Decrypt before re-entering framing.
   --  No new buffer lives here; this record holds only crypto + hooks.

   procedure Set_Online_Mode
     (Conn : in out Connection_Context;
      Mode : in Boolean);

   procedure Inject_RSA_Keypair
     (Conn   : in out Connection_Context;
      Key    : in RSA_Keypair);
   --  Test hook: fixed RSA keypair for deterministic corpus scenarios.
   --  Production path generates per #214 when Present = False.

   procedure Inject_Verify_Token
     (Conn  : in out Connection_Context;
      Token : in Verify_Token_Bytes);
   --  Test hook: fixed verify token. Production generates per #214.

   procedure Inject_Shared_Secret
     (Conn   : in out Connection_Context;
      Secret : in Shared_Secret_Bytes);
   --  Test hook: fixed client shared secret for deterministic tests.

   function Is_Encryption_Enabled (Conn : Connection_Context) return Boolean;

   function Try_Enable_Encryption
     (Conn   : in out Connection_Context;
      Secret : in Shared_Secret_Bytes) return Boolean;
   --  Creates the two independent persistent CFB8 instances once
   --  (Key = IV = Secret for both), sets Enabled. Returns True on the
   --  single enabling; returns False and changes nothing when
   --  Enabled_Once is already True (never disable, never reset).

   procedure On_Receive_Bytes
     (Conn : in out Connection_Context;
      Data : in out Ada.Streams.Stream_Element_Array);
   --  Ingress stage: if Enabled then CFB8_Decrypt before Frame_Decoder,
   --  else passthrough. Pure in-memory transform; no threads, no world
   --  mutation. Applies equally to leftover bytes already buffered past
   --  the Encryption Response frame in the same read.

   procedure Compress_Passthrough
     (Data   : in Ada.Streams.Stream_Element_Array;
      Output : out Ada.Streams.Stream_Element_Array;
      Last   : out Ada.Streams.Stream_Element_Offset);
   --  Identity stage today. INSERTION POINT for #218: Set Compression
   --  wiring goes here, between encoder and encryption, with no reordering
   --  of the Encode -> Compress -> Encrypt -> Socket_Send pipeline.

   procedure On_Send_Frame
     (Conn : in out Connection_Context;
      Data : in out Ada.Streams.Stream_Element_Array);
   --  Egress stage, last before the socket: if Enabled then CFB8_Encrypt
   --  over the fully framed bytes (length prefix + ID + payload).
   --  Callers must build wire bytes via the existing encoder/framer, run
   --  Compress_Passthrough, then call this immediately before socket write.

   procedure Serve (Port : GNAT.Sockets.Port_Type);
end Adacraft.Network;
