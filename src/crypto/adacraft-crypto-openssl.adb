with Interfaces.C;
with System;

package body Adacraft.Crypto.OpenSSL is

   use type System.Address;

   function Is_Null (H : RSA_Ptr) return Boolean is
   begin
      return System.Address (H) = System.Null_Address;
   end Is_Null;

   function Is_Null (H : Bignum_Ptr) return Boolean is
   begin
      return System.Address (H) = System.Null_Address;
   end Is_Null;

   function Is_Null (H : Evp_Pkey_Ptr) return Boolean is
   begin
      return System.Address (H) = System.Null_Address;
   end Is_Null;

   --  Raw C imports.  Pragma Import only; no logic here. --------------------

   function C_RSA_New return System.Address;
   pragma Import (C, C_RSA_New, "RSA_new");

   function C_RSA_Generate_Key_Ex
     (Rsa  : System.Address;
      Bits : Interfaces.C.int;
      E    : System.Address;
      Cb   : System.Address) return Interfaces.C.int;
   pragma Import (C, C_RSA_Generate_Key_Ex, "RSA_generate_key_ex");

   procedure C_RSA_Free (Rsa : System.Address);
   pragma Import (C, C_RSA_Free, "RSA_free");

   function C_RSA_Size (Rsa : System.Address) return Interfaces.C.int;
   pragma Import (C, C_RSA_Size, "RSA_size");

   function C_RSA_Up_Ref (Rsa : System.Address) return Interfaces.C.int;
   pragma Import (C, C_RSA_Up_Ref, "RSA_up_ref");

   function C_RSA_Public_Encrypt
     (Flen    : Interfaces.C.int;
      From    : System.Address;
      To      : System.Address;
      Rsa     : System.Address;
      Padding : Interfaces.C.int) return Interfaces.C.int;
   pragma Import (C, C_RSA_Public_Encrypt, "RSA_public_encrypt");

   function C_RSA_Private_Decrypt
     (Flen    : Interfaces.C.int;
      From    : System.Address;
      To      : System.Address;
      Rsa     : System.Address;
      Padding : Interfaces.C.int) return Interfaces.C.int;
   pragma Import (C, C_RSA_Private_Decrypt, "RSA_private_decrypt");

   function C_BN_New return System.Address;
   pragma Import (C, C_BN_New, "BN_new");

   function C_BN_Set_Word
     (A : System.Address;
      W : Interfaces.C.unsigned_long) return Interfaces.C.int;
   pragma Import (C, C_BN_Set_Word, "BN_set_word");

   procedure C_BN_Free (A : System.Address);
   pragma Import (C, C_BN_Free, "BN_free");

   function C_EVP_PKEY_New return System.Address;
   pragma Import (C, C_EVP_PKEY_New, "EVP_PKEY_new");

   --  EVP_PKEY_assign_RSA is a macro for EVP_PKEY_assign (type 6).
   EVP_PKEY_RSA : constant := 6;

   function C_EVP_PKEY_Assign
     (Pkey : System.Address;
      Kind : Interfaces.C.int;
      Key  : System.Address) return Interfaces.C.int;
   pragma Import (C, C_EVP_PKEY_Assign, "EVP_PKEY_assign");

   procedure C_EVP_PKEY_Free (Pkey : System.Address);
   pragma Import (C, C_EVP_PKEY_Free, "EVP_PKEY_free");

   function C_EVP_PKEY_Get1_RSA
     (Pkey : System.Address) return System.Address;
   pragma Import (C, C_EVP_PKEY_Get1_RSA, "EVP_PKEY_get1_RSA");

   function C_I2D_PUBKEY
     (Pkey : System.Address;
      Pp   : System.Address) return Interfaces.C.int;
   pragma Import (C, C_I2D_PUBKEY, "i2d_PUBKEY");

   function C_D2I_PUBKEY
     (A      : System.Address;
      Pp     : System.Address;
      Length : Interfaces.C.long) return System.Address;
   pragma Import (C, C_D2I_PUBKEY, "d2i_PUBKEY");

   function C_RAND_Bytes
     (Buf : System.Address;
      Num : Interfaces.C.int) return Interfaces.C.int;
   pragma Import (C, C_RAND_Bytes, "RAND_bytes");

   --  OPENSSL_free is a macro for CRYPTO_free (ptr, file, line).
   procedure C_CRYPTO_Free
     (Ptr  : System.Address;
      File : System.Address;
      Line : Interfaces.C.int);
   pragma Import (C, C_CRYPTO_Free, "CRYPTO_free");

   function C_ERR_Get_Error return Interfaces.C.unsigned_long;
   pragma Import (C, C_ERR_Get_Error, "ERR_get_error");

   --  Local helpers to call the DER helpers that take pointer-to-pointer. --

   --  i2d with a null output pointer returns the encoded length.
   function I2D_Length (Pkey : System.Address) return Interfaces.C.int is
   begin
      return C_I2D_PUBKEY (Pkey, System.Null_Address);
   end I2D_Length;

   --  Wrappers ----------------------------------------------------------------

   function Rsa_New return Handle_Result is
      Addr : System.Address := System.Null_Address;
   begin
      Addr := C_RSA_New;
      if Addr = System.Null_Address then
         return (Code => Alloc_Failed, Handle => Null_RSA);
      end if;
      return (Code => Success, Handle => RSA_Ptr (Addr));
   exception
      when others =>
         return (Code => Alloc_Failed, Handle => Null_RSA);
   end Rsa_New;

   function Bignum_New return Bignum_Result is
      Addr : System.Address := System.Null_Address;
   begin
      Addr := C_BN_New;
      if Addr = System.Null_Address then
         return (Code => Alloc_Failed, Handle => Null_Bignum);
      end if;
      return (Code => Success, Handle => Bignum_Ptr (Addr));
   exception
      when others =>
         return (Code => Alloc_Failed, Handle => Null_Bignum);
   end Bignum_New;

   function Evp_Pkey_New return Pkey_Result is
      Addr : System.Address := System.Null_Address;
   begin
      Addr := C_EVP_PKEY_New;
      if Addr = System.Null_Address then
         return (Code => Alloc_Failed, Handle => Null_Evp_Pkey);
      end if;
      return (Code => Success, Handle => Evp_Pkey_Ptr (Addr));
   exception
      when others =>
         return (Code => Alloc_Failed, Handle => Null_Evp_Pkey);
   end Evp_Pkey_New;

   procedure Rsa_Free (H : in out RSA_Ptr) is
   begin
      if Is_Null (H) then
         return;
      end if;
      C_RSA_Free (System.Address (H));
      H := Null_RSA;
   exception
      when others =>
         H := Null_RSA;
   end Rsa_Free;

   procedure Bignum_Free (H : in out Bignum_Ptr) is
   begin
      if Is_Null (H) then
         return;
      end if;
      C_BN_Free (System.Address (H));
      H := Null_Bignum;
   exception
      when others =>
         H := Null_Bignum;
   end Bignum_Free;

   procedure Evp_Pkey_Free (H : in out Evp_Pkey_Ptr) is
   begin
      if Is_Null (H) then
         return;
      end if;
      C_EVP_PKEY_Free (System.Address (H));
      H := Null_Evp_Pkey;
   exception
      when others =>
         H := Null_Evp_Pkey;
   end Evp_Pkey_Free;

   procedure Libcrypto_Free (Ptr : in out System.Address) is
   begin
      if Ptr = System.Null_Address then
         return;
      end if;
      C_CRYPTO_Free (Ptr, System.Null_Address, 0);
      Ptr := System.Null_Address;
   exception
      when others =>
         Ptr := System.Null_Address;
   end Libcrypto_Free;

   function Bignum_Set_Word (H : Bignum_Ptr; W : Natural) return Error_Kind is
      Rc : Interfaces.C.int := 0;
   begin
      if Is_Null (H) then
         return Null_Argument;
      end if;
      Rc := C_BN_Set_Word
        (System.Address (H), Interfaces.C.unsigned_long (W));
      if Rc /= 1 then
         return Operation_Failed;
      end if;
      return Success;
   exception
      when others =>
         return Operation_Failed;
   end Bignum_Set_Word;

   function Rsa_Generate_Key
     (H : RSA_Ptr; Bits : Positive; Exponent : Natural) return Error_Kind
   is
      Bn : Bignum_Ptr := Null_Bignum;
      Br : Bignum_Result;
      Rc : Interfaces.C.int := 0;
   begin
      if Is_Null (H) then
         return Null_Argument;
      end if;
      if Bits < 256 or else Bits > 16384 or else Exponent = 0 then
         return Invalid_Length;
      end if;
      Br := Bignum_New;
      if Br.Code /= Success then
         return Alloc_Failed;
      end if;
      Bn := Br.Handle;
      if Bignum_Set_Word (Bn, Exponent) /= Success then
         Bignum_Free (Bn);
         return Operation_Failed;
      end if;
      Rc := C_RSA_Generate_Key_Ex
        (System.Address (H),
         Interfaces.C.int (Bits),
         System.Address (Bn),
         System.Null_Address);
      Bignum_Free (Bn);
      if Rc /= 1 then
         return Generate_Failed;
      end if;
      return Success;
   exception
      when others =>
         declare
            Tmp : Bignum_Ptr := Bn;
         begin
            Bignum_Free (Tmp);
         exception
            when others => null;
         end;
         return Generate_Failed;
   end Rsa_Generate_Key;

   function Generate_Keypair
     (Bits : Positive; Exponent : Natural) return Handle_Result
   is
      R : Handle_Result := Rsa_New;
   begin
      if R.Code /= Success then
         return R;
      end if;
      if Rsa_Generate_Key (R.Handle, Bits, Exponent) /= Success then
         declare
            Tmp : RSA_Ptr := R.Handle;
         begin
            Rsa_Free (Tmp);
         exception
            when others => null;
         end;
         return (Code => Generate_Failed, Handle => Null_RSA);
      end if;
      return R;
   exception
      when others =>
         return (Code => Generate_Failed, Handle => Null_RSA);
   end Generate_Keypair;

   function Rsa_Size (H : RSA_Ptr) return Size_Result is
      Rc : Interfaces.C.int := 0;
   begin
      if Is_Null (H) then
         return (Code => Null_Argument, Size => 0);
      end if;
      Rc := C_RSA_Size (System.Address (H));
      if Rc <= 0 then
         return (Code => Operation_Failed, Size => 0);
      end if;
      return (Code => Success, Size => Natural (Rc));
   exception
      when others =>
         return (Code => Operation_Failed, Size => 0);
   end Rsa_Size;

   procedure Rand_Bytes
     (Data : out Byte_Array; Result : out Random_Result)
   is
      Rc : Interfaces.C.int := 0;
   begin
      if Data'Length = 0 then
         Result := (Code => Invalid_Length);
         return;
      end if;
      if Data'Length > Interfaces.C.int'Last then
         for I in Data'Range loop
            Data (I) := 0;
         end loop;
         Result := (Code => Invalid_Length);
         return;
      end if;
      --  Zero first so a short/failed call never leaves stale bytes.
      for I in Data'Range loop
         Data (I) := 0;
      end loop;
      Rc := C_RAND_Bytes (Data'Address, Interfaces.C.int (Data'Length));
      if Rc /= 1 then
         for I in Data'Range loop
            Data (I) := 0;
         end loop;
         Result := (Code => Random_Failed);
         return;
      end if;
      Result := (Code => Success);
   exception
      when others =>
         --  Best effort cleanup; never propagate.
         begin
            for I in Data'Range loop
               Data (I) := 0;
            end loop;
         exception
            when others => null;
         end;
         Result := (Code => Random_Failed);
   end Rand_Bytes;

   procedure Export_Public_DER
     (H      : RSA_Ptr;
      Der    : out Byte_Array;
      Result : out Der_Result)
   is
      Pkey     : System.Address := System.Null_Address;
      Len      : Interfaces.C.int := 0;
      Tmp_Der  : Der_Buffer := (others => 0);
      --  i2d advances the pointer it is given, so keep base + cursor.
      Cursor   : System.Address;
      Arg_Addr : aliased System.Address;
      Rc       : Interfaces.C.int := 0;
      Assign   : Interfaces.C.int := 0;
      Up       : Interfaces.C.int := 0;
   begin
      Result := (Code => Operation_Failed, Length => 0);
      for I in Der'Range loop
         Der (I) := 0;
      end loop;
      if Is_Null (H) then
         Result.Code := Null_Argument;
         return;
      end if;
      if Der'Length = 0 then
         Result.Code := Invalid_Length;
         return;
      end if;

      Pkey := C_EVP_PKEY_New;
      if Pkey = System.Null_Address then
         Result.Code := Alloc_Failed;
         return;
      end if;

      --  Up-ref so freeing the temporary EVP_PKEY does not destroy H.
      Up := C_RSA_Up_Ref (System.Address (H));
      if Up /= 1 then
         C_EVP_PKEY_Free (Pkey);
         Result.Code := Operation_Failed;
         return;
      end if;

      Assign := C_EVP_PKEY_Assign
        (Pkey, EVP_PKEY_RSA, System.Address (H));
      if Assign /= 1 then
         --  Assign failed: drop the extra reference we just took.
         C_RSA_Free (System.Address (H));
         C_EVP_PKEY_Free (Pkey);
         Result.Code := Operation_Failed;
         return;
      end if;

      Len := I2D_Length (Pkey);
      if Len <= 0 or else Natural (Len) > Tmp_Der'Length
        or else Natural (Len) > Der'Length
      then
         C_EVP_PKEY_Free (Pkey);
         if Len <= 0 then
            Result.Code := Operation_Failed;
         else
            Result.Code := Buffer_Too_Small;
         end if;
         return;
      end if;

      Cursor := Tmp_Der'Address;
      Arg_Addr := Cursor;
      Rc := C_I2D_PUBKEY (Pkey, Arg_Addr'Address);
      C_EVP_PKEY_Free (Pkey);
      if Rc <= 0 or else Natural (Rc) /= Natural (Len) then
         Result := (Code => Operation_Failed, Length => 0);
         return;
      end if;
      for I in 1 .. Natural (Rc) loop
         Der (Der'First + (I - 1)) := Tmp_Der (I);
      end loop;
      Result := (Code => Success, Length => Natural (Rc));
   exception
      when others =>
         Result := (Code => Operation_Failed, Length => 0);
   end Export_Public_DER;

   function Parse_Public_DER (Der : Byte_Array) return Handle_Result is
      Tmp    : Der_Buffer := (others => 0);
      Cursor : aliased System.Address;
      Pkey   : System.Address := System.Null_Address;
      Rsa    : System.Address := System.Null_Address;
   begin
      if Der'Length = 0 or else Der'Length > Tmp'Length then
         return (Code => Invalid_Length, Handle => Null_RSA);
      end if;
      for I in Der'Range loop
         Tmp (Tmp'First + (I - Der'First)) := Der (I);
      end loop;
      Cursor := Tmp'Address;
      Pkey := C_D2I_PUBKEY
        (System.Null_Address, Cursor'Address,
         Interfaces.C.long (Der'Length));
      if Pkey = System.Null_Address then
         return (Code => Operation_Failed, Handle => Null_RSA);
      end if;
      Rsa := C_EVP_PKEY_Get1_RSA (Pkey);
      C_EVP_PKEY_Free (Pkey);
      if Rsa = System.Null_Address then
         return (Code => Operation_Failed, Handle => Null_RSA);
      end if;
      return (Code => Success, Handle => RSA_Ptr (Rsa));
   exception
      when others =>
         return (Code => Operation_Failed, Handle => Null_RSA);
   end Parse_Public_DER;

   procedure Rsa_Public_Encrypt
     (Rsa       : RSA_Ptr;
      Plain     : Byte_Array;
      Plain_Len : Natural;
      Cipher    : out Byte_Array;
      Result    : out Crypt_Result;
      Padding   : Interfaces.C.int := RSA_PKCS1_PADDING)
   is
      Tmp_Plain  : Block_Buffer := (others => 0);
      Tmp_Cipher : Block_Buffer := (others => 0);
      Sz         : Size_Result;
      Rc         : Interfaces.C.int := 0;
   begin
      Result := (Code => Operation_Failed, Length => 0);
      for I in Cipher'Range loop
         Cipher (I) := 0;
      end loop;
      if Is_Null (Rsa) then
         Result.Code := Null_Argument;
         return;
      end if;
      Sz := Rsa_Size (Rsa);
      if Sz.Code /= Success then
         Result.Code := Sz.Code;
         return;
      end if;
      if Plain_Len > Plain'Length or else Plain_Len > Tmp_Plain'Length
        or else Cipher'Length < Sz.Size
      then
         Result.Code := Invalid_Length;
         return;
      end if;
      for I in 1 .. Plain_Len loop
         Tmp_Plain (I) := Plain (Plain'First + (I - 1));
      end loop;
      Rc := C_RSA_Public_Encrypt
        (Interfaces.C.int (Plain_Len),
         Tmp_Plain'Address, Tmp_Cipher'Address,
         System.Address (Rsa), Padding);
      if Rc <= 0 then
         Result.Code := Operation_Failed;
         return;
      end if;
      for I in 1 .. Natural (Rc) loop
         Cipher (Cipher'First + (I - 1)) := Tmp_Cipher (I);
      end loop;
      Result := (Code => Success, Length => Natural (Rc));
   exception
      when others =>
         Result := (Code => Operation_Failed, Length => 0);
   end Rsa_Public_Encrypt;

   procedure Rsa_Private_Decrypt
     (Rsa        : RSA_Ptr;
      Cipher     : Byte_Array;
      Cipher_Len : Natural;
      Plain      : out Byte_Array;
      Result     : out Crypt_Result;
      Padding    : Interfaces.C.int := RSA_PKCS1_PADDING)
   is
      Tmp_Cipher : Block_Buffer := (others => 0);
      Tmp_Plain  : Block_Buffer := (others => 0);
      Sz         : Size_Result;
      Rc         : Interfaces.C.int := 0;
   begin
      Result := (Code => Operation_Failed, Length => 0);
      for I in Plain'Range loop
         Plain (I) := 0;
      end loop;
      if Is_Null (Rsa) then
         Result.Code := Null_Argument;
         return;
      end if;
      Sz := Rsa_Size (Rsa);
      if Sz.Code /= Success then
         Result.Code := Sz.Code;
         return;
      end if;
      if Cipher_Len > Cipher'Length or else Cipher_Len > Tmp_Cipher'Length
        or else Cipher_Len /= Sz.Size or else Plain'Length = 0
      then
         Result.Code := Invalid_Length;
         return;
      end if;
      for I in 1 .. Cipher_Len loop
         Tmp_Cipher (I) := Cipher (Cipher'First + (I - 1));
      end loop;
      Rc := C_RSA_Private_Decrypt
        (Interfaces.C.int (Cipher_Len),
         Tmp_Cipher'Address, Tmp_Plain'Address,
         System.Address (Rsa), Padding);
      if Rc <= 0 then
         Result.Code := Operation_Failed;
         return;
      end if;
      if Natural (Rc) > Plain'Length then
         Result.Code := Buffer_Too_Small;
         return;
      end if;
      for I in 1 .. Natural (Rc) loop
         Plain (Plain'First + (I - 1)) := Tmp_Plain (I);
      end loop;
      Result := (Code => Success, Length => Natural (Rc));
   exception
      when others =>
         Result := (Code => Operation_Failed, Length => 0);
   end Rsa_Private_Decrypt;

   function Last_Error return Interfaces.C.unsigned_long is
   begin
      return C_ERR_Get_Error;
   exception
      when others =>
         return 0;
   end Last_Error;

end Adacraft.Crypto.OpenSSL;
