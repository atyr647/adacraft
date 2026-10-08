with Ada.Streams;
with Ada.Text_IO;
with Interfaces;
with Adacraft.Protocol.Packet_Encoder;
with Adacraft.Protocol.Packet_Decoder;

procedure Test_Protocol_Packet_Decoder is
   package Enc renames Adacraft.Protocol.Packet_Encoder;
   package Dec renames Adacraft.Protocol.Packet_Decoder;
   use type Ada.Streams.Stream_Element;
   use type Ada.Streams.Stream_Element_Offset;
   use type Interfaces.Integer_32;
   use type Interfaces.Integer_64;
   use type Dec.Field_Kind;
   use type Dec.Fail_Reason;

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

   function Get_Body (E : Enc.Encoder_Type) return SEA is
      Buf  : SEA (1 .. 4_096) := (others => 0);
      Last : SEO;
   begin
      Enc.Get_Body (E, Buf, Last);
      if Last < Buf'First then
         return SEA'(1 .. 0 => 0);
      end if;
      declare
         R : SEA (1 .. Last - Buf'First + 1);
      begin
         for I in R'Range loop
            R (I) := Buf (Buf'First + SEO (I) - 1);
         end loop;
         return R;
      end;
   end Get_Body;

   function Build (Id : Natural; Do_Write : access procedure (E : in out Enc.Encoder_Type)) return SEA is
      E : Enc.Encoder_Type;
   begin
      Enc.Start_Packet (E, Id);
      Do_Write (E);
      return Get_Body (E);
   end Build;

   procedure W_Bool_T (E : in out Enc.Encoder_Type) is
   begin
      Enc.Write_Boolean (E, True);
   end W_Bool_T;
   procedure W_Bool_F (E : in out Enc.Encoder_Type) is
   begin
      Enc.Write_Boolean (E, False);
   end W_Bool_F;
   procedure W_Byte_AB (E : in out Enc.Encoder_Type) is
   begin
      Enc.Write_Byte (E, 16#AB#);
   end W_Byte_AB;
   procedure W_Int_1 (E : in out Enc.Encoder_Type) is
   begin
      Enc.Write_Int (E, 1);
   end W_Int_1;
   procedure W_Int_Neg1 (E : in out Enc.Encoder_Type) is
   begin
      Enc.Write_Int (E, -1);
   end W_Int_Neg1;
   procedure W_Int_Min (E : in out Enc.Encoder_Type) is
   begin
      Enc.Write_Int (E, Interfaces.Integer_32'First);
   end W_Int_Min;
   procedure W_Int_Max (E : in out Enc.Encoder_Type) is
   begin
      Enc.Write_Int (E, Interfaces.Integer_32'Last);
   end W_Int_Max;
   procedure W_Int_0 (E : in out Enc.Encoder_Type) is
   begin
      Enc.Write_Int (E, 0);
   end W_Int_0;
   procedure W_Long_1 (E : in out Enc.Encoder_Type) is
   begin
      Enc.Write_Long (E, 1);
   end W_Long_1;
   procedure W_Long_Neg1 (E : in out Enc.Encoder_Type) is
   begin
      Enc.Write_Long (E, -1);
   end W_Long_Neg1;
   procedure W_Long_Min (E : in out Enc.Encoder_Type) is
   begin
      Enc.Write_Long (E, Interfaces.Integer_64'First);
   end W_Long_Min;
   procedure W_Long_Max (E : in out Enc.Encoder_Type) is
   begin
      Enc.Write_Long (E, Interfaces.Integer_64'Last);
   end W_Long_Max;
   procedure W_Long_0 (E : in out Enc.Encoder_Type) is
   begin
      Enc.Write_Long (E, 0);
   end W_Long_0;
   procedure W_Mixed (E : in out Enc.Encoder_Type) is
   begin
      Enc.Write_Boolean (E, True);
      Enc.Write_Byte (E, 16#7E#);
      Enc.Write_Int (E, -12_345);
      Enc.Write_Long (E, 9_876_543_210);
   end W_Mixed;
   procedure W_None (E : in out Enc.Encoder_Type) is
   begin
      null;
   end W_None;

begin
   --  T-1: boundary round-trips per kind via encoder oracle.
   declare
      B : SEA := Build (0, W_Bool_T'Access);
      R : Dec.Decode_Result := Dec.Decode (B, Dec.Layout_Array'(1 => Dec.FK_Boolean));
   begin
      Check (R.Ok and then R.Id = 0 and then R.Count = 1
             and then R.Fields (1).Kind = Dec.FK_Boolean
             and then R.Fields (1).B = True, "T-1 bool true");
   end;
   declare
      B : SEA := Build (0, W_Bool_F'Access);
      R : Dec.Decode_Result := Dec.Decode (B, Dec.Layout_Array'(1 => Dec.FK_Boolean));
   begin
      Check (R.Ok and then R.Fields (1).B = False, "T-1 bool false");
   end;
   declare
      B : SEA := Build (1, W_Byte_AB'Access);
      R : Dec.Decode_Result := Dec.Decode (B, Dec.Layout_Array'(1 => Dec.FK_Byte));
   begin
      Check (R.Ok and then R.Id = 1 and then R.Fields (1).U8 = 16#AB#, "T-1 byte");
   end;
   for K in 1 .. 5 loop
      declare
         V : Interfaces.Integer_32 :=
           (case K is when 1 => 0, when 2 => 1, when 3 => -1,
              when 4 => Interfaces.Integer_32'First, when others => Interfaces.Integer_32'Last);
         E : Enc.Encoder_Type;
         Buf : SEA (1 .. 4_096) := (others => 0);
         Last : SEO;
         R : Dec.Decode_Result;
      begin
         Enc.Start_Packet (E, 7);
         Enc.Write_Int (E, V);
         R := Dec.Decode (Get_Body (E), Dec.Layout_Array'(1 => Dec.FK_Int));
         Check (R.Ok and then R.Id = 7 and then R.Fields (1).I32 = V, "T-1 int" & Integer'Image (K));
      end;
   end loop;
   for K in 1 .. 5 loop
      declare
         V : Interfaces.Integer_64 :=
           (case K is when 1 => 0, when 2 => 1, when 3 => -1,
              when 4 => Interfaces.Integer_64'First, when others => Interfaces.Integer_64'Last);
         E : Enc.Encoder_Type;
         R : Dec.Decode_Result;
      begin
         Enc.Start_Packet (E, 9);
         Enc.Write_Long (E, V);
         R := Dec.Decode (Get_Body (E), Dec.Layout_Array'(1 => Dec.FK_Long));
         Check (R.Ok and then R.Id = 9 and then R.Fields (1).I64 = V, "T-1 long" & Integer'Image (K));
      end;
   end loop;

   --  T-2: mixed multi-field round-trip.
   declare
      B : SEA := Build (5, W_Mixed'Access);
      R : Dec.Decode_Result := Dec.Decode
        (B, Dec.Layout_Array'(Dec.FK_Boolean, Dec.FK_Byte, Dec.FK_Int, Dec.FK_Long));
   begin
      Check (R.Ok and then R.Id = 5 and then R.Count = 4, "T-2 ok");
      Check (R.Ok and then R.Fields (1).B = True, "T-2 bool");
      Check (R.Ok and then R.Fields (2).U8 = 16#7E#, "T-2 byte");
      Check (R.Ok and then R.Fields (3).I32 = -12_345, "T-2 int");
      Check (R.Ok and then R.Fields (4).I64 = 9_876_543_210, "T-2 long");
   end;

   --  T-3: ID range ends.
   declare
      E : Enc.Encoder_Type;
      R : Dec.Decode_Result;
   begin
      Enc.Start_Packet (E, 0);
      R := Dec.Decode (Get_Body (E), Dec.Layout_Array'(1 .. 0 => Dec.FK_Boolean));
      Check (R.Ok and then R.Id = 0, "T-3 id 0");
      Enc.Start_Packet (E, 2_147_483_647);
      R := Dec.Decode (Get_Body (E), Dec.Layout_Array'(1 .. 0 => Dec.FK_Boolean));
      Check (R.Ok and then R.Id = 2_147_483_647, "T-3 id max");
   end;

   --  T-4: empty body.
   declare
      R : Dec.Decode_Result := Dec.Decode
        (SEA'(1 .. 0 => 0), Dec.Layout_Array'(1 .. 0 => Dec.FK_Boolean));
   begin
      Check (not R.Ok and then R.Reason = Dec.Empty_Body, "T-4 empty");
   end;

   --  Partial T-7: every strict prefix of valid multi-field packet fails.
   declare
      Full : SEA := Build (5, W_Mixed'Access);
      Layout : constant Dec.Layout_Array :=
        (Dec.FK_Boolean, Dec.FK_Byte, Dec.FK_Int, Dec.FK_Long);
   begin
      Check (Full'Length > 3, "T-7 fixture size");
      for K in Full'First .. Full'Last - 1 loop
         declare
            Pre : SEA := Full (Full'First .. K);
            R : Dec.Decode_Result := Dec.Decode (Pre, Layout);
         begin
            Check (not R.Ok, "T-7 prefix fails");
         end;
      end loop;
      declare
         R : Dec.Decode_Result := Dec.Decode (Full, Layout);
      begin
         Check (R.Ok, "T-7 full ok");
      end;
   end;

   --  Trailing byte check (core).
   declare
      Full : SEA := Build (5, W_Mixed'Access);
      Layout : constant Dec.Layout_Array :=
        (Dec.FK_Boolean, Dec.FK_Byte, Dec.FK_Int, Dec.FK_Long);
      Ext : SEA (1 .. Full'Length + 1);
      R : Dec.Decode_Result;
   begin
      for I in 0 .. Full'Length - 1 loop
         Ext (Ext'First + SEO (I)) := Full (Full'First + SEO (I));
      end loop;
      Ext (Ext'Last) := 16#00#;
      R := Dec.Decode (Ext, Layout);
      Check (not R.Ok and then R.Reason = Dec.Trailing_Bytes, "trailing");
   end;

   if Failures = 0 then
      Ada.Text_IO.Put_Line ("packet decoder tests passed");
   else
      Ada.Text_IO.Put_Line ("packet decoder tests failed");
      raise Program_Error with "packet decoder tests failed";
   end if;
end Test_Protocol_Packet_Decoder;
