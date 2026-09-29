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
end Adacraft.Protocol.Frame;
