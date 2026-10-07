package body Adacraft.Protocol.Varnum
  with SPARK_Mode => On
is
   use type Interfaces.Unsigned_8;
   use type Interfaces.Unsigned_32;
   use type Interfaces.Integer_32;
   use type Interfaces.Integer_64;

   function Encoded_Length (Value : Interfaces.Integer_32) return Natural is
     (if Value < 0 then 5
      elsif Value < 2 ** 7 then 1
      elsif Value < 2 ** 14 then 2
      elsif Value < 2 ** 21 then 3
      elsif Value < 2 ** 28 then 4
      else 5);

   procedure Encode
     (Value       : in     Interfaces.Integer_32;
      Buffer      : in out Octets;
      Start_Index : in     Integer;
      Written     :    out Natural;
      Status      :    out Status_Type)
   is
      Len  : constant Natural := Encoded_Length (Value);
      V64  : Interfaces.Integer_64 := Interfaces.Integer_64 (Value);
      U    : Interfaces.Unsigned_32;
      Byte : Octet;
   begin
      Written := 0;
      Status  := Buffer_Too_Small;

      if Buffer'Length = 0
        or else Start_Index < Buffer'First
        or else Start_Index > Buffer'Last
        or else Buffer'Last - Start_Index + 1 < Len
      then
         return;
      end if;

      if V64 < 0 then
         V64 := V64 + 2 ** 32;
      end if;
      U := Interfaces.Unsigned_32 (V64);

      for I in 0 .. Len - 1 loop
         pragma Loop_Invariant (Start_Index + Len - 1 <= Buffer'Last);
         Byte := Octet (U and 16#7F#);
         U    := Interfaces.Shift_Right (U, 7);
         if I < Len - 1 then
            Byte := Byte or 16#80#;
         end if;
         Buffer (Start_Index + I) := Byte;
      end loop;

      Written := Len;
      Status  := Ok;
   end Encode;

   procedure Decode
     (Buffer      : in     Octets;
      Start_Index : in     Integer;
      Value       :    out Interfaces.Integer_32;
      Consumed    :    out Natural;
      Status      :    out Status_Type)
   is
      Acc : Interfaces.Unsigned_32 := 0;
      Pos : Integer;
   begin
      Value    := 0;
      Consumed := 0;
      Status   := Truncated;

      if Buffer'Length = 0
        or else Start_Index < Buffer'First
        or else Start_Index > Buffer'Last
      then
         return;
      end if;

      Pos := Start_Index;

      for Step in 1 .. Max_Varint_Bytes loop
         pragma Loop_Invariant (Pos in Buffer'Range);
         declare
            B    : constant Octet := Buffer (Pos);
            Bits : constant Interfaces.Unsigned_32 :=
              Interfaces.Unsigned_32 (B and 16#7F#);
         begin
            if Step = Max_Varint_Bytes and then B > 16#0F# then
               Status := Overlong;
               return;
            end if;

            Acc := Acc or Interfaces.Shift_Left (Bits, (Step - 1) * 7);

            if (B and 16#80#) = 0 then
               if Acc >= 2 ** 31 then
                  Value := Interfaces.Integer_32
                    (Interfaces.Integer_64 (Acc) - 2 ** 32);
               else
                  Value := Interfaces.Integer_32 (Acc);
               end if;
               Consumed := Step;
               Status   := Ok;
               return;
            end if;

            if Pos >= Buffer'Last then
               Status := Truncated;
               return;
            end if;
            Pos := Pos + 1;
         end;
      end loop;

      Status := Overlong;
   end Decode;
end Adacraft.Protocol.Varnum;
