with Ada.Command_Line;
with Ada.Text_IO;
with Interfaces;
with Adacraft.Protocol.Varnum;

procedure Test_Varnum is
   package V renames Adacraft.Protocol.Varnum;
   use type Interfaces.Integer_32;
   use type V.Byte;
   use type V.Status;

   Failures : Natural := 0;

   procedure Check (Cond : Boolean; Name : String) is
   begin
      if not Cond then
         Ada.Text_IO.Put_Line ("FAIL " & Name);
         Failures := Failures + 1;
      end if;
   end Check;

   --  Builds a 1-based byte array from the non-negative arguments.
   function Seq
     (A : Integer := -1; B : Integer := -1; C : Integer := -1;
      D : Integer := -1; E : Integer := -1; F : Integer := -1)
      return V.Byte_Array
   is
      Items : constant array (1 .. 6) of Integer := (A, B, C, D, E, F);
      N     : Natural := 0;
   begin
      for I in Items'Range loop
         if Items (I) >= 0 then
            N := N + 1;
         end if;
      end loop;
      declare
         R : V.Byte_Array (1 .. N);
         K : Natural := 0;
      begin
         for I in Items'Range loop
            if Items (I) >= 0 then
               K := K + 1;
               R (K) := V.Byte (Items (I));
            end if;
         end loop;
         return R;
      end;
   end Seq;

   procedure Check_Vector
     (Value : Interfaces.Integer_32; Expected : V.Byte_Array; Name : String)
   is
      Enc  : constant V.Encoding := V.Encode (Value);
      Same : Boolean := Enc.Length = Expected'Length;
      St   : V.Status;
      Got  : Interfaces.Integer_32;
      Used : Natural;
   begin
      if Same then
         for I in 0 .. Expected'Length - 1 loop
            if Enc.Bytes (1 + I) /= Expected (Expected'First + I) then
               Same := False;
            end if;
         end loop;
      end if;
      Check (Same, Name & " encode");

      V.Decode (Expected, St, Got, Used);
      Check
        (St = V.Ok and then Got = Value and then Used = Expected'Length,
         Name & " decode");

      V.Decode (V.Byte_Array (Enc.Bytes (1 .. Enc.Length)), St, Got, Used);
      Check
        (St = V.Ok and then Got = Value and then Used = Enc.Length,
         Name & " round trip");
   end Check_Vector;

   procedure Check_Status
     (Data : V.Byte_Array; Expected : V.Status; Name : String)
   is
      St   : V.Status;
      Got  : Interfaces.Integer_32 := 99;
      Used : Natural := 99;
   begin
      V.Decode (Data, St, Got, Used);
      Check (St = Expected, Name & " status");
      Check (Got = 0, Name & " value zero");
      Check (Used = 0, Name & " consumed zero");
   end Check_Status;

   St   : V.Status;
   Got  : Interfaces.Integer_32;
   Used : Natural;
begin
   --  Exact vectors, decode and round trip.
   Check_Vector (0, Seq (0), "0");
   Check_Vector (1, Seq (1), "1");
   Check_Vector (127, Seq (127), "127");
   Check_Vector (128, Seq (128, 1), "128");
   Check_Vector (255, Seq (255, 1), "255");
   Check_Vector (Interfaces.Integer_32'Last, Seq (255, 255, 255, 255, 7), "max");
   Check_Vector (-1, Seq (255, 255, 255, 255, 15), "minus one");
   Check_Vector (Interfaces.Integer_32'First, Seq (128, 128, 128, 128, 8), "min");

   --  Negative values always take five bytes.
   Check (V.Encode (-2).Length = 5, "negative length");

   --  Trailing bytes are neither read nor consumed.
   V.Decode (Seq (127, 1), St, Got, Used);
   Check (St = V.Ok and then Got = 127 and then Used = 1, "trailing bytes");

   --  Non-minimal form is accepted.
   V.Decode (Seq (128, 0), St, Got, Used);
   Check (St = V.Ok and then Got = 0 and then Used = 2, "non-minimal");

   --  Offset slices.
   declare
      Buf : V.Byte_Array (1 .. 20) := (others => 0);
      Neg : constant V.Byte_Array (-3 .. -2) := (128, 1);
   begin
      Buf (10) := 128;
      Buf (11) := 1;
      V.Decode (Buf (10 .. 11), St, Got, Used);
      Check (St = V.Ok and then Got = 128 and then Used = 2, "offset slice");

      V.Decode (Neg, St, Got, Used);
      Check (St = V.Ok and then Got = 128 and then Used = 2, "negative bounds");

      --  The byte after the slice must not be read.
      Check_Status (Buf (10 .. 10), V.Truncated, "slice end");
   end;

   --  Truncated inputs.
   declare
      Empty : constant V.Byte_Array (1 .. 0) := (others => 0);
   begin
      Check_Status (Empty, V.Truncated, "empty");
   end;
   Check_Status (Seq (128), V.Truncated, "trunc 1");
   Check_Status (Seq (255, 255), V.Truncated, "trunc 2");
   Check_Status (Seq (255, 255, 255), V.Truncated, "trunc 3");
   Check_Status (Seq (255, 255, 255, 255), V.Truncated, "trunc 4");

   --  Overlong inputs.
   Check_Status (Seq (255, 255, 255, 255, 255, 1), V.Overlong, "six-byte run");
   Check_Status (Seq (255, 255, 255, 255, 128), V.Overlong, "fifth continuation");
   Check_Status (Seq (255, 255, 255, 255, 31), V.Overlong, "fifth extra bits");
   Check_Status (Seq (255, 255, 255, 255, 16), V.Overlong, "fifth lowest extra bit");

   if Failures = 0 then
      Ada.Text_IO.Put_Line ("varnum tests passed");
   else
      Ada.Text_IO.Put_Line ("varnum tests failed:" & Failures'Image);
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
   end if;
end Test_Varnum;
