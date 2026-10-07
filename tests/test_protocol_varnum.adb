with Ada.Command_Line;
with Ada.Text_IO;
with Interfaces;
with Adacraft.Protocol;
with Adacraft.Protocol.Varnum;

procedure Test_Protocol_Varnum is
   package V renames Adacraft.Protocol.Varnum;
   use Adacraft.Protocol;
   use type Interfaces.Integer_32;
   use type Interfaces.Unsigned_8;
   use type V.Status_Type;

   Failures : Natural := 0;

   procedure Check (Condition : Boolean; Name : String) is
   begin
      if not Condition then
         Failures := Failures + 1;
         Ada.Text_IO.Put_Line ("FAIL: " & Name);
      end if;
   end Check;

   type Value_Array is array (Positive range <>) of Interfaces.Integer_32;

   Values : constant Value_Array :=
     (0, 1, 127, 128, 255, 16383, 16384, 2_097_151, 2_097_152,
      268_435_455, 268_435_456, Interfaces.Integer_32'Last,
      -1, -128, Interfaces.Integer_32'First);

   --  Encode at Start in Buf, then decode again; check shape and length.
   procedure Round_Trip (Value : Interfaces.Integer_32; Name : String) is
      Buf  : Octets (1 .. 8) := (others => 16#AA#);
      W, C : Natural;
      S    : V.Status_Type;
      D    : Interfaces.Integer_32;
      Good : Boolean := True;
   begin
      V.Encode (Value, Buf, 1, W, S);
      Check (S = V.Ok and then W = V.Encoded_Length (Value),
             Name & " encode length");
      if S /= V.Ok or else W not in 1 .. 5 then
         return;
      end if;
      for I in 1 .. W - 1 loop
         if Buf (I) < 16#80# then
            Good := False;
         end if;
      end loop;
      Check (Good and then Buf (W) < 16#80#, Name & " continuation bits");
      Check (Buf (W + 1) = 16#AA#, Name & " no write past end");
      V.Decode (Buf, 1, D, C, S);
      Check (S = V.Ok and then D = Value and then C = W,
             Name & " round trip");
      Check (Value >= 0 or else W = 5, Name & " negative uses 5 bytes");
   end Round_Trip;

   --  Decode and expect an error with value 0 and consumed 0.
   procedure Expect_Error
     (Buf : Octets; Start : Integer; Expected : V.Status_Type; Name : String)
   is
      D : Interfaces.Integer_32;
      C : Natural;
      S : V.Status_Type;
   begin
      V.Decode (Buf, Start, D, C, S);
      Check (S = Expected and then D = 0 and then C = 0, Name);
   end Expect_Error;

   --  Decode and expect Ok with a given value and consumed count.
   procedure Expect_Ok
     (Buf : Octets; Start : Integer; Value : Interfaces.Integer_32;
      Count : Natural; Name : String)
   is
      D : Interfaces.Integer_32;
      C : Natural;
      S : V.Status_Type;
   begin
      V.Decode (Buf, Start, D, C, S);
      Check (S = V.Ok and then D = Value and then C = Count, Name);
   end Expect_Ok;

   --  A run of N continuation bytes.
   function Run (N : Positive) return Octets is
     (1 .. N => 16#80#);

   Empty : constant Octets (1 .. 0) := (others => 0);
begin
   --  Round trips and lengths for many values.
   for I in Values'Range loop
      Round_Trip (Values (I), "value" & Integer'Image (I));
   end loop;

   --  A few literal encodings.
   declare
      Buf  : Octets (1 .. 4) := (others => 16#AA#);
      W    : Natural;
      S    : V.Status_Type;
   begin
      V.Encode (0, Buf, 1, W, S);
      Check (S = V.Ok and then W = 1 and then Buf (1) = 16#00#, "literal 0");
      V.Encode (127, Buf, 1, W, S);
      Check (S = V.Ok and then W = 1 and then Buf (1) = 16#7F#,
             "literal 127");
      V.Encode (128, Buf, 1, W, S);
      Check (S = V.Ok and then W = 2 and then Buf (1) = 16#80#
             and then Buf (2) = 16#01#, "literal 128");
   end;

   --  Encode at a non-first index in a buffer whose First is not 1.
   declare
      Buf    : Octets (10 .. 15) := (others => 16#AA#);
      Before : constant Octets (10 .. 15) := Buf;
      W      : Natural;
      S      : V.Status_Type;
      Same   : Boolean := True;
   begin
      V.Encode (128, Buf, 12, W, S);
      Check (S = V.Ok and then W = 2 and then Buf (12) = 16#80#
             and then Buf (13) = 16#01#, "encode at index 12");
      for I in Buf'Range loop
         if I not in 12 .. 13 and then Buf (I) /= Before (I) then
            Same := False;
         end if;
      end loop;
      Check (Same, "encode leaves other bytes alone");
   end;

   --  Encode that does not fit: nothing written, buffer unchanged.
   declare
      Buf    : Octets (1 .. 4) := (others => 16#AA#);
      Before : constant Octets (1 .. 4) := Buf;
      W      : Natural;
      S      : V.Status_Type;
   begin
      V.Encode (-1, Buf, 1, W, S);
      Check (S = V.Buffer_Too_Small and then W = 0 and then Buf = Before,
             "5-byte value into 4 bytes");
      V.Encode (128, Buf, 4, W, S);
      Check (S = V.Buffer_Too_Small and then W = 0 and then Buf = Before,
             "2-byte value at last index");
      V.Encode (1, Buf, 5, W, S);
      Check (S = V.Buffer_Too_Small and then W = 0 and then Buf = Before,
             "start past end");
      V.Encode (1, Buf, 0, W, S);
      Check (S = V.Buffer_Too_Small and then W = 0 and then Buf = Before,
             "start before first");
   end;

   --  Encode that exactly fits.
   declare
      Buf : Octets (1 .. 5) := (others => 16#AA#);
      W   : Natural;
      S   : V.Status_Type;
   begin
      V.Encode (-1, Buf, 1, W, S);
      Check (S = V.Ok and then W = 5, "5-byte value into 5 bytes");
   end;

   --  Truncated.
   Expect_Error (Empty, 1, V.Truncated, "empty buffer");
   Expect_Error (Octets'(1 => 16#05#), 2, V.Truncated, "start past last");
   Expect_Error (Octets'(1 => 16#05#), 0, V.Truncated, "start before first");
   for N in 1 .. 4 loop
      Expect_Error (Run (N), 1, V.Truncated,
                    "truncated run of" & Integer'Image (N));
   end loop;

   --  Overlong: 5th byte continuation (6th byte not needed), longer runs.
   for N in 5 .. 8 loop
      Expect_Error (Run (N), 1, V.Overlong,
                    "overlong run of" & Integer'Image (N));
   end loop;

   --  Overlong: 5th byte above 16#0F#; 16#0F# is still fine.
   declare
      Buf : Octets := Run (4) & Octets'(1 => 16#10#);
   begin
      Expect_Error (Buf, 1, V.Overlong, "5th byte 10");
      Buf (5) := 16#0F#;
      Expect_Ok (Buf, 1, -268_435_456, 5, "5th byte 0F");
   end;

   --  Non-minimal forms are accepted.
   Expect_Ok (Octets'(16#80#, 16#00#), 1, 0, 2, "non-minimal zero");
   Expect_Ok (Octets'(16#FF#, 16#00#), 1, 127, 2, "non-minimal 127");
   Expect_Ok (Run (4) & Octets'(1 => 16#00#), 1, 0, 5, "5-byte zero");

   --  Trailing bytes are ignored; non-first index; First not 1.
   declare
      Buf : Octets (10 .. 15) := (others => 16#FF#);
   begin
      Buf (12) := 16#80#;
      Buf (13) := 16#01#;
      Expect_Ok (Buf, 12, 128, 2, "decode at index 12, trailing ignored");
      Expect_Error (Buf, 9, V.Truncated, "start before First 10");
      Expect_Error (Buf, 16, V.Truncated, "start past Last 15");
   end;

   if Failures = 0 then
      Ada.Text_IO.Put_Line ("varnum tests passed");
   else
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
   end if;
end Test_Protocol_Varnum;
