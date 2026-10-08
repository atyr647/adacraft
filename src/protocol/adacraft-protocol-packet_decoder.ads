with Interfaces;
with Ada.Strings.Bounded;

package Adacraft.Protocol.Packet_Decoder is

   String_Max : constant := 32_767;
   Max_Fields : constant := 16;

   type Field_Kind is
     (Kind_VarInt,
      Kind_VarLong,
      Kind_String,
      Kind_Boolean,
      Kind_Byte,
      Kind_Short,
      Kind_Int,
      Kind_Long);

   package Bounded_Strings is new Ada.Strings.Bounded.Generic_Bounded_Length
     (Max => String_Max);

   subtype Bounded_String is Bounded_Strings.Bounded_String;

   type Field (Kind : Field_Kind := Kind_VarInt) is record
      case Kind is
         when Kind_VarInt =>
            VarInt_Value : Interfaces.Integer_32 := 0;
         when Kind_VarLong =>
            VarLong_Value : Interfaces.Integer_64 := 0;
         when Kind_String =>
            String_Value : Bounded_String := Bounded_Strings.Null_Bounded_String;
         when Kind_Boolean =>
            Boolean_Value : Boolean := False;
         when Kind_Byte =>
            Byte_Value : Interfaces.Integer_8 := 0;
         when Kind_Short =>
            Short_Value : Interfaces.Integer_16 := 0;
         when Kind_Int =>
            Int_Value : Interfaces.Integer_32 := 0;
         when Kind_Long =>
            Long_Value : Interfaces.Integer_64 := 0;
      end case;
   end record;

   type Kind_Storage is array (1 .. Max_Fields) of Field_Kind;
   type Field_Storage is array (1 .. Max_Fields) of Field;

   type Kind_Array is array (Positive range <>) of Field_Kind;
   type Field_Array is array (Positive range <>) of Field;

   type Field_Layout is record
      Length : Natural := 0;
      Kinds  : Kind_Storage := (others => Kind_VarInt);
   end record;

   type Decoded_Fields is record
      Length : Natural := 0;
      Values : Field_Storage :=
        (others => (Kind => Kind_VarInt, VarInt_Value => 0));
   end record;

   type Decode_Status is (Success, Rejected);

   procedure Decode
     (Input     : in  Octets;
      Layout    : in  Field_Layout;
      Packet_Id : out Interfaces.Integer_32;
      Fields    : out Decoded_Fields;
      Status    : out Decode_Status);

end Adacraft.Protocol.Packet_Decoder;
