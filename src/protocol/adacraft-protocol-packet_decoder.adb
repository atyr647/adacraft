with Interfaces;
with Adacraft.Protocol.Varnum;

package body Adacraft.Protocol.Packet_Decoder is

   use type Adacraft.Protocol.Varnum.Status_Type;
   use type Interfaces.Unsigned_8;
   use type Interfaces.Unsigned_16;
   use type Interfaces.Unsigned_32;
   use type Interfaces.Unsigned_64;
   use type Interfaces.Integer_16;
   use type Interfaces.Integer_32;
   use type Interfaces.Integer_64;

   procedure Decode
     (Payload     : in  Byte_Array;
      Layout      : in  Layout_Type;
      Status      : out Decode_Status;
      Packet_Id   : out Interfaces.Integer_32;
      Fields      : out Field_Array;
      Field_Count : out Natural)
   is
      Data : Adacraft.Protocol.Octets (1 .. Payload'Length) :=
        (others => 0);
      Pos  : Natural := 1;

      function Need (Count : Natural) return Boolean is
      begin
         return Count <= Payload'Length
           and then Pos <= Payload'Length - Count + 1;
      end Need;

      function Byte_At (Offset : Natural) return Byte_Type is
        (Data (Positive (Offset)));

      procedure Read_Varint
        (Value : out Interfaces.Integer_32;
         Result : out Decode_Status)
      is
         Consumed : Natural := 0;
         V_Status : Adacraft.Protocol.Varnum.Status_Type;
      begin
         Value := 0;
         Adacraft.Protocol.Varnum.Decode
           (Data, Integer (Pos), Value, Consumed, V_Status);
         case V_Status is
            when Adacraft.Protocol.Varnum.Ok =>
               Pos := Pos + Consumed;
               Result := Success;
            when Adacraft.Protocol.Varnum.Truncated =>
               Result := Truncated_Field;
            when Adacraft.Protocol.Varnum.Overlong =>
               Result := Bad_VarInt;
            when Adacraft.Protocol.Varnum.Buffer_Too_Small =>
               Result := Bad_VarInt;
         end case;
      end Read_Varint;

      procedure Read_Varlong
        (Value : out Interfaces.Integer_64;
         Result : out Decode_Status)
      is
         Consumed : Natural := 0;
         V_Status : Adacraft.Protocol.Varnum.Status_Type;
      begin
         Value := 0;
         Adacraft.Protocol.Varnum.Decode_Varlong
           (Data, Integer (Pos), Value, Consumed, V_Status);
         case V_Status is
            when Adacraft.Protocol.Varnum.Ok =>
               Pos := Pos + Consumed;
               Result := Success;
            when Adacraft.Protocol.Varnum.Truncated =>
               Result := Truncated_Field;
            when Adacraft.Protocol.Varnum.Overlong =>
               Result := Bad_VarLong;
            when Adacraft.Protocol.Varnum.Buffer_Too_Small =>
               Result := Bad_VarLong;
         end case;
      end Read_Varlong;

      procedure Read_Fixed
        (Width : Positive;
         Value : out Interfaces.Unsigned_64;
         Result : out Decode_Status)
      is
         Acc : Interfaces.Unsigned_64 := 0;
      begin
         Value := 0;
         if not Need (Width) then
            Result := Truncated_Field;
            return;
         end if;

         --  This is a counted big-endian assembly loop, not a VarInt decoder.
         for I in 0 .. Width - 1 loop
            Acc := Interfaces.Shift_Left (Acc, 8)
              or Interfaces.Unsigned_64 (Byte_At (Pos + I));
         end loop;
         Pos := Pos + Width;
         Value := Acc;
         Result := Success;
      end Read_Fixed;

      procedure Decode_Field
        (Kind : Field_Kind;
         Field : out Decoded_Field;
         Result : out Decode_Status)
      is
         U : Interfaces.Unsigned_64 := 0;
         V32 : Interfaces.Integer_32 := 0;
         V64 : Interfaces.Integer_64 := 0;
         Length : Interfaces.Integer_32 := 0;
         Length_Status : Decode_Status := Success;
      begin
         Result := Success;
         case Kind is
            when VarInt =>
               Read_Varint (V32, Result);
               if Result = Success then
                  Field := (Kind => VarInt, VarInt_Value => V32);
               end if;

            when VarLong =>
               Read_Varlong (V64, Result);
               if Result = Success then
                  Field := (Kind => VarLong, VarLong_Value => V64);
               end if;

            when Boolean_Field =>
               if not Need (1) then
                  Result := Truncated_Field;
               elsif Byte_At (Pos) = 16#00# then
                  Pos := Pos + 1;
                  Field := (Kind => Boolean_Field, Bool_Value => False);
               elsif Byte_At (Pos) = 16#01# then
                  Pos := Pos + 1;
                  Field := (Kind => Boolean_Field, Bool_Value => True);
               else
                  Result := Bad_Boolean;
               end if;

            when Byte =>
               Read_Fixed (1, U, Result);
               if Result = Success then
                  if U < 2 ** 7 then
                     Field := (Kind => Byte,
                               Byte_Value => Interfaces.Integer_8 (U));
                  else
                     Field := (Kind => Byte,
                               Byte_Value => Interfaces.Integer_8
                                 (Interfaces.Integer_16 (U)
                                  - Interfaces.Integer_16 (2 ** 8)));
                  end if;
               end if;

            when Unsigned_Byte =>
               Read_Fixed (1, U, Result);
               if Result = Success then
                  Field := (Kind => Unsigned_Byte,
                            UByte_Value => Interfaces.Unsigned_8 (U));
               end if;

            when Short =>
               Read_Fixed (2, U, Result);
               if Result = Success then
                  if U < 2 ** 15 then
                     Field := (Kind => Short,
                               Short_Value => Interfaces.Integer_16 (U));
                  else
                     Field := (Kind => Short,
                               Short_Value => Interfaces.Integer_16
                                 (Interfaces.Integer_32 (U)
                                  - Interfaces.Integer_32 (2 ** 16)));
                  end if;
               end if;

            when Unsigned_Short =>
               Read_Fixed (2, U, Result);
               if Result = Success then
                  Field := (Kind => Unsigned_Short,
                            UShort_Value => Interfaces.Unsigned_16 (U));
               end if;

            when Int =>
               Read_Fixed (4, U, Result);
               if Result = Success then
                  if U < 2 ** 31 then
                     Field := (Kind => Int,
                               Int_Value => Interfaces.Integer_32 (U));
                  else
                     Field := (Kind => Int,
                               Int_Value => Interfaces.Integer_32
                                 (Interfaces.Integer_64 (U)
                                  - Interfaces.Integer_64 (2 ** 32)));
                  end if;
               end if;

            when Long =>
               Read_Fixed (8, U, Result);
               if Result = Success then
                  if U < 2 ** 63 then
                     Field := (Kind => Long,
                               Long_Value => Interfaces.Integer_64 (U));
                  else
                     Field := (Kind => Long,
                               Long_Value =>
                                 Interfaces.Integer_64'First
                                 + Interfaces.Integer_64
                                   (U - 2 ** 63));
                  end if;
               end if;

            when String_Field =>
               Read_Varint (Length, Length_Status);
               if Length_Status /= Success then
                  Result := Length_Status;
               elsif Length < 0 then
                  Result := Negative_String_Length;
               elsif Length > String_Max then
                  Result := String_Too_Long;
               elsif not Need (Natural (Length)) then
                  Result := String_Overrun;
               else
                  declare
                     Content : String_Storage := (others => 0);
                     N : constant Natural := Natural (Length);
                  begin
                     if N > 0 then
                        for I in 0 .. N - 1 loop
                           Content (I) := Byte_At (Pos + I);
                        end loop;
                     end if;
                     Pos := Pos + N;
                     Field := (Kind => String_Field,
                               Str_Len => N,
                               Str_Data => Content);
                  end;
               end if;
         end case;
      end Decode_Field;

   begin
      Status := Empty_Input;
      Packet_Id := 0;
      Field_Count := 0;

      if Payload'Length = 0 then
         return;
      end if;

      for I in 1 .. Payload'Length loop
         Data (I) := Payload (Payload'First + I - 1);
      end loop;

      if Layout'Length > Max_Fields then
         Status := Too_Many_Fields;
         return;
      end if;

      declare
         Consumed : Natural := 0;
         V_Status : Adacraft.Protocol.Varnum.Status_Type;
      begin
         Adacraft.Protocol.Varnum.Decode
           (Data, Integer (Pos), Packet_Id, Consumed, V_Status);
         case V_Status is
            when Adacraft.Protocol.Varnum.Ok =>
               Pos := Pos + Consumed;
            when Adacraft.Protocol.Varnum.Truncated =>
               Status := Truncated_Packet_Id;
               return;
            when Adacraft.Protocol.Varnum.Overlong =>
               Status := Bad_VarInt;
               return;
            when Adacraft.Protocol.Varnum.Buffer_Too_Small =>
               Status := Bad_VarInt;
               return;
         end case;
      end;

      if Layout'Length > Fields'Length then
         Status := Too_Many_Fields;
         return;
      end if;

      for I in 1 .. Layout'Length loop
         declare
            Item : Decoded_Field (Kind => Layout (Layout'First + I - 1));
            Field_Status : Decode_Status;
         begin
            Decode_Field (Layout (Layout'First + I - 1), Item, Field_Status);
            if Field_Status /= Success then
               Status := Field_Status;
               return;
            end if;
            Fields (Fields'First + I - 1) := Item;
            Field_Count := I;
         end;
      end loop;

      if Pos <= Payload'Length then
         Status := Trailing_Bytes;
         return;
      end if;

      Status := Success;

   exception
      when others =>
         Packet_Id := 0;
         Field_Count := 0;
         Status := Truncated_Field;
   end Decode;

end Adacraft.Protocol.Packet_Decoder;
