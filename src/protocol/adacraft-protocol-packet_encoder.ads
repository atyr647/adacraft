with Interfaces;

package Adacraft.Protocol.Packet_Encoder is

   type Status is
     (Ok,
      Overflow,
      Invalid_Packet_Id,
      String_Too_Long,
      Body_Too_Long,
      Invalid_Sequence);

   type Byte_Array is array (Positive range <>) of Interfaces.Unsigned_8;

   type Encoder is limited private;

   procedure Start (E : out Encoder);

   procedure Write_Packet_Id
     (E   : in out Encoder;
      Buf : in out Byte_Array;
      Id  : Interfaces.Integer_32);

   procedure Write_Boolean
     (E   : in out Encoder;
      Buf : in out Byte_Array;
      V   : Boolean);

   procedure Write_Byte
     (E   : in out Encoder;
      Buf : in out Byte_Array;
      V   : Interfaces.Integer_8);

   procedure Write_UByte
     (E   : in out Encoder;
      Buf : in out Byte_Array;
      V   : Interfaces.Unsigned_8);

   procedure Write_Short
     (E   : in out Encoder;
      Buf : in out Byte_Array;
      V   : Interfaces.Integer_16);

   procedure Write_UShort
     (E   : in out Encoder;
      Buf : in out Byte_Array;
      V   : Interfaces.Unsigned_16);

   procedure Write_Int
     (E   : in out Encoder;
      Buf : in out Byte_Array;
      V   : Interfaces.Integer_32);

   procedure Write_Long
     (E   : in out Encoder;
      Buf : in out Byte_Array;
      V   : Interfaces.Integer_64);

   procedure Write_VarInt
     (E   : in out Encoder;
      Buf : in out Byte_Array;
      V   : Interfaces.Integer_32);

   procedure Write_VarLong
     (E   : in out Encoder;
      Buf : in out Byte_Array;
      V   : Interfaces.Integer_64);

   procedure Write_String
     (E         : in out Encoder;
      Buf       : in out Byte_Array;
      Bytes     : Byte_Array;
      Max_Bytes : Natural);

   procedure Write_Bytes
     (E   : in out Encoder;
      Buf : in out Byte_Array;
      B   : Byte_Array);

   function Body_Length (E : Encoder) return Natural;
   function Status_Of (E : Encoder) return Status;

   procedure Finish
     (E         : in     Encoder;
      Buf       : in     Byte_Array;
      Body_Last :    out Natural;
      S         :    out Status);

   procedure Frame
     (E        : in     Encoder;
      Buf      : in     Byte_Array;
      Out_Buf  :    out Byte_Array;
      Out_Last :    out Natural;
      S        :    out Status);

private

   type Encoder is record
      Len        : Natural := 0;
      St         : Status  := Ok;
      Id_Written : Boolean := False;
   end record;

end Adacraft.Protocol.Packet_Encoder;
