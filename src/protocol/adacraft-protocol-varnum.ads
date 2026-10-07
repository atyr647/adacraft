with Interfaces;

package Adacraft.Protocol.Varnum is

   type Status is (Ok, Truncated, Overlong);

   Max_VarInt_Encoded_Length : constant := 5;

   type Byte is mod 2**8;
   type Byte_Array is array (Integer range <>) of Byte;

   type Encoded_Bytes is array (1 .. Max_VarInt_Encoded_Length) of Byte;

   type Encoding is record
      Bytes  : Encoded_Bytes;
      Length : Natural range 0 .. Max_VarInt_Encoded_Length;
   end record;

   function Encode (Value : Interfaces.Integer_32) return Encoding;
   --  Minimal canonical VarInt of the two's-complement bit pattern.

   procedure Decode
     (Data     : Byte_Array;
      Result   : out Status;
      Value    : out Interfaces.Integer_32;
      Consumed : out Natural);
   --  Reads at most 5 bytes of Data. On Truncated or Overlong, Value and
   --  Consumed are 0. Non-minimal forms within 5 bytes are accepted.

end Adacraft.Protocol.Varnum;
