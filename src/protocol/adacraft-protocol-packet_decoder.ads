with Interfaces;
with Adacraft.Protocol;

package Adacraft.Protocol.Packet_Decoder is

   String_Max : constant := 32_767;
   Max_Fields : constant := 32;

   subtype Byte is Adacraft.Protocol.Octet;
   subtype Byte_Array is Adacraft.Protocol.Octets;

   type Field_Kind is
     (Kind_VarInt,
      Kind_VarLong,
      Kind_String,
      Kind_Boolean,
      Kind_I8,
      Kind_I16,
      Kind_I32,
      Kind_I64);

   type Kind_Array is array (1 .. Max_Fields) of Field_Kind;

   type Layout is record
      Count : Natural range 0 .. Max_Fields := 0;
      Kinds : Kind_Array := (others => Kind_VarInt);
   end record;

   type Field (Kind : Field_Kind := Kind_VarInt) is record
      case Kind is
         when Kind_VarInt | Kind_I32 =>
            Value_32 : Interfaces.Integer_32 := 0;
         when Kind_VarLong | Kind_I64 =>
            Value_64 : Interfaces.Integer_64 := 0;
         when Kind_String =>
            String_Offset : Natural := 0;
            String_Length : Natural range 0 .. String_Max := 0;
         when Kind_Boolean =>
            Boolean_Value : Boolean := False;
         when Kind_I8 =>
            Value_8 : Interfaces.Integer_8 := 0;
         when Kind_I16 =>
            Value_16 : Interfaces.Integer_16 := 0;
      end case;
   end record;

   type Field_Array is array (1 .. Max_Fields) of Field;

   type String_Buffer is array (1 .. String_Max) of Byte;

   type Decode_Result is record
      Success     : Boolean := False;
      Packet_Id   : Interfaces.Integer_32 := 0;
      Field_Count : Natural range 0 .. Max_Fields := 0;
      Fields      : Field_Array;
      Strings     : String_Buffer := (others => 0);
   end record;

   procedure Decode
     (Data : in Byte_Array;
      L    : in Layout;
      R    : out Decode_Result);

end Adacraft.Protocol.Packet_Decoder;
