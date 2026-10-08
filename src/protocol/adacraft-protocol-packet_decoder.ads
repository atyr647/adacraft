with Ada.Streams;
with Interfaces;

package Adacraft.Protocol.Packet_Decoder is

   subtype Byte is Ada.Streams.Stream_Element;
   subtype Body_Array is Ada.Streams.Stream_Element_Array;
   subtype SEO is Ada.Streams.Stream_Element_Offset;

   subtype Packet_Id_Type is Natural range 0 .. 2_147_483_647;

   --  String bound in bytes (shipped unit). #210 defines no string
   --  primitive; this bound mirrors Buffer.Decode_String's 32_767 limit
   --  so decoder storage stays bounded and T-1/T-9 have an oracle value.
   String_Max : constant := 32_767;
   subtype String_Index is Positive range 1 .. String_Max;
   type String_Data_Array is array (String_Index) of Byte;

   type Field_Kind is
     (FK_Boolean, FK_Byte, FK_Int, FK_Long, FK_Varint, FK_Varlong,
      FK_String);

   type Field_Value (Kind : Field_Kind := FK_Boolean) is record
      case Kind is
         when FK_Boolean => B   : Boolean := False;
         when FK_Byte    => U8  : Byte := 0;
         when FK_Int     => I32 : Interfaces.Integer_32 := 0;
         when FK_Long    => I64 : Interfaces.Integer_64 := 0;
         when FK_Varint  => V32 : Interfaces.Integer_32 := 0;
         when FK_Varlong => V64 : Interfaces.Integer_64 := 0;
         when FK_String  =>
            Str_Len  : Natural := 0;
            Str_Data : String_Data_Array := (others => 0);
      end case;
   end record;

   Max_Fields : constant := 64;

   type Layout_Array is array (Positive range <>) of Field_Kind;
   type Field_Array is array (Positive range <>) of Field_Value;

   type Fail_Reason is
     (None, Empty_Body, Truncated, Overlong_Varint, Overlong_Varlong,
      Id_Out_Of_Range, String_Length_Invalid, String_Over_Max,
      String_Content_Invalid, Trailing_Bytes);

   type Decode_Result (Ok : Boolean := False) is record
      case Ok is
         when True =>
            Id     : Packet_Id_Type := 0;
            Count  : Natural := 0;
            Fields : Field_Array (1 .. Max_Fields) :=
              (others => (Kind => FK_Boolean, B => False));
         when False =>
            Reason : Fail_Reason := None;
      end case;
   end record;

   function Decode
     (Raw    : Body_Array;
      Layout : Layout_Array) return Decode_Result;

end Adacraft.Protocol.Packet_Decoder;
