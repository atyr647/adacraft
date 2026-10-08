with Interfaces;
with System;
with Adacraft.Crypto.OpenSSL;
with Adacraft.Protocol.Ids;
with Adacraft.Protocol.Varnum;

package body Adacraft.Protocol.Login_Encryption is

   use type Interfaces.Unsigned_8;
   use type Interfaces.Unsigned_32;
   use type State.Connection_State;
   use type State.Packet_Direction;

   Cached_Der  : Der_Store := (others => 0);
   Cached_Len  : Natural := 0;
   Initialized : Boolean := False;

   Priv_Handle : Adacraft.Crypto.OpenSSL.RSA_Ptr :=
     Adacraft.Crypto.OpenSSL.Null_RSA;

   function Is_Initialized return Boolean is
   begin
      return Initialized;
   end Is_Initialized;

   function Private_Handle_Address return System.Address is
   begin
      return System.Address (Priv_Handle);
   exception
      when others =>
         return System.Null_Address;
   end Private_Handle_Address;

   function Ensure_Initialized return Boolean is
      use Adacraft.Crypto.OpenSSL;
      Kr  : Handle_Result;
      Tmp : Der_Buffer := (others => 0);
      Dr  : Der_Result;
   begin
      if Initialized then
         return True;
      end if;
      if not Is_Null (Priv_Handle) then
         --  Half state from a previous failure; reset first.
         declare
            T : RSA_Ptr := Priv_Handle;
         begin
            Rsa_Free (T);
            Priv_Handle := Null_RSA;
         exception
            when others => Priv_Handle := Null_RSA;
         end;
         Cached_Len := 0;
         Initialized := False;
      end if;
      Kr := Generate_Keypair (RSA_Bits, RSA_Exponent);
      if Kr.Code /= Success then
         return False;
      end if;
      Priv_Handle := Kr.Handle;
      Export_Public_DER (Priv_Handle, Tmp, Dr);
      if Dr.Code /= Success or else Dr.Length = 0
        or else Dr.Length > Cached_Der'Length
      then
         declare
            T : RSA_Ptr := Priv_Handle;
         begin
            Rsa_Free (T);
         exception
            when others => null;
         end;
         Priv_Handle := Null_RSA;
         Cached_Len := 0;
         return False;
      end if;
      for I in 1 .. Dr.Length loop
         Cached_Der (I) := Octet (Tmp (I));
      end loop;
      Cached_Len := Dr.Length;
      Initialized := True;
      return True;
   exception
      when others =>
         return False;
   end Ensure_Initialized;

   function Public_Der_Length return Natural is
   begin
      if not Initialized then
         return 0;
      end if;
      return Cached_Len;
   exception
      when others =>
         return 0;
   end Public_Der_Length;

   procedure Get_Public_DER
     (Der     : out Octets;
      Len     : out Natural;
      Success : out Boolean)
   is
   begin
      Len := 0;
      for I in Der'Range loop
         Der (I) := 0;
      end loop;
      Success := False;
      if not Initialized or else Cached_Len = 0 then
         return;
      end if;
      if Der'Length < Cached_Len then
         return;
      end if;
      for I in 1 .. Cached_Len loop
         Der (Der'First + (I - 1)) := Cached_Der (I);
      end loop;
      Len := Cached_Len;
      Success := True;
   exception
      when others =>
         Len := 0;
         Success := False;
   end Get_Public_DER;

   procedure Generate_Verify_Token
     (Token   : out Token_Bytes;
      Success : out Boolean)
   is
      use Adacraft.Crypto.OpenSSL;
      Raw : Byte_Array (1 .. Token_Length) := (others => 0);
      Res : Random_Result;
   begin
      Token := (others => 0);
      Success := False;
      Rand_Bytes (Raw, Res);
      if Res.Code /= Success then
         return;
      end if;
      for I in Token_Bytes'Range loop
         Token (I) := Octet (Raw (I - Token_Bytes'First + Raw'First));
      end loop;
      Success := True;
   exception
      when others =>
         Token := (others => 0);
         Success := False;
   end Generate_Verify_Token;

   --  Helpers ----------------------------------------------------------------

   procedure Put_Varint_U32
     (Buf     : in out Octets;
      Pos     : in out Natural;
      Value   : Interfaces.Unsigned_32;
      Success : out Boolean)
   is
      Rest : Interfaces.Unsigned_32 := Value;
   begin
      Success := False;
      loop
         if Pos + 1 > Buf'Last then
            return;
         end if;
         declare
            B : Interfaces.Unsigned_32 := Rest and 16#7F#;
         begin
            Rest := Interfaces.Shift_Right (Rest, 7);
            if Rest /= 0 then
               Pos := Pos + 1;
               Buf (Pos) := Octet (B or 16#80#);
            else
               Pos := Pos + 1;
               Buf (Pos) := Octet (B);
               exit;
            end if;
         end;
      end loop;
      Success := True;
   exception
      when others =>
         Success := False;
   end Put_Varint_U32;

   function Request_Packet_Id return Natural is
   begin
      return Ids.Protocol_Id (Ids.Cb_Login_Hello);
   exception
      when others =>
         return 1;
   end Request_Packet_Id;

   function Response_Packet_Id return Natural is
   begin
      return Ids.Protocol_Id (Ids.Sb_Login_Key);
   exception
      when others =>
         return 1;
   end Response_Packet_Id;

   function Encode_Encryption_Request
     (Der                 : Octets;
      Token               : Token_Bytes;
      Should_Authenticate : Boolean;
      Conn_State          : State.Connection_State;
      Direction           : State.Packet_Direction) return Encode_Result
   is
      Buf : Octets (1 .. Max_Request_Length) := (others => 0);
      Pos : Natural := 0;
      Ok  : Boolean := False;
      Res : Encode_Result (Encode_Ok);
   begin
      if Conn_State /= State.Login or else Direction /= State.Clientbound then
         return (Status => Wrong_State_Or_Direction);
      end if;
      if not Initialized or else Cached_Len = 0 then
         return (Status => Not_Initialized);
      end if;
      if Der'Length = 0 or else Der'Length > Max_Der_Length then
         return (Status => Bad_Argument);
      end if;
      Put_Varint_U32 (Buf, Pos, Interfaces.Unsigned_32 (Request_Packet_Id), Ok);
      if not Ok then
         return (Status => Output_Too_Small);
      end if;
      --  Server ID: String("") => VarInt 0.
      Put_Varint_U32 (Buf, Pos, 0, Ok);
      if not Ok then
         return (Status => Output_Too_Small);
      end if;
      --  Public key byte array.
      Put_Varint_U32 (Buf, Pos, Interfaces.Unsigned_32 (Der'Length), Ok);
      if not Ok then
         return (Status => Output_Too_Small);
      end if;
      if Pos + Der'Length > Buf'Last then
         return (Status => Output_Too_Small);
      end if;
      for I in Der'Range loop
         Pos := Pos + 1;
         Buf (Pos) := Der (I);
      end loop;
      --  Verify token byte array (length 4).
      Put_Varint_U32 (Buf, Pos, Interfaces.Unsigned_32 (Token_Length), Ok);
      if not Ok then
         return (Status => Output_Too_Small);
      end if;
      if Pos + Token_Length > Buf'Last then
         return (Status => Output_Too_Small);
      end if;
      for I in Token_Bytes'Range loop
         Pos := Pos + 1;
         Buf (Pos) := Token (I);
      end loop;
      --  Should Authenticate boolean.
      if Pos + 1 > Buf'Last then
         return (Status => Output_Too_Small);
      end if;
      Pos := Pos + 1;
      Buf (Pos) := (if Should_Authenticate then 1 else 0);
      Res.Length := Pos;
      Res.Data (1 .. Pos) := Buf (1 .. Pos);
      return Res;
   exception
      when others =>
         return (Status => Bad_Argument);
   end Encode_Encryption_Request;

   function Decode_Encryption_Response
     (Payload    : Octets;
      Conn_State : State.Connection_State;
      Direction  : State.Packet_Direction) return Decode_Result
   is
      Fail : Decode_Status;
      function Err (S : Decode_Status) return Decode_Result is
        (Status => S);
      R   : Varnum.Varint_Result;
      Pos : Natural;
      Need : Natural;
   begin
      if Conn_State /= State.Login or else Direction /= State.Serverbound then
         return Err (Wrong_State_Or_Direction);
      end if;
      if Payload'Length = 0 then
         return Err (Truncated);
      end if;
      Pos := Payload'First;
      --  Packet ID.
      R := Varnum.Decode_Varint (Payload, Pos);
      if R.Status = Status_Kind'(Rejected) then
         return Err (Bad_Varint);
      elsif R.Status /= Status_Kind'(Ok) then
         return Err (Truncated);
      end if;
      if R.Value /= Interfaces.Unsigned_32 (Response_Packet_Id) then
         return Err (Bad_Packet_Id);
      end if;
      Pos := R.Next;
      declare
         Resp : Encryption_Response;
      begin
         for Field in 1 .. 2 loop
            if Pos > Payload'Last then
               Fail := Truncated;
               return Err (Fail);
            end if;
            R := Varnum.Decode_Varint (Payload, Pos);
            if R.Status = Status_Kind'(Rejected) then
               return Err (Bad_Varint);
            elsif R.Status /= Status_Kind'(Ok) then
               return Err (Truncated);
            end if;
            if R.Value /= Interfaces.Unsigned_32 (RSA_Size_Bytes) then
               return Err (Bad_Length);
            end if;
            Pos := R.Next;
            Need := RSA_Size_Bytes;
            if Pos > Payload'Last then
               return Err (Truncated);
            end if;
            if Payload'Last - Pos + 1 < Need then
               return Err (Truncated);
            end if;
            for I in 1 .. Need loop
               if Field = 1 then
                  Resp.Secret_Cipher (I) := Payload (Pos + I - 1);
               else
                  Resp.Token_Cipher (I) := Payload (Pos + I - 1);
               end if;
            end loop;
            Pos := Pos + Need;
         end loop;
         if Pos <= Payload'Last then
            return Err (Trailing_Bytes);
         end if;
         return (Status => Decode_Ok, Response => Resp);
      end;
   exception
      when others =>
         return (Status => Truncated);
   end Decode_Encryption_Response;

   function To_OpenSSL_Bytes (Data : Octets)
     return Adacraft.Crypto.OpenSSL.Byte_Array
   is
      use Adacraft.Crypto.OpenSSL;
      Out_Arr : Byte_Array (1 .. Data'Length) := (others => 0);
   begin
      for I in Data'Range loop
         Out_Arr (I - Data'First + 1) := Byte (Data (I));
      end loop;
      return Out_Arr;
   end To_OpenSSL_Bytes;

   function Verify_Response
     (Decoded        : Encryption_Response;
      Expected_Token : Token_Bytes) return Verify_Result
   is
      use Adacraft.Crypto.OpenSSL;
      Cipher_S : Byte_Array (1 .. RSA_Size_Bytes) := (others => 0);
      Cipher_T : Byte_Array (1 .. RSA_Size_Bytes) := (others => 0);
      Plain    : Byte_Array (1 .. 512) := (others => 0);
      Cr       : Crypt_Result;
      Secret_Out : Secret_Bytes := (others => 0);
      Secret_Len : Natural := 0;
      Token_Out  : Octets (1 .. 512) := (others => 0);
      Token_Len  : Natural := 0;
      Acc        : Interfaces.Unsigned_8 := 0;
   begin
      if not Initialized or else Is_Null (Priv_Handle) then
         return (Status => Not_Initialized);
      end if;
      for I in 1 .. RSA_Size_Bytes loop
         Cipher_S (I) := Byte (Decoded.Secret_Cipher (I));
         Cipher_T (I) := Byte (Decoded.Token_Cipher (I));
      end loop;
      --  Decrypt secret.
      Rsa_Private_Decrypt
        (Priv_Handle, Cipher_S, RSA_Size_Bytes, Plain, Cr);
      if Cr.Code /= Success then
         return (Status => Decryption_Padding_Failure);
      end if;
      Secret_Len := Cr.Length;
      if Secret_Len /= Secret_Length then
         return (Status => Wrong_Shared_Secret_Length);
      end if;
      for I in 1 .. Secret_Length loop
         Secret_Out (I) := Octet (Plain (I));
      end loop;
      --  Decrypt token.
      for I in Plain'Range loop
         Plain (I) := 0;
      end loop;
      Rsa_Private_Decrypt
        (Priv_Handle, Cipher_T, RSA_Size_Bytes, Plain, Cr);
      if Cr.Code /= Success then
         return (Status => Decryption_Padding_Failure);
      end if;
      Token_Len := Cr.Length;
      if Token_Len /= Token_Length then
         return (Status => Verify_Token_Mismatch);
      end if;
      for I in 1 .. Token_Length loop
         Token_Out (I) := Octet (Plain (I));
      end loop;
      --  Constant-time 4-byte compare: accumulated xor/or, no early return.
      for I in Token_Bytes'Range loop
         declare
            A : constant Interfaces.Unsigned_8 :=
              Interfaces.Unsigned_8 (Token_Out (I - Token_Bytes'First + 1));
            B : constant Interfaces.Unsigned_8 :=
              Interfaces.Unsigned_8 (Expected_Token (I));
         begin
            Acc := Acc or (A xor B);
         end;
      end loop;
      if Acc /= 0 then
         return (Status => Verify_Token_Mismatch);
      end if;
      return (Status => Verify_Ok, Secret => Secret_Out);
   exception
      when others =>
         return (Status => Decryption_Padding_Failure);
   end Verify_Response;

   function Test_Encrypt_With_Public_Key
     (Plain : Octets) return Encrypt_Result
   is
      use Adacraft.Crypto.OpenSSL;
      In_Arr  : Byte_Array (1 .. (if Plain'Length = 0 then 1 else Plain'Length))
        := (others => 0);
      Out_Arr : Byte_Array (1 .. RSA_Size_Bytes) := (others => 0);
      Pub     : RSA_Ptr := Null_RSA;
      Tmp_Der : Byte_Array (1 .. Max_Der_Length) := (others => 0);
      Cr      : Crypt_Result;
      Res     : Encrypt_Result (Encrypt_Ok);
   begin
      if not Initialized or else Cached_Len = 0 then
         return (Status => Not_Initialized);
      end if;
      if Plain'Length = 0 or else Plain'Length > RSA_Size_Bytes - 11 then
         return (Status => Bad_Argument);
      end if;
      for I in Plain'Range loop
         In_Arr (I - Plain'First + 1) := Byte (Plain (I));
      end loop;
      for I in 1 .. Cached_Len loop
         Tmp_Der (I) := Byte (Cached_Der (I));
      end loop;
      declare
         Slice : Byte_Array renames Tmp_Der (1 .. Cached_Len);
         Pr : Handle_Result := Parse_Public_DER (Slice);
      begin
         if Pr.Code /= Success then
            return (Status => Operation_Failed);
         end if;
         Pub := Pr.Handle;
         Rsa_Public_Encrypt
           (Pub, In_Arr, Plain'Length, Out_Arr, Cr);
         declare
            T : RSA_Ptr := Pub;
         begin
            Rsa_Free (T);
         exception
            when others => null;
         end;
         if Cr.Code /= Success or else Cr.Length /= RSA_Size_Bytes then
            return (Status => Operation_Failed);
         end if;
         for I in 1 .. RSA_Size_Bytes loop
            Res.Data (I) := Octet (Out_Arr (I));
         end loop;
         Res.Length := Cr.Length;
         return Res;
      end;
   exception
      when others =>
         return (Status => Operation_Failed);
   end Test_Encrypt_With_Public_Key;

end Adacraft.Protocol.Login_Encryption;
