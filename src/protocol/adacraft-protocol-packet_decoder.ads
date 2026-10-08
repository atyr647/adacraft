with Ada.Streams;
with Interfaces;
with Adacraft.Protocol;

package Adacraft.Protocol.Packet_Decoder is

   String_Max : constant := 255;

   type Field_Kind is
     (Kind_Boolean,
      Kind_Byte,
      Kind_Int,
      Kind_Long,
      Kind_Varint,
      Kind_Varlong,
      Kind_String);

   type Reason_Type is
     (Reason_None,
      Reason_Empty_Body,
      Reason_Truncated_Id,
      Reason_Overlong_Id,
      Reason_Invalid_Id,
      Reason_Truncated_Field,
      Reason_Overlong_Field,
      Reason_String_Negative_Length,
      Reason_String_Too_Long,
      Reason_String_Beyond_Remaining,
      Reason_Invalid_Boolean,
      Reason_Trailing_Bytes);

   type Layout_Array is array (Positive range <>) of Field_Kind;

   Max_Fields : constant := 16;

   type Field_Value is record
      Kind          : Field_Kind := Kind_Boolean;
      Bool_Value    : Boolean := False;
      Byte_Value    : Ada.Streams.Stream_Element := 0;
      Int_Value     : Interfaces.Integer_32 := 0;
      Long_Value    : Interfaces.Integer_64 := 0;
      Varint_Value  : Interfaces.Integer_32 := 0;
      Varlong_Value : Interfaces.Integer_64 := 0;
      Str_Len       : Natural := 0;
      Str_Data      : String (1 .. String_Max) := (others => ' ');
   end record;

   type Field_Array is array (1 .. Max_Fields) of Field_Value;

   type Decode_Result is record
      Status    : Protocol.Status_Kind := Protocol.Rejected;
      Reason    : Reason_Type := Reason_Empty_Body;
      Packet_Id : Natural := 0;
      Fields    : Field_Array;
   end record;

   function Decode
     (Raw_Body : Ada.Streams.Stream_Element_Array;
      Layout   : Layout_Array) return Decode_Result;

end Adacraft.Protocol.Packet_Decoder;
