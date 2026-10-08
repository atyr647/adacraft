with Interfaces;
with Adacraft.Protocol.Varnum;

package body Adacraft.Protocol.Packet_Decoder is

   use type Interfaces.Integer_32;
   use type Interfaces.Integer_64;
   use type Interfaces.Unsigned_8;
   use type Interfaces.Unsigned_64;

   procedure Decode
     (Data : in Byte_Array;
      L    : in Layout;
      R    : out Decode_Result)
   is
      Pos       : Positive := Data'First;
      String_Pos : Natural := 1;

      procedure Reject is
      begin
         R.Success := False;
      end Reject;

      function Read_Varint
        (Value : out Interfaces.Integer_32) return Boolean
      is
         Result : constant Adacraft.Protocol.Varnum.Varint_Result :=
           Adacraft.Protocol.Varnum.Decode_Varint (Data, Pos);
      begin
         Value := 0;
         if Result.Status /= Adacraft.Protocol.Ok then
            return False;
         end if;
         if Result.Value <= Interfaces.Unsigned_32 (Interfaces.Integer_32'Last) then
            Value := Interfaces.Integer_32 (Result.Value);
         else
            Value :=
              Interfaces.Integer_32
                (Interfaces.Integer_64 (Result.Value) - 2 ** 32);
         end if;
         Pos := Result.Next;
         return True;
      end Read_Varint;

      function Read_Varlong
        (Value : out Interfaces.Integer_64) return Boolean
      is
         Result : constant Adacraft.Protocol.Varnum.Varlong_Result :=
           Adacraft.Protocol.Varnum.Decode_Varlong (Data, Pos);
      begin
         Value := 0;
         if Result.Status /= Adacraft.Protocol.Ok then
            return False;
         end if;
         if Result.Value <= Interfaces.Unsigned_64 (Interfaces.Integer_64'Last) then
            Value := Interfaces.Integer_64 (Result.Value);
         else
            Value :=
              Interfaces.Integer_64'First
                + Interfaces.Integer_64
                    (Result.Value - 16#8000_0000_0000_0000#);
         end if;
         Pos := Result.Next;
         return True;
      end Read_Varlong;

   begin
      R := (others => <>);

      --  Varnum's result-returning interfaces permit the cursor at the
      --  position immediately after the final payload byte.
      if Data'Last >= Positive'Last then
         return;
      end if;

      if not Read_Varint (R.Packet_Id) then
         return;
      end if;

      R.Field_Count := L.Count;

      for Index in 1 .. L.Count loop
         case L.Kinds (Index) is
            when Kind_VarInt =>
               declare
                  Value : Interfaces.Integer_32 := 0;
               begin
                  if not Read_Varint (Value) then
                     Reject;
                     return;
                  end if;
                  R.Fields (Index) :=
                    (Kind => Kind_VarInt, Value_32 => Value);
               end;

            when Kind_VarLong =>
               declare
                  Value : Interfaces.Integer_64 := 0;
               begin
                  if not Read_Varlong (Value) then
                     Reject;
                     return;
                  end if;
                  R.Fields (Index) :=
                    (Kind => Kind_VarLong, Value_64 => Value);
               end;

            when Kind_String =>
               declare
                  Length_32 : Interfaces.Integer_32 := 0;
                  Length    : Natural;
               begin
                  if not Read_Varint (Length_32)
                    or else Length_32 < 0
                    or else Length_32 > String_Max
                  then
                     Reject;
                     return;
                  end if;

                  Length := Natural (Length_32);
                  if Pos > Data'Last + 1
                    or else Length > Data'Last - Pos + 1
                    or else Length > String_Max - String_Pos + 1
                  then
                     Reject;
                     return;
                  end if;

                  R.Fields (Index) :=
                    (Kind => Kind_String,
                     String_Offset => String_Pos,
                     String_Length => Length);

                  if Length > 0 then
                     for Offset in 0 .. Length - 1 loop
                        R.Strings (String_Pos + Offset) := Data (Pos + Offset);
                        --  Convert each checked wire byte to its character
                        --  value without unchecked buffer access.
                        declare
                           Ch : constant Character :=
                             Character'Val (Data (Pos + Offset));
                        begin
                           pragma Unreferenced (Ch);
                        end;
                     end loop;
                  end if;

                  Pos := Pos + Length;
                  String_Pos := String_Pos + Length;
               end;

            when Kind_Boolean =>
               if Pos > Data'Last then
                  Reject;
                  return;
               end if;
               case Data (Pos) is
                  when 16#00# =>
                     R.Fields (Index) :=
                       (Kind => Kind_Boolean, Boolean_Value => False);
                  when 16#01# =>
                     R.Fields (Index) :=
                       (Kind => Kind_Boolean, Boolean_Value => True);
                  when others =>
                     Reject;
                     return;
               end case;
               Pos := Pos + 1;

            when Kind_I8 | Kind_I16 | Kind_I32 | Kind_I64 =>
               declare
                  Width : constant Natural :=
                    (case L.Kinds (Index) is
                       when Kind_I8  => 1,
                       when Kind_I16 => 2,
                       when Kind_I32 => 4,
                       when Kind_I64 => 8,
                       when others   => 0);
                  Acc : Interfaces.Unsigned_64 := 0;
               begin
                  if Pos > Data'Last
                    or else Width > Data'Last - Pos + 1
                  then
                     Reject;
                     return;
                  end if;

                  for Offset in 0 .. Width - 1 loop
                     Acc := Interfaces.Shift_Left (Acc, 8)
                       or Interfaces.Unsigned_64 (Data (Pos + Offset));
                  end loop;
                  Pos := Pos + Width;

                  case L.Kinds (Index) is
                     when Kind_I8 =>
                        if Acc >= 16#80# then
                           R.Fields (Index) :=
                             (Kind => Kind_I8,
                              Value_8 =>
                                Interfaces.Integer_8
                                  (Interfaces.Integer_16 (Acc) - 2 ** 8));
                        else
                           R.Fields (Index) :=
                             (Kind => Kind_I8,
                              Value_8 => Interfaces.Integer_8 (Acc));
                        end if;

                     when Kind_I16 =>
                        if Acc >= 16#8000# then
                           R.Fields (Index) :=
                             (Kind => Kind_I16,
                              Value_16 =>
                                Interfaces.Integer_16
                                  (Interfaces.Integer_32 (Acc) - 2 ** 16));
                        else
                           R.Fields (Index) :=
                             (Kind => Kind_I16,
                              Value_16 => Interfaces.Integer_16 (Acc));
                        end if;

                     when Kind_I32 =>
                        if Acc >= 16#8000_0000# then
                           R.Fields (Index) :=
                             (Kind => Kind_I32,
                              Value_32 =>
                                Interfaces.Integer_32
                                  (Interfaces.Integer_64 (Acc) - 2 ** 32));
                        else
                           R.Fields (Index) :=
                             (Kind => Kind_I32,
                              Value_32 => Interfaces.Integer_32 (Acc));
                        end if;

                     when Kind_I64 =>
                        if Acc >= 16#8000_0000_0000_0000# then
                           R.Fields (Index) :=
                             (Kind => Kind_I64,
                              Value_64 =>
                                Interfaces.Integer_64'First
                                  + Interfaces.Integer_64
                                      (Acc - 16#8000_0000_0000_0000#));
                        else
                           R.Fields (Index) :=
                             (Kind => Kind_I64, Value_64 => Interfaces.Integer_64 (Acc));
                        end if;

                     when others =>
                        null;
                  end case;
               end;
         end case;
      end loop;

      if Pos /= Data'Last + 1 then
         Reject;
         return;
      end if;

      R.Success := True;

   exception
      when others =>
         R.Success := False;
   end Decode;

end Adacraft.Protocol.Packet_Decoder;
