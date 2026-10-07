package body Adacraft.Protocol.Varnum is
   use type Interfaces.Unsigned_32;
   use type Interfaces.Integer_32;

   function To_Unsigned (Value : Interfaces.Integer_32)
     return Interfaces.Unsigned_32
   is
   begin
      if Value >= 0 then
         return Interfaces.Unsigned_32 (Value);
      elsif Value = Interfaces.Integer_32'First then
         return 16#8000_0000#;
      else
         return not Interfaces.Unsigned_32 (-Value - 1);
      end if;
   end To_Unsigned;

   function To_Signed (Value : Interfaces.Unsigned_32)
     return Interfaces.Integer_32
   is
   begin
      if Value <= Interfaces.Unsigned_32 (Interfaces.Integer_32'Last) then
         return Interfaces.Integer_32 (Value);
      elsif Value = 16#8000_0000# then
         return Interfaces.Integer_32'First;
      else
         return -(Interfaces.Integer_32 (not Value) + 1);
      end if;
   end To_Signed;

   function Encode (Value : Interfaces.Integer_32) return Encoding is
      U      : Interfaces.Unsigned_32 := To_Unsigned (Value);
      Group  : Interfaces.Unsigned_32;
      Result : Encoding := (Bytes => (others => 0), Length => 0);
   begin
      for Index in 1 .. Max_VarInt_Encoded_Length loop
         Group := U mod 128;
         U := U / 128;
         if U = 0 then
            Result.Bytes (Index) := Byte (Group);
            Result.Length := Index;
            return Result;
         end if;
         Result.Bytes (Index) := Byte (Group or 16#80#);
      end loop;
      --  Not reached for 32-bit input; kept for completeness.
      Result.Length := Max_VarInt_Encoded_Length;
      return Result;
   end Encode;

   procedure Decode
     (Data     : Byte_Array;
      Result   : out Status;
      Value    : out Interfaces.Integer_32;
      Consumed : out Natural)
   is
      Acc     : Interfaces.Unsigned_32 := 0;
      Current : Byte;
      Part    : Interfaces.Unsigned_32;
   begin
      Result := Truncated;
      Value := 0;
      Consumed := 0;

      for Index in 0 .. Max_VarInt_Encoded_Length - 1 loop
         if Index >= Data'Length then
            return;
         end if;

         Current := Data (Data'First + Index);

         if Index = Max_VarInt_Encoded_Length - 1
           and then ((Current and 16#80#) /= 0 or else (Current and 16#70#) /= 0)
         then
            Result := Overlong;
            return;
         end if;

         Part := Interfaces.Unsigned_32 (Current and 16#7F#);
         Acc := Acc or Interfaces.Shift_Left (Part, Index * 7);

         if (Current and 16#80#) = 0 then
            Value := To_Signed (Acc);
            Consumed := Index + 1;
            Result := Ok;
            return;
         end if;
      end loop;

      --  Not reached; the fifth byte always returns above.
      Result := Overlong;
   end Decode;

end Adacraft.Protocol.Varnum;
