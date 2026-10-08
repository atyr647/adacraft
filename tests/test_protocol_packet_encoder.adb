with Ada.Streams;
with Ada.Text_IO;
with Interfaces;
with Adacraft.Protocol;
with Adacraft.Protocol.Frame;
with Adacraft.Protocol.Packet_Encoder;
with Adacraft.Protocol.Varnum;

procedure Test_Protocol_Packet_Encoder is
   package Enc renames Adacraft.Protocol.Packet_Encoder;
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
         Ada.Text_IO.Put_Line ("FAIL encoder: " & Name);
      end if;
   end Check;

   function Same (A : SEA; B : SEA) return Boolean is
   begin
      if A'Length /= B'Length then
         return False;
      end if;
      for I in 0 .. A'Length - 1 loop
         if A (A'First + SEO (I)) /= B (B'First + SEO (I)) then
            return False;
         end if;
      end loop;
      return True;
   end Same;

   procedure Check_Body (E : Enc.Encoder_Type; Expected : SEA; Name : String) is
      Buf  : SEA (1 .. 32) := (others => 0);
      Last : SEO;
   begin
      Enc.Get_Body (E, Buf, Last);
      Check (SEO (Enc.Length (E)) = Last - Buf'First + 1
             and then SEO (Expected'Length) = Last - Buf'First + 1
             and then Same (Buf (Buf'First .. Last), Expected),
             Name);
   end Check_Body;

   type Enc_Access is access Enc.Encoder_Type;

   E : Enc_Access := new Enc.Encoder_Type;
   S : Enc_Access := new Enc.Encoder_Type (Capacity => 4);
begin
   Enc.Start_Packet (E.all, 0);
   Check (not Enc.Has_Failed (E.all), "id0 no fail");
   Check (Enc.Length (E.all) = 1, "id0 length");
   Check_Body (E.all, SEA'(1 => 16#00#), "id0 bytes");

   Enc.Start_Packet (E.all, 128);
   Check (not Enc.Has_Failed (E.all), "id128 no fail");
   Check (Enc.Length (E.all) = 2, "id128 length");
   Check_Body (E.all, SEA'(16#80#, 16#01#), "id128 bytes");

   Enc.Start_Packet (E.all, 0);
   Enc.Write_Boolean (E.all, True);
   Check (not Enc.Has_Failed (E.all), "bool true no fail");
   Check_Body (E.all, SEA'(16#00#, 16#01#), "bool true bytes");
   Enc.Start_Packet (E.all, 0);
   Enc.Write_Boolean (E.all, False);
   Check (not Enc.Has_Failed (E.all), "bool false no fail");
   Check_Body (E.all, SEA'(16#00#, 16#00#), "bool false bytes");

   Enc.Start_Packet (E.all, 0);
   Enc.Write_Byte (E.all, 16#AB#);
   Check (not Enc.Has_Failed (E.all), "byte no fail");
   Check_Body (E.all, SEA'(16#00#, 16#AB#), "byte value");

   Enc.Start_Packet (E.all, 0);
   Enc.Write_Int (E.all, 1);
   Check (not Enc.Has_Failed (E.all), "int1 no fail");
   Check_Body (E.all, SEA'(16#00#, 16#00#, 16#00#, 16#00#, 16#01#), "int 1");
   Enc.Start_Packet (E.all, 0);
   Enc.Write_Int (E.all, -1);
   Check (not Enc.Has_Failed (E.all), "int-1 no fail");
   Check_Body (E.all, SEA'(16#00#, 16#FF#, 16#FF#, 16#FF#, 16#FF#), "int -1");
   Enc.Start_Packet (E.all, 0);
   Enc.Write_Int (E.all, Interfaces.Integer_32'First);
   Check (not Enc.Has_Failed (E.all), "int first no fail");
   Check_Body (E.all, SEA'(16#00#, 16#80#, 16#00#, 16#00#, 16#00#), "int first");

   Enc.Start_Packet (E.all, 0);
   Enc.Write_Long (E.all, 1);
   Check (not Enc.Has_Failed (E.all), "long1 no fail");
   Check_Body (E.all, SEA'(16#00#, 16#00#, 16#00#, 16#00#, 16#00#, 16#00#, 16#00#, 16#00#, 16#01#), "long 1");
   Enc.Start_Packet (E.all, 0);
   Enc.Write_Long (E.all, -1);
   Check (not Enc.Has_Failed (E.all), "long-1 no fail");
   Check_Body (E.all, SEA'(16#00#, 16#FF#, 16#FF#, 16#FF#, 16#FF#, 16#FF#, 16#FF#, 16#FF#, 16#FF#), "long -1");
   Enc.Start_Packet (E.all, 0);
   Enc.Write_Long (E.all, Interfaces.Integer_64'First);
   Check (not Enc.Has_Failed (E.all), "long first no fail");
   Check_Body (E.all, SEA'(16#00#, 16#80#, 16#00#, 16#00#, 16#00#, 16#00#, 16#00#, 16#00#, 16#00#), "long first");

   declare
      Body_Buf  : SEA (1 .. 32) := (others => 0);
      Body_Last : SEO;
      Out_Buf   : SEA (1 .. 64) := (others => 0);
      Out_Last  : SEO;
      Len       : Natural;
   begin
      Enc.Start_Packet (E.all, 0);
      Enc.Write_Boolean (E.all, True);
      Enc.Write_Byte (E.all, 16#7E#);
      Check (not Enc.Has_Failed (E.all), "framed no fail");
      Len := Enc.Length (E.all);
      Enc.Get_Body (E.all, Body_Buf, Body_Last);
      Enc.Get_Framed (E.all, Out_Buf, Out_Last);
      Check (not Enc.Has_Failed (E.all), "framed get no fail");
      Check (Out_Last = Out_Buf'First + SEO (Len) + 1 - 1, "framed last");
      Check (Out_Buf (Out_Buf'First) = SE (Len), "framed prefix");
      Check (Same (Out_Buf (Out_Buf'First + 1 .. Out_Last),
        Body_Buf (Body_Buf'First .. Body_Last)), "framed body");
   end;

   declare
      Before : Natural;
      Buf    : SEA (1 .. 16) := (others => 0);
      L1     : SEO;
      Buf2   : SEA (1 .. 16) := (others => 0);
      L2     : SEO;
   begin
      Enc.Start_Packet (S.all, 0);
      Check (not Enc.Has_Failed (S.all), "small start ok");
      Check (Enc.Length (S.all) = 1, "small start len");
      Enc.Write_Int (S.all, 1);
      Check (Enc.Has_Failed (S.all), "small overflow failed");
      Before := Enc.Length (S.all);
      Check (Before = 1, "small overflow len unchanged");
      Enc.Get_Body (S.all, Buf, L1);
      Enc.Write_Byte (S.all, 16#FF#);
      Enc.Write_Boolean (S.all, True);
      Check (Enc.Has_Failed (S.all), "small sticky failed");
      Check (Enc.Length (S.all) = Before, "small sticky len unchanged");
      Enc.Get_Body (S.all, Buf2, L2);
      Check (L1 = L2
        and then Same (Buf (Buf'First .. L1), Buf2 (Buf2'First .. L2)),
        "small later writes no effect");
   end;

   Enc.Start_Packet (E.all, 0);
   Enc.Write_Boolean (E.all, True);
   Enc.Write_Byte (E.all, 16#01#);
   Enc.Write_Int (E.all, 1);
   Enc.Write_Long (E.all, 1);
   Check (not Enc.Has_Failed (E.all), "success has_failed false");

   --  T-1/T-2 decode round-trip tests.
   --  Shipped #210 defines exactly four field kinds (Boolean, Byte, Int,
   --  Long); there is no VarInt/VarLong field kind and no string kind.
   --  VarInt coverage below applies to the packet ID (VarInt-encoded);
   --  VarLong extremes apply to Long fields; string cases do not apply.
   declare
      BBuf  : SEA (1 .. 64) := (others => 0);
      BLast : SEO;
      Res   : Enc.Decode_Result;

      procedure Fetch (Layout : Enc.Layout_Array) is
         Len : Natural;
         Tmp : Enc.Body_Bytes (0 .. 63) := (others => 0);
      begin
         Enc.Get_Body (E.all, BBuf, BLast);
         Len := Natural (BLast - BBuf'First + 1);
         for I in 0 .. Len - 1 loop
            Tmp (I) := BBuf (BBuf'First + SEO (I));
         end loop;
         Enc.Decode (Tmp (0 .. Len - 1), Layout, Res);
      end Fetch;

      procedure Check_Ok_Id (Want_Id : Natural; Want_N : Natural; Name : String) is
      begin
         Check (Res.Status = Enc.Ok
           and then Res.Packet_Id = Want_Id
           and then Res.Count = Want_N, Name);
      end Check_Ok_Id;
   begin
      --  T-1: Boolean identity.
      Enc.Start_Packet (E.all, 0);
      Enc.Write_Boolean (E.all, True);
      Fetch (Enc.Layout_Array'(0 => Enc.Field_Boolean));
      Check_Ok_Id (0, 1, "T1 bool true ok");
      Check (Res.Values (1).Kind = Enc.Field_Boolean
        and then Res.Values (1).Bool_Val = True, "T1 bool true val");
      Enc.Start_Packet (E.all, 0);
      Enc.Write_Boolean (E.all, False);
      Fetch (Enc.Layout_Array'(0 => Enc.Field_Boolean));
      Check_Ok_Id (0, 1, "T1 bool false ok");
      Check (Res.Values (1).Kind = Enc.Field_Boolean
        and then Res.Values (1).Bool_Val = False, "T1 bool false val");

      --  T-1: Byte identity.
      for B in 0 .. 2 loop
         declare
            V : constant SE :=
              (if B = 0 then 16#00# elsif B = 1 then 16#AB# else 16#FF#);
         begin
            Enc.Start_Packet (E.all, 0);
            Enc.Write_Byte (E.all, V);
            Fetch (Enc.Layout_Array'(0 => Enc.Field_Byte));
            Check (Res.Status = Enc.Ok and then Res.Count = 1
              and then Res.Values (1).Kind = Enc.Field_Byte
              and then Res.Values (1).Byte_Val = V, "T1 byte val");
         end;
      end loop;

      --  T-1: Int identity incl. extremes.
      declare
         Vals : constant array (1 .. 7) of Interfaces.Integer_32 :=
           (0, 1, 127, 128, -1,
            Interfaces.Integer_32'First, Interfaces.Integer_32'Last);
      begin
         for I in Vals'Range loop
            Enc.Start_Packet (E.all, 0);
            Enc.Write_Int (E.all, Vals (I));
            Fetch (Enc.Layout_Array'(0 => Enc.Field_Int));
            Check (Res.Status = Enc.Ok and then Res.Count = 1
              and then Res.Values (1).Kind = Enc.Field_Int
              and then Res.Values (1).Int_Val = Vals (I), "T1 int val");
         end loop;
      end;

      --  T-1: Long identity incl. First/Last extremes.
      declare
         Vals : constant array (1 .. 5) of Interfaces.Integer_64 :=
           (0, 1, -1,
            Interfaces.Integer_64'First, Interfaces.Integer_64'Last);
      begin
         for I in Vals'Range loop
            Enc.Start_Packet (E.all, 0);
            Enc.Write_Long (E.all, Vals (I));
            Fetch (Enc.Layout_Array'(0 => Enc.Field_Long));
            Check (Res.Status = Enc.Ok and then Res.Count = 1
              and then Res.Values (1).Kind = Enc.Field_Long
              and then Res.Values (1).Long_Val = Vals (I), "T1 long val");
         end loop;
      end;

      --  T-1: packet-ID VarInt points 0,1,127,128,max (empty layout).
      declare
         Ids : constant array (1 .. 5) of Natural :=
           (0, 1, 127, 128, Natural (Interfaces.Integer_32'Last));
         Empty : constant Enc.Layout_Array (1 .. 0) := (others => Enc.Field_Boolean);
      begin
         for I in Ids'Range loop
            Enc.Start_Packet (E.all, Ids (I));
            Fetch (Empty);
            Check (Res.Status = Enc.Ok
              and then Res.Packet_Id = Ids (I)
              and then Res.Count = 0, "T1 id val");
         end loop;
      end;

      --  T-1: packet-ID with a payload field present.
      Enc.Start_Packet (E.all, 128);
      Enc.Write_Int (E.all, -1);
      Fetch (Enc.Layout_Array'(0 => Enc.Field_Int));
      Check_Ok_Id (128, 1, "T1 id128+int ok");
      Check (Res.Values (1).Int_Val = -1, "T1 id128+int val");

      --  T-2: single layout containing every Field_Kind, golden bytes
      --  from the #210 encoder, values asserted in order.
      declare
         Layout : constant Enc.Layout_Array (0 .. 3) :=
           (Enc.Field_Boolean, Enc.Field_Byte, Enc.Field_Int, Enc.Field_Long);
         Expect : constant SEA :=
           (16#05#, 16#01#, 16#AB#,
            16#01#, 16#02#, 16#03#, 16#04#,
            16#01#, 16#02#, 16#03#, 16#04#,
            16#05#, 16#06#, 16#07#, 16#08#);
         GBuf  : SEA (1 .. 32) := (others => 0);
         GLast : SEO;
         Len   : Natural;
         Tmp   : Enc.Body_Bytes (0 .. 31) := (others => 0);
      begin
         Enc.Start_Packet (E.all, 5);
         Enc.Write_Boolean (E.all, True);
         Enc.Write_Byte (E.all, 16#AB#);
         Enc.Write_Int (E.all, 16#01020304#);
         Enc.Write_Long (E.all, 16#0102030405060708#);
         Check (not Enc.Has_Failed (E.all), "T2 encode no fail");
         Enc.Get_Body (E.all, GBuf, GLast);
         Len := Natural (GLast - GBuf'First + 1);
         Check (Natural (Expect'Length) = Len
           and then Same (GBuf (GBuf'First .. GLast), Expect),
           "T2 golden bytes");
         for I in 0 .. Len - 1 loop
            Tmp (I) := GBuf (GBuf'First + SEO (I));
         end loop;
         Enc.Decode (Tmp (0 .. Len - 1), Layout, Res);
         Check (Res.Status = Enc.Ok
           and then Res.Packet_Id = 5
           and then Res.Count = 4, "T2 decode ok");
         Check (Res.Values (1).Kind = Enc.Field_Boolean
           and then Res.Values (1).Bool_Val = True, "T2 field bool");
         Check (Res.Values (2).Kind = Enc.Field_Byte
           and then Res.Values (2).Byte_Val = 16#AB#, "T2 field byte");
         Check (Res.Values (3).Kind = Enc.Field_Int
           and then Res.Values (3).Int_Val = 16#01020304#, "T2 field int");
         Check (Res.Values (4).Kind = Enc.Field_Long
           and then Res.Values (4).Long_Val = 16#0102030405060708#,
           "T2 field long");
      end;

      --  T-3: every strict prefix 0 .. n-1 of the valid T-2 multi-field
      --  body rejects as Truncated (AC-7/AC-11).
      declare
         Layout : constant Enc.Layout_Array (0 .. 3) :=
           (Enc.Field_Boolean, Enc.Field_Byte, Enc.Field_Int, Enc.Field_Long);
         Full : constant Enc.Body_Bytes (0 .. 14) :=
           (16#05#, 16#01#, 16#AB#,
            16#01#, 16#02#, 16#03#, 16#04#,
            16#01#, 16#02#, 16#03#, 16#04#,
            16#05#, 16#06#, 16#07#, 16#08#);
         Empty_Body : constant Enc.Body_Bytes (1 .. 0) :=
           (others => 0);
         R : Enc.Decode_Result;
      begin
         Enc.Decode (Empty_Body, Layout, R);
         Check (R.Status = Enc.Truncated, "T3 prefix 0 truncated");
         for N in 1 .. Full'Length - 1 loop
            Enc.Decode (Full (Full'First .. Full'First + N - 1), Layout, R);
            Check (R.Status = Enc.Truncated, "T3 prefix truncated");
         end loop;
         --  Sanity: the full body decodes Ok.
         Enc.Decode (Full, Layout, R);
         Check (R.Status = Enc.Ok
           and then R.Packet_Id = 5
           and then R.Count = 4, "T3 full ok");
      end;

      --  T-4: overlong VarInt ID (6 bytes) => Overlong_Varint; 11-byte
      --  VarLong encoding => Varnum Overlong (decoder has no VarLong
      --  field kind in shipped #210, so the VarLong leg is covered at
      --  the Varnum codec the decoder delegates to; the decoder's
      --  Overlong_Varlong status is retained for that mapping).
      declare
         Empty : constant Enc.Layout_Array (1 .. 0) :=
           (others => Enc.Field_Boolean);
         Over_Id : constant Enc.Body_Bytes (0 .. 5) :=
           (16#80#, 16#80#, 16#80#, 16#80#, 16#80#, 16#01#);
         R : Enc.Decode_Result;
         Buf : Adacraft.Protocol.Octets (1 .. 11) := (others => 16#80#);
         Val : Interfaces.Integer_64 := 0;
         Consumed : Natural := 0;
         St : Adacraft.Protocol.Varnum.Status_Type;
      begin
         Enc.Decode (Over_Id, Empty, R);
         Check (R.Status = Enc.Overlong_Varint, "T4 overlong varint id");
         Buf (11) := 16#01#;
         Adacraft.Protocol.Varnum.Decode_Varlong (Buf, 1, Val, Consumed, St);
         Check (St = Adacraft.Protocol.Varnum.Overlong,
           "T4 overlong varlong");
         Check (Enc.Overlong_Varlong /= Enc.Ok, "T4 status present");
      end;

      --  T-5: hand-crafted negative VarInt ID (-1) => Id_Out_Of_Range
      --  (shipped #210 packet-ID range is Natural/non-negative).
      declare
         Empty : constant Enc.Layout_Array (1 .. 0) :=
           (others => Enc.Field_Boolean);
         Neg_Id : constant Enc.Body_Bytes (0 .. 4) :=
           (16#FF#, 16#FF#, 16#FF#, 16#FF#, 16#0F#);
         R : Enc.Decode_Result;
      begin
         Enc.Decode (Neg_Id, Empty, R);
         Check (R.Status = Enc.Id_Out_Of_Range, "T5 negative id range");
      end;
   end;

   if Failures = 0 then
      Ada.Text_IO.Put_Line ("packet encoder tests passed");
   else
      Ada.Text_IO.Put_Line ("packet encoder tests failed");
      raise Program_Error with "packet encoder tests failed";
   end if;
end Test_Protocol_Packet_Encoder;
