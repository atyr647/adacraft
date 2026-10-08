with Interfaces;
with Adacraft.Protocol.Varnum;

package body Adacraft.Protocol.Packet_Decoder is

   use type Interfaces.Integer_32;
   use type Interfaces.Integer_64;
   use type Interfaces.Unsigned_32;
   use type Interfaces.Unsigned_64;
   use type Ada.Streams.Stream_Element;
   use type Ada.Streams.Stream_Element_Offset;
   use type Varnum.Status_Type;

   function Decode
     (Raw_Body : Ada.Streams.Stream_Element_Array;
      Layout   : Layout_Array) return Decode_Result
   is
      Result : Decode_Result;
      Total  : constant Natural := Natural (Raw_Body'Length);
      Idx    : Natural := 0;
      Octs   : Protocol.Octets (1 .. Natural'Max (1, Total));
   begin
      Result.Status := Protocol.Rejected;
      Result.Reason := Reason_Empty_Body;
      Result.Packet_Id := 0;

      if Total = 0 then
         Result.Reason := Reason_Empty_Body;
         return Result;
      end if;

      for I in 1 .. Total loop
         Octs (I) :=
           Protocol.Octet
             (Raw_Body
                (Raw_Body'First + Ada.Streams.Stream_Element_Offset (I) - 1));
      end loop;

      declare
         Value    : Interfaces.Integer_32 := 0;
         Consumed : Natural := 0;
         Status   : Varnum.Status_Type := Varnum.Truncated;
      begin
         Varnum.Decode (Octs (1 .. Total), 1, Value, Consumed, Status);
         if Status = Varnum.Truncated then
            Result.Reason := Reason_Truncated_Id;
            return Result;
         elsif Status /= Varnum.Ok then
            Result.Reason := Reason_Overlong_Id;
            return Result;
         end if;
         if Value < 0 then
            Result.Reason := Reason_Invalid_Id;
            return Result;
         end if;
         Result.Packet_Id := Natural (Value);
         Idx := Consumed;
      end;

      if Layout'Length > Max_Fields then
         Result.Reason := Reason_Truncated_Field;
         return Result;
      end if;

      for F in 1 .. Layout'Length loop
         declare
            K : constant Field_Kind := Layout (Layout'First + F - 1);
            Slot : Field_Value;
         begin
            Slot.Kind := K;
            case K is
               when Kind_Boolean =>
                  if Idx >= Total then
                     Result.Reason := Reason_Truncated_Field;
                     return Result;
                  end if;
                  declare
                     B : constant Ada.Streams.Stream_Element :=
                       Raw_Body
                         (Raw_Body'First +
                            Ada.Streams.Stream_Element_Offset (Idx));
                  begin
                     if B = 0 then
                        Slot.Bool_Value := False;
                     elsif B = 1 then
                        Slot.Bool_Value := True;
                     else
                        Result.Reason := Reason_Invalid_Boolean;
                        return Result;
                     end if;
                  end;
                  Idx := Idx + 1;
               when Kind_Byte =>
                  if Idx >= Total then
                     Result.Reason := Reason_Truncated_Field;
                     return Result;
                  end if;
                  Slot.Byte_Value :=
                    Raw_Body
                      (Raw_Body'First +
                         Ada.Streams.Stream_Element_Offset (Idx));
                  Idx := Idx + 1;
               when Kind_Int =>
                  if Total - Idx < 4 then
                     Result.Reason := Reason_Truncated_Field;
                     return Result;
                  end if;
                  declare
                     U : Interfaces.Unsigned_32 := 0;
                  begin
                     for J in 0 .. 3 loop
                        U := Interfaces.Shift_Left (U, 8) or
                          Interfaces.Unsigned_32
                            (Raw_Body
                               (Raw_Body'First +
                                  Ada.Streams.Stream_Element_Offset
                                    (Idx + J)));
                     end loop;
                     Slot.Int_Value :=
                       (if U >= 2 ** 31 then
                          Interfaces.Integer_32
                            (Interfaces.Integer_64 (U) - 2 ** 32)
                        else Interfaces.Integer_32 (U));
                  end;
                  Idx := Idx + 4;
               when Kind_Long =>
                  if Total - Idx < 8 then
                     Result.Reason := Reason_Truncated_Field;
                     return Result;
                  end if;
                  declare
                     U : Interfaces.Unsigned_64 := 0;
                  begin
                     for J in 0 .. 7 loop
                        U := Interfaces.Shift_Left (U, 8) or
                          Interfaces.Unsigned_64
                            (Raw_Body
                               (Raw_Body'First +
                                  Ada.Streams.Stream_Element_Offset
                                    (Idx + J)));
                     end loop;
                     if U >= 2 ** 63 then
                        Slot.Long_Value :=
                          Interfaces.Integer_64 (U - 2 ** 63) +
                            Interfaces.Integer_64'First;
                     else
                        Slot.Long_Value := Interfaces.Integer_64 (U);
                     end if;
                  end;
                  Idx := Idx + 8;
               when Kind_Varint =>
                  declare
                     Value    : Interfaces.Integer_32 := 0;
                     Consumed : Natural := 0;
                     Status   : Varnum.Status_Type := Varnum.Truncated;
                  begin
                     Varnum.Decode
                       (Octs (1 .. Total), Idx + 1, Value, Consumed, Status);
                     if Status = Varnum.Truncated then
                        Result.Reason := Reason_Truncated_Field;
                        return Result;
                     elsif Status /= Varnum.Ok then
                        Result.Reason := Reason_Overlong_Field;
                        return Result;
                     end if;
                     Slot.Varint_Value := Value;
                     Idx := Idx + Consumed;
                  end;
               when Kind_Varlong =>
                  declare
                     Value    : Interfaces.Integer_64 := 0;
                     Consumed : Natural := 0;
                     Status   : Varnum.Status_Type := Varnum.Truncated;
                  begin
                     Varnum.Decode_Varlong
                       (Octs (1 .. Total), Idx + 1, Value, Consumed, Status);
                     if Status = Varnum.Truncated then
                        Result.Reason := Reason_Truncated_Field;
                        return Result;
                     elsif Status /= Varnum.Ok then
                        Result.Reason := Reason_Overlong_Field;
                        return Result;
                     end if;
                     Slot.Varlong_Value := Value;
                     Idx := Idx + Consumed;
                  end;
               when Kind_String =>
                  declare
                     Lval     : Interfaces.Integer_32 := 0;
                     Consumed : Natural := 0;
                     Status   : Varnum.Status_Type := Varnum.Truncated;
                  begin
                     Varnum.Decode
                       (Octs (1 .. Total), Idx + 1, Lval, Consumed, Status);
                     if Status = Varnum.Truncated then
                        Result.Reason := Reason_Truncated_Field;
                        return Result;
                     elsif Status /= Varnum.Ok then
                        Result.Reason := Reason_Overlong_Field;
                        return Result;
                     end if;
                     if Lval < 0 then
                        Result.Reason := Reason_String_Negative_Length;
                        return Result;
                     end if;
                     if Lval > Interfaces.Integer_32 (String_Max) then
                        Result.Reason := Reason_String_Too_Long;
                        return Result;
                     end if;
                     declare
                        L : constant Natural := Natural (Lval);
                     begin
                        if Total - (Idx + Consumed) < L then
                           Result.Reason := Reason_String_Beyond_Remaining;
                           return Result;
                        end if;
                        Slot.Str_Len := L;
                        for J in 1 .. L loop
                           Slot.Str_Data (J) :=
                             Character'Val
                               (Natural
                                  (Raw_Body
                                     (Raw_Body'First +
                                        Ada.Streams.Stream_Element_Offset
                                          (Idx + Consumed + J - 1))));
                        end loop;
                        Idx := Idx + Consumed + L;
                     end;
                  end;
            end case;
            Result.Fields (F) := Slot;
         end;
      end loop;

      if Idx /= Total then
         Result.Reason := Reason_Trailing_Bytes;
         return Result;
      end if;

      Result.Status := Protocol.Ok;
      Result.Reason := Reason_None;
      return Result;
   end Decode;

end Adacraft.Protocol.Packet_Decoder;
