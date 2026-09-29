package body Adacraft.Protocol.Varnum
  with SPARK_Mode
is
   use type Interfaces.Unsigned_8;
   use type Interfaces.Unsigned_32;
   use type Interfaces.Unsigned_64;
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

   function Decode_Varlong (Buffer : Octets; From : Positive) return Varlong_Result is
      Result : Interfaces.Unsigned_64 := 0;
      Pos    : Natural                := From;
   begin
      if From > Buffer'Last then
         return (Status => Need_More, Value => 0, Next => From);
      end if;

      for Step in 1 .. Max_Varlong_Bytes loop
         pragma Loop_Invariant (Pos in From .. Buffer'Last);
         declare
            B     : constant Octet := Buffer (Pos);
            Bits  : constant Interfaces.Unsigned_64 :=
              Interfaces.Unsigned_64 (B and 16#7F#);
            Shift : constant Natural := (Step - 1) * 7;
         begin
            if Step = Max_Varlong_Bytes and then Bits > 1 then
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
   end Decode_Varlong;
end Adacraft.Protocol.Varnum;
