with Ada.Streams;
with Ada.Text_IO;
with Interfaces;
with Adacraft.Protocol;
with Adacraft.Protocol.Packet_Encoder;
with Adacraft.Protocol.Packet_Decoder;
with Adacraft.Protocol.Varnum;

procedure Test_Protocol_Packet_Decoder is
   package Enc renames Adacraft.Protocol.Packet_Encoder;
   package Dec renames Adacraft.Protocol.Packet_Decoder;
   package Varnum renames Adacraft.Protocol.Varnum;
   use type Ada.Streams.Stream_Element;
   use type Ada.Streams.Stream_Element_Offset;
   use type Interfaces.Integer_32;
   use type Interfaces.Integer_64;
   use type Dec.Field_Kind;
   use type Dec.Fail_Reason;
   use type Varnum.Status_Type;

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

   --  Raw helpers crafted via Varnum (no encoder support for
   --  Varint/Varlong/String kinds; encoder is the oracle only for
   --  Boolean/Byte/Int/Long per shipped #210 spec).
   function Enc_Varint (V : Interfaces.Integer_32) return SEA is
      use Adacraft.Protocol;
      Buf : Octets (1 .. 5) := (others => 0);
      W : Natural := 0;
      S : Varnum.Status_Type;
   begin
      Varnum.Encode (V, Buf, 1, W, S);
      if S /= Varnum.Ok then
         raise Program_Error with "Enc_Varint failed";
      end if;
      declare
         R : SEA (1 .. SEO (W));
      begin
         for I in 1 .. W loop
            R (SEO (I)) := SE (Buf (I));
         end loop;
         return R;
      end;
   end Enc_Varint;

   function Enc_Varlong (V : Interfaces.Integer_64) return SEA is
      use Adacraft.Protocol;
      Buf : Octets (1 .. 10) := (others => 0);
      W : Natural := 0;
      S : Varnum.Status_Type;
   begin
      Varnum.Encode_Varlong (V, Buf, 1, W, S);
      if S /= Varnum.Ok then
         raise Program_Error with "Enc_Varlong failed";
      end if;
      declare
         R : SEA (1 .. SEO (W));
      begin
         for I in 1 .. W loop
            R (SEO (I)) := SE (Buf (I));
         end loop;
         return R;
      end;
   end Enc_Varlong;

   function Cat (A, B : SEA) return SEA is
      R : SEA (1 .. A'Length + B'Length) := (others => 0);
   begin
      for I in 0 .. Integer (A'Length) - 1 loop
         R (R'First + SEO (I)) := A (A'First + SEO (I));
      end loop;
      for I in 0 .. Integer (B'Length) - 1 loop
         R (R'First + SEO (A'Length + Natural (I))) :=
           B (B'First + SEO (I));
      end loop;
      return R;
   end Cat;

   function Raw_Bytes (B : SEA) return SEA is
   begin
      return B;
   end Raw_Bytes;

begin
   --  T-1: boundary round-trips per kind via encoder oracle (AC-7).
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
   --  T-1 varint boundaries via Varnum oracle.
   for K in 1 .. 5 loop
      declare
         V : Interfaces.Integer_32 :=
           (case K is when 1 => 0, when 2 => 1, when 3 => -1,
              when 4 => Interfaces.Integer_32'First, when others => Interfaces.Integer_32'Last);
         Pkt : SEA := Cat (Enc_Varint (7), Enc_Varint (V));
         R : Dec.Decode_Result :=
           Dec.Decode (Pkt, Dec.Layout_Array'(1 => Dec.FK_Varint));
      begin
         Check (R.Ok and then R.Id = 7 and then R.Fields (1).V32 = V,
                "T-1 varint" & Integer'Image (K));
      end;
   end loop;
   --  T-1 varlong boundaries via Varnum oracle.
   for K in 1 .. 5 loop
      declare
         V : Interfaces.Integer_64 :=
           (case K is when 1 => 0, when 2 => 1, when 3 => -1,
              when 4 => Interfaces.Integer_64'First, when others => Interfaces.Integer_64'Last);
         Pkt : SEA := Cat (Enc_Varint (9), Enc_Varlong (V));
         R : Dec.Decode_Result :=
           Dec.Decode (Pkt, Dec.Layout_Array'(1 => Dec.FK_Varlong));
      begin
         Check (R.Ok and then R.Id = 9 and then R.Fields (1).V64 = V,
                "T-1 varlong" & Integer'Image (K));
      end;
   end loop;
   --  T-1 string: empty and String_Max length.
   declare
      Pkt : SEA := Cat (Enc_Varint (3), Enc_Varint (0));
      R : Dec.Decode_Result :=
        Dec.Decode (Pkt, Dec.Layout_Array'(1 => Dec.FK_String));
   begin
      Check (R.Ok and then R.Id = 3 and then R.Fields (1).Str_Len = 0,
             "T-1 string empty");
   end;
   declare
      N : constant Natural := Dec.String_Max;
      Pkt : SEA (1 .. SEO (Enc_Varint (3)'Length + Enc_Varint (Interfaces.Integer_32 (N))'Length + N));
      Lb : SEA := Enc_Varint (3);
      Lp : SEA := Enc_Varint (Interfaces.Integer_32 (N));
      Off : SEO := Pkt'First;
      R : Dec.Decode_Result;
      Good : Boolean := True;
   begin
      for I in Lb'Range loop
         Pkt (Off) := Lb (I);
         Off := Off + 1;
      end loop;
      for I in Lp'Range loop
         Pkt (Off) := Lp (I);
         Off := Off + 1;
      end loop;
      for I in 1 .. N loop
         Pkt (Off) := Character'Pos ('A');
         Off := Off + 1;
      end loop;
      R := Dec.Decode (Pkt, Dec.Layout_Array'(1 => Dec.FK_String));
      Check (R.Ok and then R.Id = 3, "T-1 string max ok");
      if R.Ok then
         Check (R.Fields (1).Str_Len = N, "T-1 string max len");
         for I in 1 .. N loop
            if R.Fields (1).Str_Data (I) /= Character'Pos ('A') then
               Good := False;
            end if;
         end loop;
         Check (Good, "T-1 string max content");
      end if;
   end;

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
   --  T-2b: mixed incl varint/varlong/string round-trip (raw).
   declare
      Pkt : SEA := Cat
        (Cat
           (Cat
              (Cat (Cat (Enc_Varint (11),
                         SEA'(1 => 1)),      -- boolean true
                    Enc_Varint (-300)),           -- varint
               Enc_Varlong (-9_876_543_210)),     -- varlong
            Enc_Varint (2)),                      -- string len 2
         SEA'(1 => SE (Character'Pos ('h')),
             2 => SE (Character'Pos ('h'))));
      R : Dec.Decode_Result := Dec.Decode
        (Pkt, Dec.Layout_Array'
           (Dec.FK_Boolean, Dec.FK_Varint, Dec.FK_Varlong, Dec.FK_String));
   begin
      Check (R.Ok and then R.Id = 11 and then R.Count = 4, "T-2b ok");
      Check (R.Ok and then R.Fields (1).B = True, "T-2b bool");
      Check (R.Ok and then R.Fields (2).V32 = -300, "T-2b varint");
      Check (R.Ok and then R.Fields (3).V64 = -9_876_543_210, "T-2b varlong");
      Check (R.Ok and then R.Fields (4).Str_Len = 2, "T-2b strlen");
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

   --  T-5: truncated / overlong ID crafted via Varnum (AC-8 specificity).
   declare
      T : SEA (1 .. 1) := (1 => 16#80#); -- continuation, no terminator
      R : Dec.Decode_Result :=
        Dec.Decode (T, Dec.Layout_Array'(1 .. 0 => Dec.FK_Boolean));
   begin
      Check (not R.Ok and then R.Reason = Dec.Truncated, "T-5 trunc id");
   end;
   declare
      O : SEA (1 .. 5) := (16#FF#, 16#FF#, 16#FF#, 16#FF#, 16#7F#);
      R : Dec.Decode_Result :=
        Dec.Decode (O, Dec.Layout_Array'(1 .. 0 => Dec.FK_Boolean));
   begin
      Check (not R.Ok and then R.Reason = Dec.Overlong_Varint, "T-5 overlong id");
   end;

   --  T-6: negative / Max+1 ID => Id_Out_Of_Range (AC-3).
   declare
      N : SEA := Enc_Varint (-1);
      R : Dec.Decode_Result :=
        Dec.Decode (N, Dec.Layout_Array'(1 .. 0 => Dec.FK_Boolean));
   begin
      Check (not R.Ok and then R.Reason = Dec.Id_Out_Of_Range, "T-6 negative id");
   end;
   declare
      --  2**31 as unsigned varint wraps to Integer_32'First; still rejected.
      M : SEA (1 .. 5) := (16#80#, 16#80#, 16#80#, 16#80#, 16#08#);
      R : Dec.Decode_Result :=
        Dec.Decode (M, Dec.Layout_Array'(1 .. 0 => Dec.FK_Boolean));
   begin
      Check (not R.Ok and then R.Reason = Dec.Id_Out_Of_Range, "T-6 max+1 id");
   end;

   --  T-7: every strict prefix of valid multi-field packet fails.
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

   --  T-8: overlong VarInt/VarLong fields => respective reason.
   declare
      Pkt : SEA := Cat (SEA'(1 => 0),
                         SEA'(16#FF#, 16#FF#, 16#FF#, 16#FF#, 16#7F#));
      R : Dec.Decode_Result :=
        Dec.Decode (Pkt, Dec.Layout_Array'(1 => Dec.FK_Varint));
   begin
      Check (not R.Ok and then R.Reason = Dec.Overlong_Varint, "T-8 overlong varint");
   end;
   declare
      Pkt : SEA := Cat (SEA'(1 => 0),
                         SEA'(16#FF#, 16#FF#, 16#FF#, 16#FF#, 16#FF#,
                              16#FF#, 16#FF#, 16#FF#, 16#FF#, 16#02#));
      R : Dec.Decode_Result :=
        Dec.Decode (Pkt, Dec.Layout_Array'(1 => Dec.FK_Varlong));
   begin
      Check (not R.Ok and then R.Reason = Dec.Overlong_Varlong, "T-8 overlong varlong");
   end;
   --  T-8b: truncated varint/varlong field => Truncated, no partial packet.
   declare
      Pkt : SEA (1 .. 2) := (SE (0), SE (16#80#));
      R : Dec.Decode_Result :=
        Dec.Decode (Pkt, Dec.Layout_Array'(1 => Dec.FK_Varint));
   begin
      Check (not R.Ok and then R.Reason = Dec.Truncated, "T-8 trunc varint");
      Check (not R.Ok, "T-8 no partial");
   end;

   --  T-9: string negative / Max+1 / beyond-remaining.
   declare
      Pkt : SEA := Cat (SEA'(1 => 0), Enc_Varint (-1));
      R : Dec.Decode_Result :=
        Dec.Decode (Pkt, Dec.Layout_Array'(1 => Dec.FK_String));
   begin
      Check (not R.Ok and then R.Reason = Dec.String_Length_Invalid, "T-9 neg len");
   end;
   declare
      Pkt : SEA := Cat (SEA'(1 => 0),
                         Enc_Varint (Interfaces.Integer_32 (Dec.String_Max + 1)));
      R : Dec.Decode_Result :=
        Dec.Decode (Pkt, Dec.Layout_Array'(1 => Dec.FK_String));
   begin
      Check (not R.Ok and then R.Reason = Dec.String_Over_Max, "T-9 over max");
   end;
   declare
      Pkt : SEA := Cat (Cat (SEA'(1 => 0), Enc_Varint (5)),
                         SEA'(1 => SE (Character'Pos ('a')),
                             2 => SE (Character'Pos ('b'))));
      R : Dec.Decode_Result :=
        Dec.Decode (Pkt, Dec.Layout_Array'(1 => Dec.FK_String));
   begin
      Check (not R.Ok and then R.Reason = Dec.Truncated, "T-9 beyond remaining");
   end;

   --  T-10: one trailing byte => Trailing_Bytes.
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
      Check (not R.Ok and then R.Reason = Dec.Trailing_Bytes, "T-10 trailing");
   end;

   --  T-11: reason specificity already asserted per-case above (AC-8/AC-10);
   --  extra: truncated Int field is Truncated, not another reason.
   declare
      Full : SEA := Build (5, W_Mixed'Access);
      Layout : constant Dec.Layout_Array :=
        (Dec.FK_Boolean, Dec.FK_Byte, Dec.FK_Int, Dec.FK_Long);
      Pre : SEA := Full (Full'First .. Full'Last - 2);
      R : Dec.Decode_Result := Dec.Decode (Pre, Layout);
   begin
      Check (not R.Ok and then R.Reason = Dec.Truncated, "T-11 trunc int reason");
      Check ((R.Reason /= Dec.Trailing_Bytes
              and then R.Reason /= Dec.Id_Out_Of_Range
              and then R.Reason /= Dec.Overlong_Varint),
             "T-11 specificity");
   end;

   if Failures = 0 then
      Ada.Text_IO.Put_Line ("packet decoder tests passed");
   else
      Ada.Text_IO.Put_Line ("packet decoder tests failed");
      raise Program_Error with "packet decoder tests failed";
   end if;
end Test_Protocol_Packet_Decoder;
