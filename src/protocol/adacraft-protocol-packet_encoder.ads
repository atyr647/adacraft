with Ada.Streams;
with Interfaces;
with Adacraft.Protocol.Frame;

package Adacraft.Protocol.Packet_Encoder
is

   subtype Byte is Ada.Streams.Stream_Element;

   --  Decoder field model (mirrors the shipped encoder writes).
   --  Shipped encoder defines no Field_Kind / value record / string kind,
   --  so the decoder layout covers exactly the shipped writes:
   --  Boolean (1 byte), Byte (1 byte), Int (4 bytes big-endian),
   --  Long (8 bytes big-endian). Packet ID is Natural (non-negative
   --  VarInt). String statuses below are reserved; no string kind shipped.

   type Field_Kind is (Field_Boolean, Field_Byte, Field_Int, Field_Long);

   type Field_Value (Kind : Field_Kind := Field_Boolean) is record
      case Kind is
         when Field_Boolean =>
            Bool_Val : Boolean := False;
         when Field_Byte =>
            Byte_Val : Byte := 0;
         when Field_Int =>
            Int_Val : Interfaces.Integer_32 := 0;
         when Field_Long =>
            Long_Val : Interfaces.Integer_64 := 0;
      end case;
   end record;

   --  Caller-supplied expected layout (A-1); one value decoded per entry,
   --  in layout order.

   type Layout_Array is array (Natural range <>) of Field_Kind;

   --  Maximum number of fields decoded in one call. Layouts longer than
   --  this are rejected with Invalid_Length without reading the body.

   Max_Decoded_Fields : constant := 256;

   subtype Field_Count is Natural range 0 .. Max_Decoded_Fields;

   type Value_Array is array (Positive range <>) of Field_Value;

   subtype Bounded_Values is Value_Array (1 .. Max_Decoded_Fields);

   --  Frame body bound reused from Frame (C-4); do not redefine the limit.

   subtype Body_Length is Adacraft.Protocol.Frame.Frame_Body_Length;

   type Body_Bytes is array (Natural range <>) of Byte;

   type Decode_Status is
     (Ok,
      Truncated,
      Overlong_Varint,
      Overlong_Varlong,
      Id_Out_Of_Range,
      Invalid_Length,
      String_Too_Long,
      Invalid_Utf8,
      Trailing_Bytes);

   --  Explicit result, no exceptions (C-6):
   --  Ok => Packet_Id + Values (1 .. Count) in layout order (AC-2).
   --  Error => Status + failure offset; no partial packet (AC-3).
   --  Error_Offset is a 0-based index into Body (bytes consumed before
   --  failure) or 0 when not applicable.

   type Decode_Result (Status : Decode_Status := Ok) is record
      case Status is
         when Ok =>
            Packet_Id : Natural := 0;
            Count     : Field_Count := 0;
            Values    : Bounded_Values;
         when others =>
            Error_Offset : Natural := 0;
      end case;
   end record;

   procedure Decode
     (Body_Data : in Body_Bytes;
      Layout    : in Layout_Array;
      Result    : out Decode_Result)
   with
     SPARK_Mode => On,
     Global => null,
     Pre  =>
       Body_Data'Length <= Adacraft.Protocol.Frame.Max_Frame_Body_Length
       and then Layout'Length <= Max_Decoded_Fields,
     Depends => (Result => (Body_Data, Layout));
   --  Pure decoder (C-5): decodes the packet ID via Varnum then each layout
   --  field in order. Empty body => Truncated. ID with > 5 VarInt bytes =>
   --  Overlong_Varint; negative or out-of-Natural ID => Id_Out_Of_Range.
   --  Every read is bounds-checked; short input => Truncated. Leftover
   --  bytes after the last field => Trailing_Bytes. No I/O, no globals.

   type Encoder_Type
     (Capacity : Positive := Adacraft.Protocol.Frame.Max_Frame_Body_Length)
   is record
      Storage : Ada.Streams.Stream_Element_Array
        (1 .. Adacraft.Protocol.Frame.Max_Frame_Body_Length) :=
          (others => 0);
      Count   : Natural := 0;
      Failed  : Boolean := False;
      Started : Boolean := False;
   end record;

   procedure Start_Packet (E : in out Encoder_Type; Packet_Id : Natural);

   procedure Write_Boolean (E : in out Encoder_Type; V : Boolean);

   procedure Write_Byte (E : in out Encoder_Type; V : Byte);

   procedure Write_Int (E : in out Encoder_Type; V : Interfaces.Integer_32);

   procedure Write_Long (E : in out Encoder_Type; V : Interfaces.Integer_64);

   procedure Get_Framed
     (E      : in out Encoder_Type;
      Output : out Ada.Streams.Stream_Element_Array;
      Last   : out Ada.Streams.Stream_Element_Offset);

   procedure Get_Body
     (E     : in Encoder_Type;
      Data  : out Ada.Streams.Stream_Element_Array;
      Last  : out Ada.Streams.Stream_Element_Offset);

   function Has_Failed (E : Encoder_Type) return Boolean;

   function Length (E : Encoder_Type) return Natural;

end Adacraft.Protocol.Packet_Encoder;
