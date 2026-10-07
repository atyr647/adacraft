with Interfaces;

package Adacraft.Protocol.Buffer is
   type Writer (Capacity : Positive) is record
      Data   : Octets (1 .. Capacity) := (others => 0);
      Len    : Natural := 0;
      Failed : Boolean := False;
   end record;

   procedure Reset (W : in out Writer);
   procedure Put_Octet (W : in out Writer; Value : Octet);
   procedure Put_Bytes (W : in out Writer; Value : Octets);
   procedure Put_Varint (W : in out Writer; Value : Interfaces.Unsigned_32);
   procedure Put_U16 (W : in out Writer; Value : Interfaces.Unsigned_16);
   procedure Put_U64 (W : in out Writer; Value : Interfaces.Unsigned_64);
   procedure Put_String (W : in out Writer; Value : String);

   type Varint_Result is record
      Status : Status_Kind            := Rejected;
      Value  : Interfaces.Unsigned_32 := 0;
      Next   : Natural                := 0;
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

   type String_Decode is record
      Status : Status_Kind := Rejected;
      Text   : String (1 .. 32767) := (others => ' ');
      Length : Natural := 0;
      Next   : Natural := 0;
   end record;

   function Decode_String
     (Buffer : Octets; From : Positive; Max_Chars : Positive) return String_Decode;

   function Decode_U16
     (Buffer : Octets; From : Positive) return Interfaces.Unsigned_16;

   function U16_Ok (Buffer : Octets; From : Positive) return Boolean;

   function Decode_U64
     (Buffer : Octets; From : Positive) return Interfaces.Unsigned_64;

   function U64_Ok (Buffer : Octets; From : Positive) return Boolean;
end Adacraft.Protocol.Buffer;
