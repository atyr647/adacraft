with Interfaces;
with Adacraft.Protocol.Varnum;

package Adacraft.Protocol.Packet_Decoder is

   String_Max : constant := 32_767;
   Max_Fields : constant := 16;

   --  String and Boolean are reserved words in Ada, so the corresponding
   --  field-kind literals use the _Field suffix.
   type Field_Kind is
     (VarInt, VarLong, String_Field, Boolean_Field, Byte, Unsigned_Byte,
      Short, Unsigned_Short, Int, Long);

   subtype Byte_Type is Adacraft.Protocol.Octet;
   subtype Varnum_Status is Adacraft.Protocol.Varnum.Status_Type;
   type Byte_Array is array (Positive range <>) of Byte_Type;

   type Layout_Type is array (Positive range <>) of Field_Kind;

   type String_Storage is array (0 .. String_Max - 1) of Byte_Type;

   type Decoded_Field (Kind : Field_Kind := VarInt) is record
      case Kind is
         when VarInt =>
            VarInt_Value : Interfaces.Integer_32;
         when VarLong =>
            VarLong_Value : Interfaces.Integer_64;
         when Boolean_Field =>
            Bool_Value : Boolean;
         when Byte =>
            Byte_Value : Interfaces.Integer_8;
         when Unsigned_Byte =>
            UByte_Value : Interfaces.Unsigned_8;
         when Short =>
            Short_Value : Interfaces.Integer_16;
         when Unsigned_Short =>
            UShort_Value : Interfaces.Unsigned_16;
         when Int =>
            Int_Value : Interfaces.Integer_32;
         when Long =>
            Long_Value : Interfaces.Integer_64;
         when String_Field =>
            Str_Len : Natural range 0 .. String_Max;
            Str_Data : String_Storage;
      end case;
   end record;

   type Field_Array is array (Positive range <>) of Decoded_Field;

   type Decode_Status is
     (Success,
      Empty_Input,
      Truncated_Packet_Id,
      Truncated_Field,
      Bad_VarInt,
      Bad_VarLong,
      Negative_String_Length,
      String_Too_Long,
      String_Overrun,
      Bad_Boolean,
      Trailing_Bytes,
      Too_Many_Fields);

   --  Payload is a packet body without its frame length prefix. On success,
   --  Fields (Fields'First .. Fields'First + Field_Count - 1) contains the
   --  decoded fields in layout order; Field_Count equals Layout'Length.
   --  Layouts longer than Max_Fields are rejected with Too_Many_Fields.
   --  Bad_VarInt and Bad_VarLong report Varnum overlong encodings; truncated
   --  encodings are reported as Truncated_Packet_Id or Truncated_Field,
   --  according to whether the decoder was reading the packet ID or a field.
   procedure Decode
     (Payload     : in  Byte_Array;
      Layout      : in  Layout_Type;
      Status      : out Decode_Status;
      Packet_Id   : out Interfaces.Integer_32;
      Fields      : out Field_Array;
      Field_Count : out Natural);

end Adacraft.Protocol.Packet_Decoder;
