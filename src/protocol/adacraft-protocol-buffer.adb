package body Adacraft.Protocol.Buffer is
   use type Interfaces.Unsigned_8;
   use type Interfaces.Unsigned_32;
   use type Interfaces.Unsigned_16;
   use type Interfaces.Unsigned_64;
   use type Status_Kind;
   procedure Reset (W : in out Writer) is
   begin
      W.Len := 0;
      W.Failed := False;
   end Reset;

   procedure Put_Octet (W : in out Writer; Value : Octet) is
   begin
      if W.Failed or else W.Len >= W.Capacity then
         W.Failed := True;
         return;
      end if;
      W.Len := W.Len + 1;
      W.Data (W.Len) := Value;
   end Put_Octet;

   procedure Put_Bytes (W : in out Writer; Value : Octets) is
   begin
      for B of Value loop
         Put_Octet (W, B);
      end loop;
   end Put_Bytes;

   procedure Put_Varint (W : in out Writer; Value : Interfaces.Unsigned_32) is
      Rest : Interfaces.Unsigned_32 := Value;
      Byte : Interfaces.Unsigned_32;
   begin
      loop
         Byte := Rest and 16#7F#;
         Rest := Interfaces.Shift_Right (Rest, 7);
         if Rest /= 0 then
            Put_Octet (W, Octet (Byte or 16#80#));
         else
            Put_Octet (W, Octet (Byte));
            exit;
         end if;
      end loop;
   end Put_Varint;

   procedure Put_U16 (W : in out Writer; Value : Interfaces.Unsigned_16) is
   begin
      Put_Octet (W, Octet (Interfaces.Shift_Right (Value, 8)));
      Put_Octet (W, Octet (Value and 16#FF#));
   end Put_U16;

   procedure Put_U64 (W : in out Writer; Value : Interfaces.Unsigned_64) is
   begin
      for Shift in reverse 0 .. 7 loop
         Put_Octet
           (W,
            Octet (Interfaces.Shift_Right (Value, Shift * 8) and 16#FF#));
      end loop;
   end Put_U64;

   procedure Put_String (W : in out Writer; Value : String) is
   begin
      Put_Varint (W, Interfaces.Unsigned_32 (Value'Length));
      for Ch of Value loop
         Put_Octet (W, Octet (Character'Pos (Ch)));
      end loop;
   end Put_String;

   function Decode_Varint (Buffer : Octets; From : Positive) return Varint_Result is
      Result : Interfaces.Unsigned_32 := 0;
      Pos    : Natural                := From;
   begin
      if From > Buffer'Last then
         return (Status => Need_More, Value => 0, Next => From);
      end if;

      for Step in 1 .. Max_Varint_Bytes loop
         pragma Loop_Invariant (Pos in From .. Buffer'Last);
         declare
            B     : constant Octet := Buffer (Pos);
            Bits  : constant Interfaces.Unsigned_32 :=
              Interfaces.Unsigned_32 (B and 16#7F#);
            Shift : constant Natural := (Step - 1) * 7;
         begin
            if Step = Max_Varint_Bytes and then Bits > 15 then
               return (Status => Rejected, Value => 0, Next => From);
            end if;
            Result := Result or Interfaces.Shift_Left (Bits, Shift);
            Pos    := Pos + 1;
            if (B and 16#80#) = 0 then
               if Step > 1 and then Bits = 0 then
                  return (Status => Rejected, Value => 0, Next => From);
               end if;
               return (Status => Ok, Value => Result, Next => Pos);
            end if;
            if Pos > Buffer'Last then
               return (Status => Need_More, Value => 0, Next => From);
            end if;
         end;
      end loop;
      return (Status => Rejected, Value => 0, Next => From);
   end Decode_Varint;

   function Remaining (Last : Natural; From : Natural) return Natural is
     (if From > Last then 0 else Last - From + 1);

   function Decode_String
     (Buffer : Octets; From : Positive; Max_Chars : Positive) return String_Decode
   is
      Dec : constant Varint_Result := Decode_Varint (Buffer, From);
      Len : Natural;
      Pos : Natural;
      Decoded : String_Decode;
   begin
      if Dec.Status /= Ok then
         return (Status => Dec.Status, Text => (others => ' '), Length => 0, Next => From);
      end if;
      if Dec.Value > Interfaces.Unsigned_32 (Max_Chars) then
         return (Status => Rejected, Text => (others => ' '), Length => 0, Next => From);
      end if;
      Len := Natural (Dec.Value);
      Pos := Dec.Next;
      if Remaining (Buffer'Last, Pos) < Len then
         return (Status => Need_More, Text => (others => ' '), Length => 0, Next => From);
      end if;
      Decoded.Status := Ok;
      Decoded.Length := Len;
      Decoded.Next := Pos + Len;
      for I in 1 .. Len loop
         declare
            B : constant Octet := Buffer (Pos + I - 1);
         begin
            Decoded.Text (I) := Character'Val (Natural (B));
         end;
      end loop;
      return Decoded;
   end Decode_String;

   function U16_Ok (Buffer : Octets; From : Positive) return Boolean is
     (From <= Buffer'Last and then Buffer'Last - From >= 1);

   function Decode_U16
     (Buffer : Octets; From : Positive) return Interfaces.Unsigned_16
   is
      Hi : constant Interfaces.Unsigned_16 := Interfaces.Unsigned_16 (Buffer (From));
      Lo : constant Interfaces.Unsigned_16 := Interfaces.Unsigned_16 (Buffer (From + 1));
   begin
      return Interfaces.Shift_Left (Hi, 8) or Lo;
   end Decode_U16;

   function U64_Ok (Buffer : Octets; From : Positive) return Boolean is
     (From <= Buffer'Last and then Buffer'Last - From >= 7);

   function Decode_U64
     (Buffer : Octets; From : Positive) return Interfaces.Unsigned_64
   is
      Acc : Interfaces.Unsigned_64 := 0;
   begin
      for I in 0 .. 7 loop
         Acc := Interfaces.Shift_Left (Acc, 8) or Interfaces.Unsigned_64 (Buffer (From + I));
      end loop;
      return Acc;
   end Decode_U64;
end Adacraft.Protocol.Buffer;
