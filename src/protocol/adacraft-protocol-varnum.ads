with Interfaces;

--  This package is not in SPARK_Mode because the incremental
--  Try_Decode entry point returns a tri-state status and reports the
--  decoded value and the consumed byte count via out parameters. SPARK
--  does not permit functions to have out parameters; the existing
--  one-shot Decode_Varint / Decode_Varlong remain SPARK-checked where
--  applicable and Try_Decode is implemented to match their semantics
--  for the Ok branch.
package Adacraft.Protocol.Varnum
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

   --  Result of an incremental VarInt decode. Distinct from Status_Kind
   --  (which describes a one-shot whole-buffer decode) because the
   --  wire-format seam must distinguish a legal partial prefix from a
   --  definitively bad one without having consumed any bytes.
   --
   --    Incomplete -- Data (From .. Data'Last) is a legal VarInt prefix
   --                 that simply does not yet contain a terminator byte.
   --                 More bytes are needed; no byte is consumed.
   --    Ok         -- Value holds the decoded unsigned 32-bit value, and
   --                 Consumed is the number of bytes starting at From
   --                 (in 1 .. Max_Varint_Bytes) that produced it.
   --    Malformed  -- Data (From .. Data'Last) cannot start a legal
   --                 VarInt: overlong encoding (> Max_Varint_Bytes),
   --                 bit 31 set on a signed read (i.e. a "negative"
   --                 length), or a non-terminal zero group. No byte is
   --                 consumed; the caller must treat the stream as
   --                 desynchronized (fail-stop).
   type VarInt_Status is (Incomplete, Ok, Malformed);

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

   --  Incremental VarInt decode for the wire-format seam. Drives the
   --  decoder against an arbitrary slice of an already-buffered stream
   --  (e.g. a TCP framing state machine), so it must report a tri-state
   --  outcome without committing to any bytes on failure. Semantically
   --  equivalent to Decode_Varint for the Ok branch, but expressed as
   --  out parameters and a status return so it can be used mid-varint
   --  without re-slicing the buffer.
   --
   --  Parameters:
   --    Data     -- Byte buffer holding the candidate VarInt.
   --    From     -- Index of the first byte to consider.
   --    Value    -- (out) Decoded unsigned 32-bit value; only defined
   --                when the result is Ok.
   --    Consumed -- (out) Number of bytes starting at From that the
   --                decoder consumed. 0 unless the result is Ok, in
   --                which case it lies in 1 .. Max_Varint_Bytes.
   function Try_Decode
     (Data     : Octets;
      From     : Positive;
      Value    : out Interfaces.Unsigned_32;
      Consumed : out Natural) return VarInt_Status
     with Pre =>
       Data'Last < Positive'Last
       and then From <= Data'Last + 1,
       Post =>
         (if Try_Decode'Result = Ok
          then Consumed in 1 .. Max_Varint_Bytes
               and then From + Consumed - 1 <= Data'Last)
         and then (if Try_Decode'Result /= Ok
                   then Consumed = 0);
end Adacraft.Protocol.Varnum;
