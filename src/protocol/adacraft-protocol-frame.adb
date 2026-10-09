with Interfaces;
with Adacraft.Protocol.Compression;
with Adacraft.Protocol.Varnum;

package body Adacraft.Protocol.Frame
  with SPARK_Mode
is
   use type Interfaces.Unsigned_32;
   use type Ada.Streams.Stream_Element_Offset;
   use type Ada.Streams.Stream_Element;
   use type Adacraft.Protocol.Compression.Byte_Array_Access;
   use type Adacraft.Protocol.Varnum.Status_Type;

   function Remaining (Last : Natural; From : Natural) return Natural is
     (if From > Last then 0 else Last - From + 1);

   procedure Write_Length_Prefix
     (Length : in  Frame_Body_Length;
      Buffer : out Prefix_Buffer;
      Last   : out Ada.Streams.Stream_Element_Offset)
     with SPARK_Mode => Off
   is
      Left  : Frame_Body_Length := Length;
      Digit : Ada.Streams.Stream_Element;
      Index : Positive := 1;
   begin
      Buffer := (others => 0);
      Last := 1;
      loop
         Digit := Ada.Streams.Stream_Element (Left mod 128);
         Left := Left / 128;
         if Left > 0 then
            Buffer (Index) := Digit or 16#80#;
         else
            Buffer (Index) := Digit;
         end if;
         Last := Ada.Streams.Stream_Element_Offset (Index);
         exit when Left = 0;
         Index := Index + 1;
      end loop;
   end Write_Length_Prefix;

   procedure Encode
     (Payload : in  Ada.Streams.Stream_Element_Array;
      Output  : out Ada.Streams.Stream_Element_Array;
      Last    : out Ada.Streams.Stream_Element_Offset;
      Status  : out Encode_Status)
     with SPARK_Mode => Off
   is
      Prefix     : Prefix_Buffer;
      Prefix_Len : Ada.Streams.Stream_Element_Offset;
      Frame_Len  : Ada.Streams.Stream_Element_Offset;
      Body_First : Ada.Streams.Stream_Element_Offset;
   begin
      if Output'First > Ada.Streams.Stream_Element_Offset'First then
         Last := Output'First - 1;
      else
         Last := Output'First;
      end if;
      Status := Output_Too_Small;

      if Payload'Length > Max_Frame_Body_Length then
         Status := Body_Too_Long;
         return;
      end if;

      Write_Length_Prefix
        (Frame_Body_Length (Payload'Length), Prefix, Prefix_Len);
      Frame_Len := Prefix_Len + Payload'Length;

      if Output'Length < Frame_Len then
         return;
      end if;

      for I in 1 .. Prefix_Len loop
         Output (Output'First + I - 1) := Prefix (Integer (I));
      end loop;

      if Payload'Length > 0 then
         Body_First := Output'First + Prefix_Len;
         Output (Body_First .. Body_First + Payload'Length - 1) := Payload;
      end if;

      Last := Output'First + Frame_Len - 1;
      Status := Ok;
   end Encode;

   procedure Feed
     (Decoder  : in out Decoder_Type;
      Chunk    : in     Byte_Array;
      On_Frame : not null access procedure (Frame : in Byte_Array);
      Status   : out    Feed_Status)
     with SPARK_Mode => Off
   is
      Empty_Body : constant Byte_Array (1 .. 0) := (others => 0);
      Value      : Ada.Streams.Stream_Element;
   begin
      if Decoder.Failed then
         Status := Framing_Error;
         return;
      end if;

      for I in Chunk'Range loop
         Value := Chunk (I);

         case Decoder.Phase is
            when In_Prefix =>
               Decoder.Prefix_Count := Decoder.Prefix_Count + 1;
               Decoder.Prefix_Bytes (Decoder.Prefix_Count) := Value;

               if (Value and 16#80#) /= 0 then
                  if Decoder.Prefix_Count = Max_Frame_Prefix_Bytes then
                     Decoder.Failed := True;
                     Status := Framing_Error;
                     return;
                  end if;
               else
                  declare
                     Length : Ada.Streams.Stream_Element_Offset := 0;
                     Mult   : Ada.Streams.Stream_Element_Offset := 1;
                  begin
                     for J in 1 .. Decoder.Prefix_Count loop
                        Length := Length
                          + Ada.Streams.Stream_Element_Offset
                              (Decoder.Prefix_Bytes (J) and 16#7F#) * Mult;
                        Mult := Mult * 128;
                     end loop;

                     if Length > Max_Frame_Body_Length then
                        Decoder.Failed := True;
                        Status := Framing_Error;
                        return;
                     end if;

                     Decoder.Body_Length := Length;
                  end;

                  Decoder.Body_Count := 0;
                  if Decoder.Body_Length = 0 then
                     On_Frame (Empty_Body);
                     Decoder.Phase := In_Prefix;
                     Decoder.Prefix_Count := 0;
                  else
                     Decoder.Phase := In_Body;
                  end if;
               end if;

            when In_Body =>
               Decoder.Body_Count := Decoder.Body_Count + 1;
               Decoder.Body_Bytes (Decoder.Body_Count) := Value;

               if Decoder.Body_Count = Decoder.Body_Length then
                  Decoder.Phase := In_Prefix;
                  Decoder.Prefix_Count := 0;
                  On_Frame (Decoder.Body_Bytes (1 .. Decoder.Body_Length));
                  Decoder.Body_Count := 0;
               end if;
         end case;
      end loop;

      Status := Success;
   end Feed;

   function Encode_Compressed_Frame
     (Uncompressed_Payload : Octets;
      Threshold            : Natural) return Octets
     with SPARK_Mode => Off
   is
      package V renames Adacraft.Protocol.Varnum;
      package C renames Adacraft.Protocol.Compression;
      Enc    : C.Encode_Result;
      Chunk  : C.Byte_Array_Access := null;
      Len32  : Interfaces.Integer_32;
      Prefix : Octets (1 .. 5) := (others => 0);
      W      : Natural := 0;
      St     : V.Status_Type := V.Buffer_Too_Small;
   begin
      C.Encode (Threshold, Uncompressed_Payload, Enc);
      if not Enc.Ok or else Enc.Data = null then
         return (1 .. 0 => 0);
      end if;
      Chunk := Enc.Data;
      if Chunk.all'Length = 0
        or else Natural'Last - Chunk.all'Length < 5
      then
         C.Free (Chunk);
         Enc.Data := null;
         C.Free (Enc);
         return (1 .. 0 => 0);
      end if;
      if Chunk.all'Length > Max_Frame_Body_Length
        or else Chunk.all'Length > Max_Packet_Length
      then
         C.Free (Chunk);
         Enc.Data := null;
         C.Free (Enc);
         return (1 .. 0 => 0);
      end if;
      Len32 := Interfaces.Integer_32 (Chunk.all'Length);
      V.Encode (Len32, Prefix, 1, W, St);
      if St /= V.Ok or else W not in 1 .. 5 then
         C.Free (Chunk);
         Enc.Data := null;
         C.Free (Enc);
         return (1 .. 0 => 0);
      end if;
      declare
         Out_Len : constant Natural := W + Chunk.all'Length;
         Result  : Octets (1 .. Out_Len) := (others => 0);
      begin
         for I in 1 .. W loop
            Result (I) := Prefix (I);
         end loop;
         for I in 1 .. Chunk.all'Length loop
            Result (W + I) := Chunk.all (Chunk.all'First + I - 1);
         end loop;
         C.Free (Chunk);
         Enc.Data := null;
         C.Free (Enc);
         return Result;
      end;
   end Encode_Compressed_Frame;

   function Split_Compressed_Frame
     (Buffer : Octets;
      From   : Positive) return Compressed_Split
     with SPARK_Mode => Off
   is
      package V renames Adacraft.Protocol.Varnum;
      Plen : V.Varint_Result;
      Dlen : V.Varint_Result;
      Size : Natural;
      Data_End : Natural;
      Frame_End : Natural;
   begin
      if From > Buffer'Last then
         return (Status => Need_More, Data_Length => 0,
                 Payload_First => 1, Payload_Last => 0, Next => From);
      end if;
      Plen := V.Decode_Varint (Buffer, From);
      if Plen.Status = Need_More then
         return (Status => Need_More, Data_Length => 0,
                 Payload_First => 1, Payload_Last => 0, Next => From);
      end if;
      if Plen.Status /= Status_Kind'(Ok) then
         return (Status => Rejected, Data_Length => 0,
                 Payload_First => 1, Payload_Last => 0, Next => From);
      end if;
      if Plen.Next - From > Max_Length_Bytes
        or else Plen.Value = 0
        or else Plen.Value > Interfaces.Unsigned_32 (Max_Packet_Length)
      then
         return (Status => Rejected, Data_Length => 0,
                 Payload_First => 1, Payload_Last => 0, Next => From);
      end if;
      Size := Natural (Plen.Value);
      if Remaining (Buffer'Last, Plen.Next) < Size then
         return (Status => Need_More, Data_Length => 0,
                 Payload_First => 1, Payload_Last => 0, Next => From);
      end if;
      Frame_End := Plen.Next + Size - 1;
      Dlen := V.Decode_Varint (Buffer, Plen.Next);
      if Dlen.Status /= Status_Kind'(Ok)
        or else Dlen.Next < Plen.Next
        or else Dlen.Next > Frame_End + 1
        or else Dlen.Value > Interfaces.Unsigned_32 (Natural'Last)
      then
         return (Status => Rejected, Data_Length => 0,
                 Payload_First => 1, Payload_Last => 0, Next => From);
      end if;
      Data_End := Dlen.Next;
      return
        (Status        => Ok,
         Data_Length   => Natural (Dlen.Value),
         Payload_First => Data_End,
         Payload_Last  => Frame_End,
         Next          => Frame_End + 1);
   end Split_Compressed_Frame;

   procedure Decode_Compressed_Frame
     (Buffer    : in     Octets;
      From      : in     Positive;
      Threshold : in     Natural;
      Data      : in out Compression.Byte_Array_Access;
      Next      :    out Natural;
      Status    :    out Compressed_Split_Status)
     with SPARK_Mode => Off
   is
      package C renames Adacraft.Protocol.Compression;
      Split : Compressed_Split;
      Dec   : C.Decode_Result;
      First : Positive;
   begin
      C.Free (Data);
      Data := null;
      Next := From;
      Status := Rejected;
      Split := Split_Compressed_Frame (Buffer, From);
      if Split.Status /= Ok then
         Status := Split.Status;
         return;
      end if;
      if Split.Data_Length /= 0 and then Split.Data_Length < Threshold then
         return;
      end if;
      if Split.Data_Length > C.Max_Decompressed_Size then
         return;
      end if;
      if Split.Payload_First > Split.Payload_Last then
         --  Empty payload after Data_Length VarInt.
         if Split.Data_Length = 0 then
            Data := new Octets (1 .. 0);
            Next := Split.Next;
            Status := Ok;
            return;
         else
            --  Declared bytes but no bytes to inflate: let the codec
            --  report truncation so the reason stays fail-closed.
            First := Split.Next;
            declare
               Empty : Octets (1 .. 0) := (others => 0);
            begin
               C.Decode (Threshold, Empty, Dec);
               C.Free (Dec);
               return;
            end;
         end if;
      end if;
      First := Split.Payload_First - (Split.Payload_First - Split.Payload_First);
      --  Feed the codec the Data_Length VarInt plus the frame payload,
      --  i.e. Buffer (Plen.Next .. Frame_End). Recover the Data_Length
      --  start from the split: it is the byte after Packet_Length.
      declare
         package V renames Adacraft.Protocol.Varnum;
         Plen : V.Varint_Result := V.Decode_Varint (Buffer, From);
         Codec_Input : Octets renames Buffer (Plen.Next .. Split.Payload_Last);
      begin
         First := Plen.Next;
         C.Decode (Threshold, Codec_Input, Dec);
         if not Dec.Ok or else Dec.Data = null then
            C.Free (Dec);
            return;
         end if;
         if Dec.Data.all'Length /= Split.Data_Length then
            C.Free (Dec);
            return;
         end if;
         Data := Dec.Data;
         Dec.Data := null;
         C.Free (Dec);
         Next := Split.Next;
         Status := Ok;
      end;
   end Decode_Compressed_Frame;

   function Decode_Frame (Buffer : Octets; From : Positive) return Frame_Decode is
      Length      : Varnum.Varint_Result;
      Ident       : Varnum.Varint_Result;
      Size        : Natural;
      Payload_End : Natural;
   begin
      if From > Buffer'Last then
         return (Status => Need_More, Packet_Id => 0, Payload_First => 1,
                 Payload_Last => 0, Next => From, Declared_Length => 0);
      end if;

      Length := Varnum.Decode_Varint (Buffer, From);
      if Length.Status /= Status_Kind'(Ok) then
         return (Status => Length.Status, Packet_Id => 0, Payload_First => 1,
                 Payload_Last => 0, Next => From, Declared_Length => 0);
      end if;

      if Length.Next - From > Max_Length_Bytes
        or else Length.Value = 0
        or else Length.Value > Interfaces.Unsigned_32 (Max_Packet_Length)
      then
         return (Status => Rejected, Packet_Id => 0, Payload_First => 1,
                 Payload_Last => 0, Next => From,
                 Declared_Length =>
                   (if Length.Value > Interfaces.Unsigned_32 (Natural'Last)
                    then Natural'Last
                    else Natural (Length.Value)));
      end if;

      Size := Natural (Length.Value);
      if Remaining (Buffer'Last, Length.Next) < Size then
         return (Status => Need_More, Packet_Id => 0, Payload_First => 1,
                 Payload_Last => 0, Next => From, Declared_Length => Size);
      end if;

      Payload_End := Length.Next + Size - 1;
      Ident := Varnum.Decode_Varint (Buffer, Length.Next);
      if Ident.Status /= Status_Kind'(Ok)
        or else Ident.Next < Length.Next
        or else Ident.Next > Payload_End + 1
        or else Ident.Value > Interfaces.Unsigned_32 (Natural'Last)
      then
         return (Status => Rejected, Packet_Id => 0, Payload_First => 1,
                 Payload_Last => 0, Next => From, Declared_Length => Size);
      end if;

      return
        (Status          => Status_Kind'(Ok),
         Packet_Id       => Natural (Ident.Value),
         Payload_First   => Ident.Next,
         Payload_Last    => Payload_End,
         Next            => Payload_End + 1,
         Declared_Length => Size);
   end Decode_Frame;
end Adacraft.Protocol.Frame;
