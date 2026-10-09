with Adacraft.Ingress;
with Adacraft.Protocol.Buffer;

package body Adacraft.Network is

   procedure Cipher_Init
     (Ctx    : out Cipher_Context;
      Secret : in  Shared_Secret_Bytes)
   is
   begin
      Ctx.Initialized := True;
      Ctx.Key := Secret;
      Ctx.Position := 0;
   end Cipher_Init;

   procedure Transform_In_Place
     (Ctx  : in out Cipher_Context;
      Data : in out Ada.Streams.Stream_Element_Array)
   is
      use type Ada.Streams.Stream_Element;
      use type Ada.Streams.Stream_Element_Offset;
   begin
      if not Ctx.Initialized then
         return;
      end if;
      for I in Data'Range loop
         declare
            K : constant Ada.Streams.Stream_Element :=
              Ada.Streams.Stream_Element
                (Ctx.Key (Ctx.Position mod Shared_Secret_Length + 1));
         begin
            --  PLACEHOLDER stream transform mirroring the CFB8 byte-stream
            --  contract (whole wire stream, persistent per-direction state,
            --  never reset per packet). #215 replaces this XOR body with
            --  AES-128/CFB8 using Key = IV = shared secret; callers are
            --  unaffected.
            Data (I) := Data (I) xor K;
            Ctx.Position := Ctx.Position + 1;
         end;
      end loop;
   end Transform_In_Place;

   procedure Cipher_Encrypt
     (Ctx  : in out Cipher_Context;
      Data : in out Ada.Streams.Stream_Element_Array)
   is
   begin
      Transform_In_Place (Ctx, Data);
   end Cipher_Encrypt;

   procedure Cipher_Decrypt
     (Ctx  : in out Cipher_Context;
      Data : in out Ada.Streams.Stream_Element_Array)
   is
   begin
      Transform_In_Place (Ctx, Data);
   end Cipher_Decrypt;

   procedure Set_Online_Mode
     (Conn : in out Connection_Context;
      Mode : in Boolean)
   is
   begin
      Conn.Online_Mode := Mode;
   end Set_Online_Mode;

   procedure Inject_RSA_Keypair
     (Conn : in out Connection_Context;
      Key  : in RSA_Keypair)
   is
   begin
      Conn.Injected_RSA := Key;
      Conn.Injected_RSA.Present := True;
   end Inject_RSA_Keypair;

   procedure Inject_Verify_Token
     (Conn  : in out Connection_Context;
      Token : in Verify_Token_Bytes)
   is
   begin
      Conn.Injected_Token := Token;
      Conn.Has_Injected_Token := True;
   end Inject_Verify_Token;

   procedure Inject_Shared_Secret
     (Conn   : in out Connection_Context;
      Secret : in Shared_Secret_Bytes)
   is
   begin
      Conn.Injected_Secret := Secret;
      Conn.Has_Injected_Secret := True;
   end Inject_Shared_Secret;

   function Is_Encryption_Enabled (Conn : Connection_Context) return Boolean is
   begin
      return Conn.Crypto.Enabled;
   end Is_Encryption_Enabled;

   function Try_Enable_Encryption
     (Conn   : in out Connection_Context;
      Secret : in Shared_Secret_Bytes) return Boolean
   is
   begin
      if Conn.Crypto.Enabled_Once then
         return False;
      end if;
      Cipher_Init (Conn.Crypto.Encrypt_Ctx, Secret);
      Cipher_Init (Conn.Crypto.Decrypt_Ctx, Secret);
      Conn.Crypto.Enabled := True;
      Conn.Crypto.Enabled_Once := True;
      return True;
   end Try_Enable_Encryption;

   procedure On_Receive_Bytes
     (Conn : in out Connection_Context;
      Data : in out Ada.Streams.Stream_Element_Array)
   is
   begin
      if Conn.Crypto.Enabled then
         Cipher_Decrypt (Conn.Crypto.Decrypt_Ctx, Data);
      end if;
   end On_Receive_Bytes;

   procedure Compress_Passthrough
     (Data   : in Ada.Streams.Stream_Element_Array;
      Output : out Ada.Streams.Stream_Element_Array;
      Last   : out Ada.Streams.Stream_Element_Offset)
   is
      use type Ada.Streams.Stream_Element_Offset;
      Len : constant Ada.Streams.Stream_Element_Offset :=
        Data'Length;
   begin
      --  Identity today. INSERTION POINT for #218 (Set Compression wiring):
      --  compress framed bytes here, between encoder and encryption.
      --  Pipeline must stay Encode -> Compress -> Encrypt -> Socket_Send.
      if Output'Length < Len then
         Last := Output'First - 1;
         return;
      end if;
      Last := Output'First - 1;
      for I in Data'Range loop
         Last := Last + 1;
         Output (Last) := Data (I);
      end loop;
   end Compress_Passthrough;

   procedure On_Send_Frame
     (Conn : in out Connection_Context;
      Data : in out Ada.Streams.Stream_Element_Array)
   is
   begin
      if Conn.Crypto.Enabled then
         Cipher_Encrypt (Conn.Crypto.Encrypt_Ctx, Data);
      end if;
   end On_Send_Frame;

   procedure Serve_Client (Client : GNAT.Sockets.Socket_Type) is
      use type Ada.Streams.Stream_Element_Offset;
      Cap    : constant := 8192;
      Hold   : Protocol.Octets (1 .. Cap) := (others => 0);
      Used   : Natural := 0;
      Item   : Ada.Streams.Stream_Element_Array (1 .. 2048);
      Last   : Ada.Streams.Stream_Element_Offset;
      Out_W  : Protocol.Buffer.Writer (4096);
      S      : Ingress.Session;
      Conn   : Connection_Context;
   begin
      loop
         GNAT.Sockets.Receive_Socket (Client, Item, Last);
         exit when Last < Item'First;
         --  Ingress crypto stage: decrypt before framing (passthrough
         --  until Try_Enable_Encryption latches Enabled).
         On_Receive_Bytes (Conn, Item (Item'First .. Last));
         if Used > Cap - Natural (Last - Item'First + 1) then
            exit;
         end if;
         for I in Item'First .. Last loop
            Used := Used + 1;
            Hold (Used) := Protocol.Octet (Item (I));
         end loop;

         Protocol.Buffer.Reset (Out_W);
         declare
            Consumed  : Natural;
            Close_Now : Boolean;
         begin
            Ingress.Ingest (S, Hold (1 .. Used), 1, Consumed, Out_W, Close_Now);
            if Out_W.Len > 0 and then not Out_W.Failed then
               declare
                  Msg : Ada.Streams.Stream_Element_Array (1 .. Ada.Streams.Stream_Element_Offset (Out_W.Len));
                  Sent : Ada.Streams.Stream_Element_Offset;
               begin
                  for I in Msg'Range loop
                     Msg (I) := Ada.Streams.Stream_Element (Out_W.Data (Positive (I)));
                  end loop;
                  --  Egress pipeline: encoder output is already in Msg;
                  --  compression is identity (Compress_Passthrough), then
                  --  On_Send_Frame encrypts as the last stage before send.
                  --  Encode_Packet -> Compress_Passthrough -> Encrypt
                  --    -> Socket_Send.
                  declare
                     Comp : Ada.Streams.Stream_Element_Array (Msg'Range);
                     Comp_Last : Ada.Streams.Stream_Element_Offset;
                  begin
                     Compress_Passthrough (Msg, Comp, Comp_Last);
                     for I in Msg'First .. Comp_Last loop
                        Msg (I) := Comp (I);
                     end loop;
                  end;
                  On_Send_Frame (Conn, Msg);
                  GNAT.Sockets.Send_Socket (Client, Msg, Sent);
               end;
            end if;
            if Consumed > 0 and then Consumed <= Used then
               if Consumed < Used then
                  Hold (1 .. Used - Consumed) := Hold (Consumed + 1 .. Used);
               end if;
               Used := Used - Consumed;
            end if;
            exit when Close_Now or else Out_W.Failed;
         end;
      end loop;
   end Serve_Client;

   procedure Serve (Port : GNAT.Sockets.Port_Type) is
      use GNAT.Sockets;
      Server  : Socket_Type;
      Client  : Socket_Type;
      Address : Sock_Addr_Type;
      Peer    : Sock_Addr_Type;
   begin
      Create_Socket (Server);
      Set_Socket_Option (Server, Socket_Level, (Reuse_Address, True));
      Address.Addr := Any_Inet_Addr;
      Address.Port := Port;
      Bind_Socket (Server, Address);
      Listen_Socket (Server);
      loop
         Accept_Socket (Server, Client, Peer);
         Serve_Client (Client);
         Close_Socket (Client);
      end loop;
   end Serve;
end Adacraft.Network;
