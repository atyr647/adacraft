with Ada.Streams;
with Ada.Text_IO;
with Interfaces;
with Adacraft.Protocol.Frame;
with Adacraft.Protocol.Packet_Encoder;

procedure Test_Protocol_Packet_Encoder is
   package Enc renames Adacraft.Protocol.Packet_Encoder;
   use type Ada.Streams.Stream_Element;
   use type Ada.Streams.Stream_Element_Offset;

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

   if Failures = 0 then
      Ada.Text_IO.Put_Line ("packet encoder tests passed");
   else
      Ada.Text_IO.Put_Line ("packet encoder tests failed");
      raise Program_Error with "packet encoder tests failed";
   end if;
end Test_Protocol_Packet_Encoder;
