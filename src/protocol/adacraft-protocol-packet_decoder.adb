with Ada.Unchecked_Conversion;

package body Adacraft.Protocol.Packet_Decoder is

   function To_I16 is new Ada.Unchecked_Conversion
     (Interfaces.Unsigned_16, Interfaces.Integer_16);
   function To_I32 is new Ada.Unchecked_Conversion
     (Interfaces.Unsigned_32, Interfaces.Integer_32);
   function To_I64 is new Ada.Unchecked_Conversion
     (Interfaces.Unsigned_64, Interfaces.Integer_64);

   procedure Decode
     (Payload     : in  Payload_Array;
      Layout      : in  Layout_Type;
      Packet_Id   : out Interfaces.Integer_32;
      Fields      : out Field_Array;
      Field_Count : out Natural;
      Status      : out Decode_Status)
   is
      use type Interfaces.Integer_32;
      use type Interfaces.Integer_64;
      use type Interfaces.Unsigned_8;
      use type Interfaces.Unsigned_16;
      use type Interfaces.Unsigned_32;
      use type Interfaces.Unsigned_64;
      use type Adacraft.Protocol.Varnum.Status_Type;

      Pos          : Natural := 0;
      V_Status     : Adacraft.Protocol.Varnum.Status_Type := Adacraft.Protocol.Varnum.Ok;
      Consumed     : Natural := 0;
      I32_Val      : Interfaces.Integer_32 := 0;
      I64_Val      : Interfaces.Integer_64 := 0;
      Len_Val      : Interfaces.Integer_32 := 0;

      procedure Reject is
      begin
         Field_Count := 0;
         Status := Rejected;
      end Reject;

      function In_Bounds (From : Natural; Need : Natural)
        return Standard.Boolean is
      begin
         if Need = 0 then
            return Standard.True;
         end if;
         if Payload'Length = 0 then
            return Standard.False;
         end if;
         if From > Payload'Last then
            return Standard.False;
         end if;
         if Need - 1 > Payload'Last - From then
            return Standard.False;
         end if;
         return Standard.True;
      end In_Bounds;

   begin
      Packet_Id := 0;
      Fields := [others => (Kind => VarInt, VarInt_Value => 0)];
      Field_Count := 0;
      Status := Rejected;

      if Payload'Length = 0 then
         return;
      end if;
      if Layout.Count > Max_Fields then
         return;
      end if;

      Pos := Payload'First;

      --  Packet-ID first via Varnum.
      if Pos > Payload'Last then
         return;
      end if;
      Adacraft.Protocol.Varnum.Decode
        (Buffer => Payload, Start_Index => Pos,
         Value => I32_Val, Consumed => Consumed, Status => V_Status);
      if V_Status /= Adacraft.Protocol.Varnum.Ok then
         return;
      end if;
      if Consumed = 0 then
         return;
      end if;
      Packet_Id := I32_Val;
      Pos := Pos + Consumed;

      for I in 1 .. Layout.Count loop
         declare
            K : constant Field_Kind := Layout.Kinds (I);
         begin
            case K is
               when VarInt =>
                  if Pos > Payload'Last then
                     return;
                  end if;
                  Adacraft.Protocol.Varnum.Decode
                    (Buffer => Payload, Start_Index => Pos,
                     Value => I32_Val, Consumed => Consumed, Status => V_Status);
                  if V_Status /= Adacraft.Protocol.Varnum.Ok then
                     return;
                  end if;
                  if Consumed = 0 then
                     return;
                  end if;
                  Pos := Pos + Consumed;
                  Fields (I) := (Kind => VarInt, VarInt_Value => I32_Val);

               when VarLong =>
                  if Pos > Payload'Last then
                     return;
                  end if;
                  Adacraft.Protocol.Varnum.Decode_Varlong
                    (Buffer => Payload, Start_Index => Pos,
                     Value => I64_Val, Consumed => Consumed, Status => V_Status);
                  if V_Status /= Adacraft.Protocol.Varnum.Ok then
                     return;
                  end if;
                  if Consumed = 0 then
                     return;
                  end if;
                  Pos := Pos + Consumed;
                  Fields (I) := (Kind => VarLong, VarLong_Value => I64_Val);

               when String =>
                  if Pos > Payload'Last then
                     return;
                  end if;
                  Adacraft.Protocol.Varnum.Decode
                    (Buffer => Payload, Start_Index => Pos,
                     Value => Len_Val, Consumed => Consumed, Status => V_Status);
                  if V_Status /= Adacraft.Protocol.Varnum.Ok then
                     return;
                  end if;
                  if Consumed = 0 then
                     return;
                  end if;
                  Pos := Pos + Consumed;
                  if Len_Val < 0 then
                     return;
                  end if;
                  if Len_Val > String_Max then
                     return;
                  end if;
                  if Len_Val = 0 then
                     Fields (I) :=
                       (Kind => String,
                        String_Data => [others => 0],
                        String_Len => 0);
                  else
                     declare
                        Need : constant Natural := Natural (Len_Val);
                        Tmp  : Payload_Array (1 .. String_Max) := [others => 0];
                     begin
                        if not In_Bounds (Pos, Need) then
                           return;
                        end if;
                        for J in 0 .. Need - 1 loop
                           Tmp (J + 1) := Payload (Pos + J);
                        end loop;
                        Pos := Pos + Need;
                        Fields (I) :=
                          (Kind => String, String_Data => Tmp,
                           String_Len => Need);
                     end;
                  end if;

               when Boolean =>
                  if Pos > Payload'Last then
                     return;
                  end if;
                  declare
                     B : constant Interfaces.Unsigned_8 := Payload (Pos);
                  begin
                     Pos := Pos + 1;
                     if B = 16#00# then
                        Fields (I) :=
                          (Kind => Field_Kind'(Boolean), Bool_Value => False);
                     elsif B = 16#01# then
                        Fields (I) :=
                          (Kind => Field_Kind'(Boolean), Bool_Value => True);
                     else
                        return;
                     end if;
                  end;

               when Byte =>
                  if not In_Bounds (Pos, 1) then
                     return;
                  end if;
                  declare
                     U : constant Interfaces.Unsigned_8 := Payload (Pos);
                     V : Interfaces.Integer_8;
                  begin
                     Pos := Pos + 1;
                     if U <= 16#7F# then
                        V := Interfaces.Integer_8 (U);
                     else
                        V := Interfaces.Integer_8
                          (Integer (U) - 256);
                     end if;
                     Fields (I) := (Kind => Byte, Byte_Value => V);
                  end;

               when Unsigned_Byte =>
                  if not In_Bounds (Pos, 1) then
                     return;
                  end if;
                  declare
                     U : constant Interfaces.Unsigned_8 := Payload (Pos);
                  begin
                     Pos := Pos + 1;
                     Fields (I) := (Kind => Unsigned_Byte, UByte_Value => U);
                  end;

               when Short | Unsigned_Short =>
                  if not In_Bounds (Pos, 2) then
                     return;
                  end if;
                  declare
                     Hi : constant Interfaces.Unsigned_16 :=
                       Interfaces.Unsigned_16 (Payload (Pos));
                     Lo : constant Interfaces.Unsigned_16 :=
                       Interfaces.Unsigned_16 (Payload (Pos + 1));
                     U  : constant Interfaces.Unsigned_16 :=
                       Interfaces.Shift_Left (Hi, 8) or Lo;
                  begin
                     Pos := Pos + 2;
                     if K = Short then
                        Fields (I) :=
                          (Kind => Short, Short_Value => To_I16 (U));
                     else
                        Fields (I) :=
                          (Kind => Unsigned_Short, UShort_Value => U);
                     end if;
                  end;

               when Int =>
                  if not In_Bounds (Pos, 4) then
                     return;
                  end if;
                  declare
                     U : Interfaces.Unsigned_32 := 0;
                  begin
                     for J in 0 .. 3 loop
                        U := Interfaces.Shift_Left (U, 8)
                          or Interfaces.Unsigned_32 (Payload (Pos + J));
                     end loop;
                     Pos := Pos + 4;
                     Fields (I) := (Kind => Int, Int_Value => To_I32 (U));
                  end;

               when Long =>
                  if not In_Bounds (Pos, 8) then
                     return;
                  end if;
                  declare
                     U : Interfaces.Unsigned_64 := 0;
                  begin
                     for J in 0 .. 7 loop
                        U := Interfaces.Shift_Left (U, 8)
                          or Interfaces.Unsigned_64 (Payload (Pos + J));
                     end loop;
                     Pos := Pos + 8;
                     Fields (I) := (Kind => Long, Long_Value => To_I64 (U));
                  end;
            end case;
         end;
      end loop;

      Field_Count := Layout.Count;
      if Pos = Payload'Last + 1 then
         Status := Success;
      else
         Field_Count := 0;
         Status := Rejected;
      end if;
   end Decode;

end Adacraft.Protocol.Packet_Decoder;
