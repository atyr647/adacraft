with Ada.Streams;
with Ada.Text_IO;
with Interfaces;
with Adacraft.Protocol;
with Adacraft.Protocol.Varnum;
with Adacraft.Protocol.Packet_Encoder;
with Adacraft.Protocol.Packet_Decoder;

procedure Test_Protocol_Packet_Decoder is
   --  Mapping case -> test -> exact reason identifier:
   --  empty body                        -> T_Empty            -> Reason_Empty_Body
   --  truncated id (prefix 0 of 1-byte) -> T_Trunc_Prefix_0   -> Reason_Truncated_Id
   --  trunc prefix 1..N-1 multi-field   -> T_Trunc_Prefix_K   -> Reason_Truncated_Field
   --  overlong VarInt ID                -> T_Overlong_Id      -> Reason_Overlong_Id
   --  overlong VarInt field             -> T_Overlong_Varint  -> Reason_Overlong_Field
   --  overlong VarLong field            -> T_Overlong_Varlong -> Reason_Overlong_Field
   --  string negative length            -> T_Str_Negative     -> Reason_String_Negative_Length
   --  string over String_Max            -> T_Str_Too_Long     -> Reason_String_Too_Long
   --  string beyond remaining           -> T_Str_Beyond       -> Reason_String_Beyond_Remaining
   --  trailing bytes                    -> T_Trailing         -> Reason_Trailing_Bytes
   --  invalid boolean 2..255            -> T_Bad_Bool_*       -> Reason_Invalid_Boolean
   --  negative packet id                -> T_Negative_Id      -> Reason_Invalid_Id
   --  T1/T2/T3 valid                    -> T1/T2/T3            -> Reason_None (Ok)
   --  T-1/T-9 string valid              -> T_Minus1/T_Minus9   -> Reason_None (Ok)
   --  AC-4 per-kind valid               -> T_Valid_*          -> Reason_None (Ok)

   package Enc renames Adacraft.Protocol.Packet_Encoder;
   package Dec renames Adacraft.Protocol.Packet_Decoder;
   use type Adacraft.Protocol.Varnum.Status_Type;
   use type Adacraft.Protocol.Status_Kind;
   use type Dec.Reason_Type;
   use type Dec.Field_Kind;
   use type Ada.Streams.Stream_Element;
   use type Ada.Streams.Stream_Element_Offset;
   use type Interfaces.Integer_32;
   use type Interfaces.Integer_64;

   subtype SEA is Ada.Streams.Stream_Element_Array;
   subtype SEO is Ada.Streams.Stream_Element_Offset;
   subtype SE is Ada.Streams.Stream_Element;

   Failures : Natural := 0;

   procedure Check (Cond : Boolean; Name : String) is
   begin
      if not Cond then
         Failures := Failures + 1;
         Ada.Text_IO.Put_Line ("FAIL decoder: " & Name);
      end if;
   end Check;

   function Get_Body_Of (E : Enc.Encoder_Type) return SEA is
      Buf  : SEA (1 .. 4096) := (others => 0);
      Last : SEO;
   begin
      Enc.Get_Body (E, Buf, Last);
      return Buf (Buf'First .. Last);
   end Get_Body_Of;

   E : Enc.Encoder_Type;
begin
   --  T1: id-only packet round-trip.
   Enc.Start_Packet (E, 0);
   declare
      R : constant Dec.Decode_Result :=
        Dec.Decode (Get_Body_Of (E), Dec.Layout_Array'(1 .. 0 => Dec.Kind_Boolean));
   begin
      Check (R.Status = Adacraft.Protocol.Ok and then R.Reason = Dec.Reason_None
             and then R.Packet_Id = 0, "T1 id0");
   end;

   --  T2: boolean + byte valid (encoder-built).
   Enc.Start_Packet (E, 7);
   Enc.Write_Boolean (E, True);
   Enc.Write_Byte (E, 16#AB#);
   declare
      R : constant Dec.Decode_Result :=
        Dec.Decode (Get_Body_Of (E),
                    Dec.Layout_Array'(Dec.Kind_Boolean, Dec.Kind_Byte));
   begin
      Check (R.Status = Adacraft.Protocol.Ok and then R.Packet_Id = 7, "T2 id");
      Check (R.Fields (1).Bool_Value = True, "T2 bool");
      Check (R.Fields (2).Byte_Value = 16#AB#, "T2 byte");
   end;

   --  T3: int + long valid (encoder-built).
   Enc.Start_Packet (E, 3);
   Enc.Write_Int (E, -12345);
   Enc.Write_Long (E, 9876543210);
   declare
      R : constant Dec.Decode_Result :=
        Dec.Decode (Get_Body_Of (E),
                    Dec.Layout_Array'(Dec.Kind_Int, Dec.Kind_Long));
   begin
      Check (R.Status = Adacraft.Protocol.Ok and then R.Packet_Id = 3, "T3 id");
      Check (R.Fields (1).Int_Value = -12345, "T3 int");
      Check (R.Fields (2).Long_Value = 9876543210, "T3 long");
   end;

   --  T-1: string valid "hi" (manual VarInt length + bytes).
   declare
      Raw : constant SEA := SEA'(16#00#, 16#02#, 16#68#, 16#69#);
      R : constant Dec.Decode_Result :=
        Dec.Decode (Raw, Dec.Layout_Array'(1 => Dec.Kind_String));
   begin
      Check (R.Status = Adacraft.Protocol.Ok and then R.Packet_Id = 0, "T-Minus1 id");
      Check (R.Fields (1).Str_Len = 2
             and then R.Fields (1).Str_Data (1 .. 2) = "hi", "T-Minus1 str");
   end;

   --  T-9: empty string valid.
   declare
      Raw : constant SEA := SEA'(1 => 16#00#, 2 => 16#00#);
      R : constant Dec.Decode_Result :=
        Dec.Decode (Raw, Dec.Layout_Array'(1 => Dec.Kind_String));
   begin
      Check (R.Status = Adacraft.Protocol.Ok and then R.Fields (1).Str_Len = 0,
             "T-Minus9 empty str");
   end;

   --  AC-4 per-kind valid bodies (encoder-built where encoder supports).
   --  Boolean true / false.
   Enc.Start_Packet (E, 0);
   Enc.Write_Boolean (E, False);
   declare
      R : constant Dec.Decode_Result :=
        Dec.Decode (Get_Body_Of (E), Dec.Layout_Array'(1 => Dec.Kind_Boolean));
   begin
      Check (R.Status = Adacraft.Protocol.Ok
             and then R.Fields (1).Bool_Value = False, "T-Valid-Bool");
   end;

   --  Byte.
   Enc.Start_Packet (E, 1);
   Enc.Write_Byte (E, 16#7E#);
   declare
      R : constant Dec.Decode_Result :=
        Dec.Decode (Get_Body_Of (E), Dec.Layout_Array'(1 => Dec.Kind_Byte));
   begin
      Check (R.Status = Adacraft.Protocol.Ok and then R.Packet_Id = 1
             and then R.Fields (1).Byte_Value = 16#7E#, "T-Valid-Byte");
   end;

   --  Int (first/last).
   Enc.Start_Packet (E, 2);
   Enc.Write_Int (E, Interfaces.Integer_32'First);
   declare
      R : constant Dec.Decode_Result :=
        Dec.Decode (Get_Body_Of (E), Dec.Layout_Array'(1 => Dec.Kind_Int));
   begin
      Check (R.Status = Adacraft.Protocol.Ok
             and then R.Fields (1).Int_Value = Interfaces.Integer_32'First,
             "T-Valid-Int-First");
   end;

   Enc.Start_Packet (E, 2);
   Enc.Write_Int (E, Interfaces.Integer_32'Last);
   declare
      R : constant Dec.Decode_Result :=
        Dec.Decode (Get_Body_Of (E), Dec.Layout_Array'(1 => Dec.Kind_Int));
   begin
      Check (R.Status = Adacraft.Protocol.Ok
             and then R.Fields (1).Int_Value = Interfaces.Integer_32'Last,
             "T-Valid-Int-Last");
   end;

   --  Long.
   Enc.Start_Packet (E, 2);
   Enc.Write_Long (E, Interfaces.Integer_64'First);
   declare
      R : constant Dec.Decode_Result :=
        Dec.Decode (Get_Body_Of (E), Dec.Layout_Array'(1 => Dec.Kind_Long));
   begin
      Check (R.Status = Adacraft.Protocol.Ok
             and then R.Fields (1).Long_Value = Interfaces.Integer_64'First,
             "T-Valid-Long-First");
   end;

   Enc.Start_Packet (E, 2);
   Enc.Write_Long (E, Interfaces.Integer_64'Last);
   declare
      R : constant Dec.Decode_Result :=
        Dec.Decode (Get_Body_Of (E), Dec.Layout_Array'(1 => Dec.Kind_Long));
   begin
      Check (R.Status = Adacraft.Protocol.Ok
             and then R.Fields (1).Long_Value = Interfaces.Integer_64'Last,
             "T-Valid-Long-Last");
   end;

   --  VarInt field (manual: id 0 + varint 300 = 16#AC#, 16#02#).
   declare
      Raw : constant SEA := SEA'(16#00#, 16#AC#, 16#02#);
      R : constant Dec.Decode_Result :=
        Dec.Decode (Raw, Dec.Layout_Array'(1 => Dec.Kind_Varint));
   begin
      Check (R.Status = Adacraft.Protocol.Ok
             and then R.Fields (1).Varint_Value = 300, "T-Valid-Varint");
   end;

   --  VarLong field (manual: id 0 + varlong 300).
   declare
      Raw : constant SEA := SEA'(16#00#, 16#AC#, 16#02#);
      R : constant Dec.Decode_Result :=
        Dec.Decode (Raw, Dec.Layout_Array'(1 => Dec.Kind_Varlong));
   begin
      Check (R.Status = Adacraft.Protocol.Ok
             and then R.Fields (1).Varlong_Value = 300, "T-Valid-Varlong");
   end;

   --  String valid (manual, covered by T-1/T-9 too).
   declare
      Raw : constant SEA := SEA'(16#05#, 16#03#, 16#61#, 16#62#, 16#63#);
      R : constant Dec.Decode_Result :=
        Dec.Decode (Raw, Dec.Layout_Array'(1 => Dec.Kind_String));
   begin
      Check (R.Status = Adacraft.Protocol.Ok and then R.Packet_Id = 5
             and then R.Fields (1).Str_Data (1 .. 3) = "abc", "T-Valid-String");
   end;

   --  R-7 matrix.
   --  Empty body.
   declare
      Empty : constant SEA (1 .. 0) := (others => 0);
      Empty_Lay : constant Dec.Layout_Array (1 .. 0) := (1 .. 0 => Dec.Kind_Boolean);
      R : constant Dec.Decode_Result :=
        Dec.Decode (Empty, Empty_Lay);
   begin
      Check (R.Status = Adacraft.Protocol.Rejected
             and then R.Reason = Dec.Reason_Empty_Body, "T-Empty");
   end;

   --  Truncated prefixes of multi-field body: id(1) + bool(1) + int(4) = 6 bytes.
   Enc.Start_Packet (E, 0);
   Enc.Write_Boolean (E, True);
   Enc.Write_Int (E, 1);
   declare
      Full : constant SEA := Get_Body_Of (E);
      Lay  : constant Dec.Layout_Array := (Dec.Kind_Boolean, Dec.Kind_Int);
      Len  : constant Natural := Full'Length;
   begin
      Check (Len = 6, "T-Trunc full len");
      for K in 0 .. Len - 1 loop
         declare
            Part : constant SEA := Full (Full'First .. Full'First + SEO (K) - 1);
            R : constant Dec.Decode_Result := Dec.Decode (Part, Lay);
         begin
            if K = 0 then
               Check (R.Reason = Dec.Reason_Empty_Body, "T-Trunc-Prefix-0");
            elsif K = 1 then
               --  Only ID byte present; boolean field where input ran out.
               Check (R.Reason = Dec.Reason_Truncated_Field, "T-Trunc-Prefix-1 bool");
            elsif K = 2 then
               --  ID + boolean present; int field where input ran out (0 of 4 bytes).
               Check (R.Reason = Dec.Reason_Truncated_Field,
                      "T-Trunc-Prefix-2 int-missing");
            else
               --  ID + boolean + partial int; int field where input ran out.
               Check (R.Reason = Dec.Reason_Truncated_Field,
                      "T-Trunc-Prefix-" & Integer'Image (K) & " int-partial");
            end if;
            Check (R.Status = Adacraft.Protocol.Rejected, "T-Trunc rejected");
         end;
      end loop;
   end;

   --  Overlong VarInt ID: 6 continuation bytes.
   declare
      Raw : constant SEA :=
        SEA'(16#80#, 16#80#, 16#80#, 16#80#, 16#80#, 16#01#);
      Empty_Lay : constant Dec.Layout_Array (1 .. 0) := (1 .. 0 => Dec.Kind_Boolean);
      R : constant Dec.Decode_Result :=
        Dec.Decode (Raw, Empty_Lay);
   begin
      Check (R.Reason = Dec.Reason_Overlong_Id, "T-Overlong-Id");
   end;

   --  Overlong VarInt field.
   declare
      Raw : constant SEA :=
        SEA'(16#00#, 16#80#, 16#80#, 16#80#, 16#80#, 16#80#, 16#01#);
      R : constant Dec.Decode_Result :=
        Dec.Decode (Raw, Dec.Layout_Array'(1 => Dec.Kind_Varint));
   begin
      Check (R.Reason = Dec.Reason_Overlong_Field, "T-Overlong-Varint");
   end;

   --  Overlong VarLong field: 11 bytes.
   declare
      Raw : constant SEA :=
        SEA'(16#00#, 16#80#, 16#80#, 16#80#, 16#80#, 16#80#, 16#80#, 16#80#,
             16#80#, 16#80#, 16#80#, 16#01#);
      R : constant Dec.Decode_Result :=
        Dec.Decode (Raw, Dec.Layout_Array'(1 => Dec.Kind_Varlong));
   begin
      Check (R.Reason = Dec.Reason_Overlong_Field, "T-Overlong-Varlong");
   end;

   --  String negative length: VarInt -1 = FF FF FF FF 0F.
   declare
      Raw : constant SEA :=
        SEA'(16#00#, 16#FF#, 16#FF#, 16#FF#, 16#FF#, 16#0F#);
      R : constant Dec.Decode_Result :=
        Dec.Decode (Raw, Dec.Layout_Array'(1 => Dec.Kind_String));
   begin
      Check (R.Reason = Dec.Reason_String_Negative_Length, "T-Str-Negative");
   end;

   --  String over String_Max (256 > 255): 16#80#, 16#02#.
   declare
      Raw : constant SEA := SEA'(16#00#, 16#80#, 16#02#);
      R : constant Dec.Decode_Result :=
        Dec.Decode (Raw, Dec.Layout_Array'(1 => Dec.Kind_String));
   begin
      Check (R.Reason = Dec.Reason_String_Too_Long, "T-Str-Too-Long");
   end;

   --  String beyond remaining: length 5 but only 2 bytes.
   declare
      Raw : constant SEA := SEA'(16#00#, 16#05#, 16#61#, 16#62#);
      R : constant Dec.Decode_Result :=
        Dec.Decode (Raw, Dec.Layout_Array'(1 => Dec.Kind_String));
   begin
      Check (R.Reason = Dec.Reason_String_Beyond_Remaining, "T-Str-Beyond");
   end;

   --  Trailing bytes.
   declare
      Raw : constant SEA := SEA'(16#00#, 16#01#, 16#FF#);
      R : constant Dec.Decode_Result :=
        Dec.Decode (Raw, Dec.Layout_Array'(1 => Dec.Kind_Boolean));
   begin
      Check (R.Reason = Dec.Reason_Trailing_Bytes, "T-Trailing");
   end;

   --  Invalid boolean 2..255 (sample 2 and 255).
   for V in SE range 2 .. 255 loop
      declare
         Raw : constant SEA := SEA'(1 => 16#00#, 2 => V);
         R : constant Dec.Decode_Result :=
           Dec.Decode (Raw, Dec.Layout_Array'(1 => Dec.Kind_Boolean));
      begin
         Check (R.Status = Adacraft.Protocol.Rejected
                and then R.Reason = Dec.Reason_Invalid_Boolean,
                "T-Bad-Bool-" & SE'Image (V));
      end;
   end loop;

   --  Negative packet id.
   declare
      Raw : constant SEA :=
        SEA'(16#FF#, 16#FF#, 16#FF#, 16#FF#, 16#0F#);
      Empty_Lay : constant Dec.Layout_Array (1 .. 0) := (1 .. 0 => Dec.Kind_Boolean);
      R : constant Dec.Decode_Result :=
        Dec.Decode (Raw, Empty_Lay);
   begin
      Check (R.Reason = Dec.Reason_Invalid_Id, "T-Negative-Id");
   end;

   --  Truncated id: single continuation byte.
   declare
      Raw : constant SEA := SEA'(1 => 16#80#);
      Empty_Lay : constant Dec.Layout_Array (1 .. 0) := (1 .. 0 => Dec.Kind_Boolean);
      R : constant Dec.Decode_Result :=
        Dec.Decode (Raw, Empty_Lay);
   begin
      Check (R.Reason = Dec.Reason_Truncated_Id, "T-Trunc-Id");
   end;

   if Failures = 0 then
      Ada.Text_IO.Put_Line ("packet decoder tests passed");
   else
      Ada.Text_IO.Put_Line ("packet decoder tests failed");
      raise Program_Error with "packet decoder tests failed";
   end if;
end Test_Protocol_Packet_Decoder;
