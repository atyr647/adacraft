with Ada.Streams;
with Interfaces;
with Adacraft.Protocol.Frame;

package Adacraft.Protocol.Packet_Encoder is
   Default_Capacity : constant Ada.Streams.Stream_Element_Offset := 4_096;

   type Encoder_Type
     (Capacity : Ada.Streams.Stream_Element_Offset := Default_Capacity)
   is limited private;

   procedure Start_Packet
     (E         : in out Encoder_Type;
      Packet_Id :        Interfaces.Integer_32);

   procedure Write_Boolean (E : in out Encoder_Type; V : Boolean);

   procedure Write_Byte (E : in out Encoder_Type; V : Interfaces.Integer_8);

   procedure Write_Int (E : in out Encoder_Type; V : Interfaces.Integer_32);

   procedure Write_Long (E : in out Encoder_Type; V : Interfaces.Integer_64);

   function Has_Failed (E : Encoder_Type) return Boolean;

   function Length (E : Encoder_Type) return Natural;

   procedure Encode_Frame
     (E       : in out Encoder_Type;
      Output  :    out Ada.Streams.Stream_Element_Array;
      Out_Len :    out Natural;
      Success :    out Boolean);

private
   subtype Capacity_Range is Ada.Streams.Stream_Element_Offset
     range 1 .. Adacraft.Protocol.Frame.Max_Frame_Body_Length;

   type Encoder_Type
     (Capacity : Ada.Streams.Stream_Element_Offset := Default_Capacity)
   is limited record
      Buffer  : Ada.Streams.Stream_Element_Array (1 .. Capacity);
      Count   : Natural := 0;
      Failed  : Boolean := False;
      Started : Boolean := False;
   end record;
end Adacraft.Protocol.Packet_Encoder;
