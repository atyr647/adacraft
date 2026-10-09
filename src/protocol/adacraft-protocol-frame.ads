with Ada.Streams;
with Adacraft.Protocol.Compression;

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

   --  Compressed framing: Packet_Length VarInt | Data_Length VarInt | payload.
   --  Pure helpers with no globals and no world access. The caller owns the
   --  per-connection threshold/active switch; Threshold comparison lives
   --  here so the codec stays dumb. Existing uncompressed Encode_Frame
   --  (Encode below) is untouched.

   function Encode_Compressed_Frame
     (Uncompressed_Payload : Octets;
      Threshold            : Natural) return Octets
     with SPARK_Mode => Off;
   --  Uncompressed_Payload is the ID+body bytes (without any length prefix).
   --  If Uncompressed_Payload'Length < Threshold the result is
   --  Packet_Length | 0x00 | raw bytes, else Packet_Length |
   --  VarInt (uncompressed size) | Compress (payload). Packet_Length covers
   --  the Data_Length bytes plus the payload that follows. Returns an empty
   --  array only when the frame would exceed the protocol bound.

   type Compressed_Split_Status is (Ok, Need_More, Rejected);

   type Compressed_Split is record
      Status        : Compressed_Split_Status := Rejected;
      Data_Length   : Natural                 := 0;
      Payload_First : Natural                 := 0;
      Payload_Last  : Natural                 := 0;
      Next          : Natural                 := 0;
   end record;

   function Split_Compressed_Frame
     (Buffer : Octets;
      From   : Positive) return Compressed_Split
     with SPARK_Mode => Off,
          Pre => Buffer'Last < Positive'Last
                 and then From <= Buffer'Last + 1;
   --  Parses Packet_Length | Data_Length | payload without decompressing.
   --  Payload_First .. Payload_Last is the byte range after the Data_Length
   --  VarInt up to the end of the frame; Next is the first byte after the
   --  frame. Rejected on overlong/empty/oversize Packet_Length or a bad
   --  Data_Length VarInt. No threshold or bound check here; see
   --  Decode_Compressed_Frame.

   procedure Decode_Compressed_Frame
     (Buffer    : in     Octets;
      From      : in     Positive;
      Threshold : in     Natural;
      Data      : in out Compression.Byte_Array_Access;
      Next      :    out Natural;
      Status    :    out Compressed_Split_Status)
     with SPARK_Mode => Off,
          Pre => Buffer'Last < Positive'Last
                 and then From <= Buffer'Last + 1;
   --  Full ingress helper: split, validate, then decompress via
   --  Adacraft.Protocol.Compression. On Ok, Data holds the decompressed
   --  (or, when Data_Length = 0, raw) ID+body bytes and Next is the first
   --  byte after the frame; the caller must free Data with
   --  Adacraft.Protocol.Compression.Free. Rejected (Data = null) when:
   --  framing is bad; declared Data_Length is non-zero but < Threshold;
   --  declared Data_Length exceeds Compression.Max_Decompressed_Size
   --  (checked before allocating/decompressing); decompressed size
   --  mismatches the declared length; or the zlib stream is invalid.
   --  Need_More when Buffer holds only a prefix of the frame.

   --  Ingress framing: stateful, per-connection frame decoder.

   subtype Byte_Array is Ada.Streams.Stream_Element_Array;

   type Feed_Status is (Success, Framing_Error);

   type Decoder_Type is private;

   procedure Feed
     (Decoder  : in out Decoder_Type;
      Chunk    : in     Byte_Array;
      On_Frame : not null access procedure (Frame : in Byte_Array);
      Status   : out    Feed_Status)
     with SPARK_Mode => Off;
   --  Consumes every byte of Chunk in order. Each completed frame body
   --  (without its length prefix) is passed to On_Frame exactly once, during
   --  the call that supplied its last byte; the body is valid only during the
   --  callback. A framing error is terminal: it is reported again by every
   --  later call and no further callbacks are made.

private

   type Decode_Phase is (In_Prefix, In_Body);

   type Decoder_Type is record
      Phase        : Decode_Phase := In_Prefix;
      Failed       : Boolean      := False;

      Prefix_Count : Ada.Streams.Stream_Element_Offset
        range 0 .. Max_Frame_Prefix_Bytes := 0;
      Prefix_Bytes : Byte_Array (1 .. Max_Frame_Prefix_Bytes);

      Body_Length  : Frame_Body_Length := 0;
      Body_Count   : Frame_Body_Length := 0;
      Body_Bytes   : Byte_Array (1 .. Max_Frame_Body_Length);
   end record;

end Adacraft.Protocol.Frame;
