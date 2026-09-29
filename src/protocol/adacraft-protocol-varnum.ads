with Interfaces;

package Adacraft.Protocol.Varnum
  with SPARK_Mode
is
   type Varint_Result is record
      Status : Status_Kind             := Rejected;
      Value  : Interfaces.Unsigned_32  := 0;
      Next   : Natural                 := 0;
   end record;

   type Varlong_Result is record
      Status : Status_Kind             := Rejected;
      Value  : Interfaces.Unsigned_64  := 0;
      Next   : Natural                 := 0;
   end record;

   function Decode_Varint (Buffer : Octets; From : Positive) return Varint_Result
     with Pre =>
       Buffer'Last < Positive'Last
       and then From <= Buffer'Last + 1,
       Post =>
         (if Decode_Varint'Result.Status = Ok
          then Decode_Varint'Result.Next in From + 1 .. From + Max_Varint_Bytes
               and then Decode_Varint'Result.Next - 1 <= Buffer'Last)
         and then (if Decode_Varint'Result.Status /= Ok
                   then Decode_Varint'Result.Next = From);

   function Decode_Varlong (Buffer : Octets; From : Positive) return Varlong_Result
     with Pre =>
       Buffer'Last < Positive'Last
       and then From <= Buffer'Last + 1,
       Post =>
         (if Decode_Varlong'Result.Status = Ok
          then Decode_Varlong'Result.Next in From + 1 .. From + Max_Varlong_Bytes
               and then Decode_Varlong'Result.Next - 1 <= Buffer'Last)
         and then (if Decode_Varlong'Result.Status /= Ok
                   then Decode_Varlong'Result.Next = From);
end Adacraft.Protocol.Varnum;
