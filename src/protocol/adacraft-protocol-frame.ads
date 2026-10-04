with Ada.Streams;

package Adacraft.Protocol.Frame
  with SPARK_Mode
is
   type Frame_Decode is record
      Status          : Status_Kind := Rejected;
      Packet_Id       : Natural     := 0;
      Payload_First   : Positive    := 1;
      Payload_Last    : Natural     := 0;
      Next            : Natural     := 0;
      Declared_Length : Natural     := 0;
   end record;

   function Decode_Frame (Buffer : Octets; From : Positive) return Frame_Decode
     with Pre =>
       Buffer'Last < Positive'Last and then From <= Buffer'Last + 1;

   --  Egress framing: minimal VarInt length prefix followed by the body.

   Max_Frame_Body_Length  : constant := 2_097_151;
   Max_Frame_Prefix_Bytes : constant := 3;

   subtype Frame_Body_Length is Ada.Streams.Stream_Element_Offset
     range 0 .. Max_Frame_Body_Length;

   type Prefix_Buffer is
     array (1 .. Max_Frame_Prefix_Bytes) of Ada.Streams.Stream_Element;

   type Encode_Status is (Ok, Body_Too_Long, Output_Too_Small);

   procedure Write_Length_Prefix
     (Length : in  Frame_Body_Length;
      Buffer : out Prefix_Buffer;
      Last   : out Ada.Streams.Stream_Element_Offset)
     with SPARK_Mode => Off;
   --  Writes the minimal prefix into Buffer (1 .. Last), Last in 1 .. 3.

   procedure Encode
     (Payload : in  Ada.Streams.Stream_Element_Array;
      Output  : out Ada.Streams.Stream_Element_Array;
      Last    : out Ada.Streams.Stream_Element_Offset;
      Status  : out Encode_Status)
     with SPARK_Mode => Off;
   --  On success Output (Output'First .. Last) holds prefix || Payload.
   --  On rejection no frame is written and Last must not be used.
end Adacraft.Protocol.Frame;
