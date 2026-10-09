package body Adacraft.Protocol.Varnum
  with SPARK_Mode => On
is
   use type Interfaces.Unsigned_8;
   use type Interfaces.Unsigned_32;
   use type Interfaces.Integer_32;
   use type Interfaces.Integer_64;
   use type Interfaces.Unsigned_64;

   function Encoded_Length (Value : Interfaces.Integer_32) return Natural is
     (if Value < 0 then 5
      elsif Value < 2 ** 7 then 1
      elsif Value < 2 ** 14 then 2
      elsif Value < 2 ** 21 then 3
      elsif Value < 2 ** 28 then 4
      else 5);

   procedure Emit_Unsigned
     (Value       : in     Interfaces.Unsigned_64;
      Len         : in     Natural;
      Buffer      : in out Octets;
      Start_Index : in     Integer)
     with
       Global => null,
       Pre    => Len in 1 .. Max_Varlong_Bytes
                 and then Start_Index in Buffer'Range
                 and then Buffer'Last - Start_Index + 1 >= Len
   is
      U    : Interfaces.Unsigned_64 := Value;
      Byte : Octet;
   begin
      for I in 0 .. Len - 1 loop
         pragma Loop_Invariant (Start_Index + Len - 1 <= Buffer'Last);
         Byte := Octet (U and 16#7F#);
         U    := Interfaces.Shift_Right (U, 7);
         if I < Len - 1 then
            Byte := Byte or 16#80#;
         end if;
         Buffer (Start_Index + I) := Byte;
      end loop;
   end Emit_Unsigned;

   procedure Encode_Unsigned
     (Value       : in     Interfaces.Unsigned_64;
      Len         : in     Natural;
      Buffer      : in out Octets;
      Start_Index : in     Integer;
      Written     :    out Natural;
      Status      :    out Status_Type)
     with
       Global => null,
       Pre    => Len in 1 .. Max_Varlong_Bytes
   is
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

      Emit_Unsigned (Value, Len, Buffer, Start_Index);

      Written := Len;
      Status  := Ok;
   end Encode_Unsigned;

   procedure Encode
     (Value       : in     Interfaces.Integer_32;
      Buffer      : in out Octets;
      Start_Index : in     Integer;
      Written     :    out Natural;
      Status      :    out Status_Type)
   is
      Len : constant Natural := Encoded_Length (Value);
      V64 : Interfaces.Integer_64 := Interfaces.Integer_64 (Value);
      U   : Interfaces.Unsigned_64;
   begin
      if V64 < 0 then
         V64 := V64 + 2 ** 32;
      end if;
      U := Interfaces.Unsigned_64 (V64);

      Encode_Unsigned (U, Len, Buffer, Start_Index, Written, Status);
   end Encode;

   procedure Decode_Unsigned
     (Buffer      : in     Octets;
      Start_Index : in     Integer;
      Max_Bytes   : in     Positive;
      Last_Limit  : in     Octet;
      Value       :    out Interfaces.Unsigned_64;
      Consumed    :    out Natural;
      Status      :    out Status_Type)
     with
       Global => null,
       Pre    => Max_Bytes in 1 .. Max_Varlong_Bytes
   is
      Acc : Interfaces.Unsigned_64 := 0;
      Pos : Integer;
   begin
      Value    := 0;
      Consumed := 0;
      Status   := Truncated;

      if Buffer'Length = 0
        or else Start_Index < Buffer'First
        or else Start_Index > Buffer'Last
        or else Max_Bytes > Max_Varlong_Bytes
      then
         return;
      end if;

      Pos := Start_Index;

      for Step in 1 .. Max_Varlong_Bytes loop
         exit when Step > Max_Bytes;
         pragma Loop_Invariant (Pos in Buffer'Range);
         pragma Loop_Invariant (Step in 1 .. Max_Bytes);
         declare
            B    : constant Octet := Buffer (Pos);
            Bits : constant Interfaces.Unsigned_64 :=
              Interfaces.Unsigned_64 (B and 16#7F#);
         begin
            if Step = Max_Bytes and then B > Last_Limit then
               Status := Overlong;
               return;
            end if;

            Acc := Acc or Interfaces.Shift_Left (Bits, (Step - 1) * 7);

            if (B and 16#80#) = 0 then
               Value    := Acc;
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
   end Decode_Unsigned;

   procedure Decode
     (Buffer      : in     Octets;
      Start_Index : in     Integer;
      Value       :    out Interfaces.Integer_32;
      Consumed    :    out Natural;
      Status      :    out Status_Type)
   is
      Acc : Interfaces.Unsigned_64 := 0;
      C   : Natural;
      S   : Status_Type;
   begin
      Value    := 0;
      Consumed := 0;

      Decode_Unsigned
        (Buffer, Start_Index, Max_Varint_Bytes, 16#0F#, Acc, C, S);

      if S /= Ok then
         Status := S;
         return;
      end if;

      if Acc >= 2 ** 31 then
         Value := Interfaces.Integer_32
           (Interfaces.Integer_64 (Acc) - 2 ** 32);
      else
         Value := Interfaces.Integer_32 (Acc);
      end if;
      Consumed := C;
      Status   := Ok;
   end Decode;

   function Encoded_Length_Varlong (Value : Interfaces.Integer_64) return Natural is
     (if Value < 0 then 10
      elsif Value < 2 ** 7 then 1
      elsif Value < 2 ** 14 then 2
      elsif Value < 2 ** 21 then 3
      elsif Value < 2 ** 28 then 4
      elsif Value < 2 ** 35 then 5
      elsif Value < 2 ** 42 then 6
      elsif Value < 2 ** 49 then 7
      elsif Value < 2 ** 56 then 8
      else 9);

   procedure Encode_Varlong
     (Value       : in     Interfaces.Integer_64;
      Buffer      : in out Octets;
      Start_Index : in     Integer;
      Written     :    out Natural;
      Status      :    out Status_Type)
   is
      Len : constant Natural := Encoded_Length_Varlong (Value);
      U   : Interfaces.Unsigned_64;
   begin
      if Value < 0 then
         U := Interfaces.Unsigned_64 (Value + 2 ** 62 + 2 ** 62) + 2 ** 63;
      else
         U := Interfaces.Unsigned_64 (Value);
      end if;

      Encode_Unsigned (U, Len, Buffer, Start_Index, Written, Status);
   end Encode_Varlong;

   procedure Decode_Varlong
     (Buffer      : in     Octets;
      Start_Index : in     Integer;
      Value       :    out Interfaces.Integer_64;
      Consumed    :    out Natural;
      Status      :    out Status_Type)
   is
      Acc : Interfaces.Unsigned_64 := 0;
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

      for Step in 1 .. Max_Varlong_Bytes loop
         pragma Loop_Invariant (Pos in Buffer'Range);
         pragma Loop_Invariant (Step in 1 .. Max_Varlong_Bytes);
         declare
            B    : constant Octet := Buffer (Pos);
            Bits : constant Interfaces.Unsigned_64 :=
              Interfaces.Unsigned_64 (B and 16#7F#);
         begin
            if Step = Max_Varlong_Bytes and then B > 16#01# then
               Status := Overlong;
               return;
            end if;

            Acc := Acc or Interfaces.Shift_Left (Bits, (Step - 1) * 7);

            if (B and 16#80#) = 0 then
               if Acc >= 2 ** 63 then
                  Value := Interfaces.Integer_64 (Acc - 2 ** 63)
                           + Interfaces.Integer_64'First;
               else
                  Value := Interfaces.Integer_64 (Acc);
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
   end Decode_Varlong;

   function Decode_Varint (Buffer : Octets; From : Positive) return Varint_Result is
      V : Interfaces.Integer_32;
      C : Natural;
      S : Status_Type;
   begin
      if From > Buffer'Last then
         return (Status => Need_More, Value => 0, Next => From);
      end if;

      Decode (Buffer, From, V, C, S);
      case S is
         when Ok =>
            return
              (Status => Status_Kind'(Ok),
               Value  =>
                 (if V < 0
                  then Interfaces.Unsigned_32
                         (Interfaces.Integer_64 (V) + 2 ** 32)
                  else Interfaces.Unsigned_32 (V)),
               Next   => From + C);
         when Truncated =>
            return (Status => Need_More, Value => 0, Next => From);
         when Overlong | Buffer_Too_Small =>
            return (Status => Rejected, Value => 0, Next => From);
      end case;
   end Decode_Varint;

   function Decode_Varlong (Buffer : Octets; From : Positive) return Varlong_Result is
      V : Interfaces.Integer_64;
      C : Natural;
      S : Status_Type;
   begin
      if From > Buffer'Last then
         return (Status => Need_More, Value => 0, Next => From);
      end if;

      Decode_Varlong (Buffer, From, V, C, S);
      case S is
         when Ok =>
            return
              (Status => Status_Kind'(Ok),
               Value  => Interfaces.Unsigned_64 (V),
               Next   => From + C);
         when Truncated =>
            return (Status => Need_More, Value => 0, Next => From);
         when Overlong | Buffer_Too_Small =>
            return (Status => Rejected, Value => 0, Next => From);
      end case;
   end Decode_Varlong;
end Adacraft.Protocol.Varnum;
