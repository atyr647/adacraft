with Interfaces.C;
with System;

package Adacraft.Crypto.OpenSSL is

   RSA_PKCS1_PADDING : constant Interfaces.C.int := 1;

   subtype Byte is Interfaces.Unsigned_8;
   type Byte_Array is array (Positive range <>) of Byte;

   subtype Der_Buffer is Byte_Array (1 .. 2048);
   subtype Block_Buffer is Byte_Array (1 .. 512);

   type RSA_Ptr is new System.Address;
   type Bignum_Ptr is new System.Address;
   type Evp_Pkey_Ptr is new System.Address;

   Null_RSA    : constant RSA_Ptr      := RSA_Ptr (System.Null_Address);
   Null_Bignum : constant Bignum_Ptr   := Bignum_Ptr (System.Null_Address);
   Null_Evp_Pkey : constant Evp_Pkey_Ptr := Evp_Pkey_Ptr (System.Null_Address);

   type Error_Kind is
     (Success,
      Alloc_Failed,
      Null_Argument,
      Operation_Failed,
      Invalid_Length,
      Generate_Failed,
      Random_Failed,
      Buffer_Too_Small);

   type Handle_Result is record
      Code   : Error_Kind := Operation_Failed;
      Handle : RSA_Ptr := Null_RSA;
   end record;

   type Bignum_Result is record
      Code   : Error_Kind := Operation_Failed;
      Handle : Bignum_Ptr := Null_Bignum;
   end record;

   type Pkey_Result is record
      Code   : Error_Kind := Operation_Failed;
      Handle : Evp_Pkey_Ptr := Null_Evp_Pkey;
   end record;

   type Size_Result is record
      Code : Error_Kind := Operation_Failed;
      Size : Natural := 0;
   end record;

   type Random_Result is record
      Code : Error_Kind := Operation_Failed;
   end record;

   type Der_Result is record
      Code   : Error_Kind := Operation_Failed;
      Length : Natural := 0;
   end record;

   type Crypt_Result is record
      Code   : Error_Kind := Operation_Failed;
      Length : Natural := 0;
   end record;

   function Is_Null (H : RSA_Ptr) return Boolean;
   function Is_Null (H : Bignum_Ptr) return Boolean;
   function Is_Null (H : Evp_Pkey_Ptr) return Boolean;

   function Rsa_New return Handle_Result;
   function Bignum_New return Bignum_Result;
   function Evp_Pkey_New return Pkey_Result;

   procedure Rsa_Free (H : in out RSA_Ptr);
   procedure Bignum_Free (H : in out Bignum_Ptr);
   procedure Evp_Pkey_Free (H : in out Evp_Pkey_Ptr);
   procedure Libcrypto_Free (Ptr : in out System.Address);

   function Bignum_Set_Word (H : Bignum_Ptr; W : Natural) return Error_Kind;

   function Rsa_Generate_Key
     (H : RSA_Ptr; Bits : Positive; Exponent : Natural) return Error_Kind;

   function Generate_Keypair
     (Bits : Positive; Exponent : Natural) return Handle_Result;

   function Rsa_Size (H : RSA_Ptr) return Size_Result;

   procedure Rand_Bytes
     (Data : out Byte_Array; Result : out Random_Result);

   procedure Export_Public_DER
     (H      : RSA_Ptr;
      Der    : out Byte_Array;
      Result : out Der_Result);

   function Parse_Public_DER (Der : Byte_Array) return Handle_Result;

   procedure Rsa_Public_Encrypt
     (Rsa       : RSA_Ptr;
      Plain     : Byte_Array;
      Plain_Len : Natural;
      Cipher    : out Byte_Array;
      Result    : out Crypt_Result;
      Padding   : Interfaces.C.int := RSA_PKCS1_PADDING);

   procedure Rsa_Private_Decrypt
     (Rsa        : RSA_Ptr;
      Cipher     : Byte_Array;
      Cipher_Len : Natural;
      Plain      : out Byte_Array;
      Result     : out Crypt_Result;
      Padding    : Interfaces.C.int := RSA_PKCS1_PADDING);

   function Last_Error return Interfaces.C.unsigned_long;

end Adacraft.Crypto.OpenSSL;
