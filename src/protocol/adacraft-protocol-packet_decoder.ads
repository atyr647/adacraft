with Interfaces;
with Adacraft.Protocol.Varnum;

package Adacraft.Protocol.Packet_Decoder is

   String_Max : constant := 131_068;
   Max_Fields : constant := 32;

   subtype Payload_Array is Adacraft.Protocol.Octets;
   subtype Varnum_Status is Adacraft.Protocol.Varnum.Status_Type;

   type Field_Kind is
     (VarInt,
      VarLong,
      String,
      Boolean,
      Byte,
      Unsigned_Byte,
      Short,
      Unsigned_Short,
      Int,
      Long);

   type Field (Kind : Field_Kind := VarInt) is record
      case Kind is
         when VarInt =>
            VarInt_Value : Interfaces.Integer_32 := 0;
         when VarLong =>
            VarLong_Value : Interfaces.Integer_64 := 0;
         when String =>
            String_Data : Payload_Array (1 .. String_Max) := [others => 0];
            String_Len  : Natural := 0;
         when Boolean =>
            Bool_Value : Standard.Boolean := False;
         when Byte =>
            Byte_Value : Interfaces.Integer_8 := 0;
         when Unsigned_Byte =>
            UByte_Value : Interfaces.Unsigned_8 := 0;
         when Short =>
            Short_Value : Interfaces.Integer_16 := 0;
         when Unsigned_Short =>
            UShort_Value : Interfaces.Unsigned_16 := 0;
         when Int =>
            Int_Value : Interfaces.Integer_32 := 0;
         when Long =>
            Long_Value : Interfaces.Integer_64 := 0;
      end case;
   end record;

   type Layout_Data is array (1 .. Max_Fields) of Field_Kind;

   type Layout_Type is record
      Count : Natural := 0;
      Kinds : Layout_Data := [others => VarInt];
   end record;

   type Field_Array is array (1 .. Max_Fields) of Field;

   type Decode_Status is (Success, Rejected);

   procedure Decode
     (Payload     : in  Payload_Array;
      Layout      : in  Layout_Type;
      Packet_Id   : out Interfaces.Integer_32;
      Fields      : out Field_Array;
      Field_Count : out Natural;
      Status      : out Decode_Status);

end Adacraft.Protocol.Packet_Decoder;
