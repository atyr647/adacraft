with Ada.Assertions;
with Ada.Command_Line;
with Ada.Streams;
with Ada.Text_IO;
with Interfaces;
with Adacraft.Protocol.Frame;
with Adacraft.Protocol.Packet_Encoder;

procedure Test_Protocol_Packet_Encoder is
   package Packet renames Adacraft.Protocol.Packet_Encoder;
   package Frame renames Adacraft.Protocol.Frame;

   use type Ada.Streams.Stream_Element;
   use type Ada.Streams.Stream_Element_Array;
   use type Ada.Streams.Stream_Element_Offset;
   use type Frame.Encode_Status;
   use type Interfaces.Integer_8;
   use type Interfaces.Integer_32;
   use type Interfaces.Integer_64;

   Failures : Natural := 0;

   procedure Check_Bool (Condition : Boolean; Name : String) is
   begin
      if not Condition then
         Failures := Failures + 1;
         Ada.Text_IO.Put_Line ("FAIL: " & Name);
      end if;
      Ada.Assertions.Assert (Condition, Name);
   end Check_Bool;

   procedure Check_Bytes
     (E        : in out Packet.Encoder_Type;
      Expected :        Ada.Streams.Stream_Element_Array;
      Name     :        String)
   is
      Output  : Ada.Streams.Stream_Element_Array (1 .. 32);
      Out_Len : Natural;
      Success : Boolean;
   begin
      Packet.Encode_Frame (E, Output, Out_Len, Success);
      Check_Bool (Success, Name & " frame succeeds");
      Check_Bool
        (Out_Len = Expected'Length + 1,
         Name & " framed length");
      if Success and then Out_Len = Expected'Length + 1 then
         Check_Bool
           (Output (1) = Ada.Streams.Stream_Element (Expected'Length),
            Name & " prefix");
         for I in Expected'Range loop
            Check_Bool
              (Output (Ada.Streams.Stream_Element_Offset (I - Expected'First + 2))
                 = Expected (I),
               Name & " byte" & Integer'Image (Integer (I - Expected'First + 1)));
         end loop;
      end if;
   end Check_Bytes;

   procedure Check_Byte
     (Value    : Interfaces.Integer_8;
      Expected : Ada.Streams.Stream_Element;
      Name     : String)
   is
      E : Packet.Encoder_Type;
   begin
      Packet.Start_Packet (E, 0);
      Packet.Write_Byte (E, Value);
      Check_Bytes (E, (1 => 0, 2 => Expected), Name);
   end Check_Byte;

   procedure Check_Int
     (Value    : Interfaces.Integer_32;
      Expected : Ada.Streams.Stream_Element_Array;
      Name     : String)
   is
      E : Packet.Encoder_Type;
   begin
      Packet.Start_Packet (E, 0);
      Packet.Write_Int (E, Value);
      Check_Bytes (E, (1 => 0) & Expected, Name);
   end Check_Int;

   procedure Check_Long
     (Value    : Interfaces.Integer_64;
      Expected : Ada.Streams.Stream_Element_Array;
      Name     : String)
   is
      E : Packet.Encoder_Type;
   begin
      Packet.Start_Packet (E, 0);
      Packet.Write_Long (E, Value);
      Check_Bytes (E, (1 => 0) & Expected, Name);
   end Check_Long;

   procedure Check_Boolean_Value
     (Value    : Boolean;
      Expected : Ada.Streams.Stream_Element;
      Name     : String)
   is
      E : Packet.Encoder_Type;
   begin
      Packet.Start_Packet (E, 0);
      Packet.Write_Boolean (E, Value);
      Check_Bytes (E, (1 => 0, 2 => Expected), Name);
   end Check_Boolean_Value;

begin
   --  T1: packet ID zero is one zero byte.
   declare
      E : Packet.Encoder_Type;
   begin
      Packet.Start_Packet (E, 0);
      Check_Bool (Packet.Length (E) = 1, "T1 length");
      Check_Bytes (E, (1 => 0), "T1 packet ID zero");
   end;

   --  T2: packet ID 300 encodes as AC 02.
   declare
      E : Packet.Encoder_Type;
   begin
      Packet.Start_Packet (E, 300);
      Check_Bool (Packet.Length (E) = 2, "T2 length");
      Check_Bytes (E, (1 => 16#AC#, 2 => 16#02#), "T2 packet ID 300");
   end;

   --  T3: booleans are one byte.
   Check_Boolean_Value (True, 16#01#, "T3 true");
   Check_Boolean_Value (False, 16#00#, "T3 false");

   --  T4: signed byte preserves its low eight bits.
   Check_Byte (-1, 16#FF#, "T4 signed byte");

   --  T5: signed Int is four-byte big-endian two's complement.
   Check_Int
     (16#01020304#,
      (1 => 16#01#, 2 => 16#02#, 3 => 16#03#, 4 => 16#04#),
      "T5 positive Int");
   Check_Int
     (-1,
      (1 => 16#FF#, 2 => 16#FF#, 3 => 16#FF#, 4 => 16#FF#),
      "T5 negative Int");

   --  T6: signed Long is eight-byte big-endian two's complement.
   Check_Long
     (16#0102030405060708#,
      (1 => 16#01#, 2 => 16#02#, 3 => 16#03#, 4 => 16#04#,
       5 => 16#05#, 6 => 16#06#, 7 => 16#07#, 8 => 16#08#),
      "T6 positive Long");
   Check_Long
     (-1,
      (1 => 16#FF#, 2 => 16#FF#, 3 => 16#FF#, 4 => 16#FF#,
       5 => 16#FF#, 6 => 16#FF#, 7 => 16#FF#, 8 => 16#FF#),
      "T6 negative Long");

   --  T7/T8: overflow is sticky, preserves length, and Start_Packet resets it.
   declare
      E : Packet.Encoder_Type (Capacity => 2);
   begin
      Packet.Start_Packet (E, 0);
      Packet.Write_Byte (E, 1);
      Check_Bool (Packet.Length (E) = 2, "T7 filled small encoder");
      Packet.Write_Boolean (E, True);
      Check_Bool (Packet.Has_Failed (E), "T7 overflow fails");
      Check_Bool (Packet.Length (E) = 2, "T7 overflow preserves length");
      Packet.Write_Byte (E, 2);
      Check_Bool (Packet.Has_Failed (E), "T7 failure stays sticky");
      Check_Bool (Packet.Length (E) = 2, "T7 later write preserves length");
      Packet.Start_Packet (E, 0);
      Check_Bool (not Packet.Has_Failed (E), "T7 Start_Packet clears failure");
      Check_Bool (Packet.Length (E) = 1, "T7 reset contains packet ID");
   end;

   declare
      E : Packet.Encoder_Type (Capacity => 3);
   begin
      Packet.Start_Packet (E, 300);
      Check_Bool (Packet.Length (E) = 2, "T8 packet ID fits");
      Packet.Write_Int (E, 16#01020304#);
      Check_Bool (Packet.Has_Failed (E), "T8 field overflow fails");
      Check_Bool (Packet.Length (E) = 2, "T8 overflow leaves ID unchanged");
      Packet.Start_Packet (E, 0);
      Check_Bool (not Packet.Has_Failed (E), "T8 Start_Packet clears failure");
      Check_Bool (Packet.Length (E) = 1, "T8 reset contains packet ID");
   end;

   --  T9: framed output matches Frame.Encode for the same packet body.
   declare
      E                : Packet.Encoder_Type;
      Encoded          : Ada.Streams.Stream_Element_Array (1 .. 32);
      Reference        : Ada.Streams.Stream_Element_Array (1 .. 32);
      Encoded_Len      : Natural;
      Encoded_Success  : Boolean;
      Reference_Last   : Ada.Streams.Stream_Element_Offset;
      Reference_Status : Frame.Encode_Status;
      Payload          : constant Ada.Streams.Stream_Element_Array :=
        (1 => 0, 2 => 1, 3 => 16#FF#);
      Same             : Boolean := True;
   begin
      Packet.Start_Packet (E, 0);
      Packet.Write_Boolean (E, True);
      Packet.Write_Byte (E, -1);
      Packet.Encode_Frame (E, Encoded, Encoded_Len, Encoded_Success);
      Frame.Encode (Payload, Reference, Reference_Last, Reference_Status);

      Check_Bool (Encoded_Success, "T9 encoder frame succeeds");
      Check_Bool (Reference_Status = Frame.Ok, "T9 reference frame succeeds");
      if Encoded_Success and then Reference_Status = Frame.Ok then
         Check_Bool
           (Encoded_Len = Natural (Reference_Last),
            "T9 frame lengths match");
         if Encoded_Len = Natural (Reference_Last) then
            for I in 1 .. Encoded_Len loop
               if Encoded (Ada.Streams.Stream_Element_Offset (I))
                 /= Reference (Ada.Streams.Stream_Element_Offset (I))
               then
                  Same := False;
               end if;
            end loop;
         else
            Same := False;
         end if;
      else
         Same := False;
      end if;
      Check_Bool (Same, "T9 framed bytes match Frame.Encode");
   end;

   --  T10: writing a field before Start_Packet fails.
   declare
      E : Packet.Encoder_Type;
   begin
      Packet.Write_Boolean (E, True);
      Check_Bool (Packet.Has_Failed (E), "T10 write before start fails");
   end;

   if Failures = 0 then
      Ada.Text_IO.Put_Line ("packet encoder tests passed");
   else
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
   end if;
end Test_Protocol_Packet_Encoder;
