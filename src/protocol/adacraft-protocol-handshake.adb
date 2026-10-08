with Adacraft.Protocol.Buffer;
with Adacraft.Protocol.Status_Info;
with Adacraft.Protocol.Varnum;

package body Adacraft.Protocol.Handshake is

   use type Interfaces.Unsigned_32;
   use type Status_Kind;

   function Map_Intention
     (Value : Interfaces.Unsigned_32; Intent : out Intention_Kind) return Boolean
   is
   begin
      case Value is
         when 1 =>
            Intent := To_Status;
            return True;
         when 2 | 3 =>
            Intent := To_Login;
            return True;
         when others =>
            Intent := To_Status;
            return False;
      end case;
   end Map_Intention;

   function Address (Data : Handshake_Data) return String is
   begin
      if Data.Addr_Len = 0 then
         return "";
      else
         return Data.Server_Address (1 .. Data.Addr_Len);
      end if;
   end Address;

   function Decode (Payload : Octets) return Decode_Result is
      Empty : constant Decode_Result := (Status => Violation);
   begin
      if Payload'Length = 0 then
         return Empty;
      end if;
      if Payload'First < Positive'First
        or else Payload'Last > Positive'Last - 1
      then
         return Empty;
      end if;

      --  Field 1: VarInt protocol version.
      declare
         Ver : constant Varnum.Varint_Result :=
           Varnum.Decode_Varint (Payload, Payload'First);
      begin
         if Ver.Status /= Ok then
            return Empty;
         end if;

         --  Field 2: String server address, byte length <= 255.
         declare
            Str : constant Buffer.String_Decode :=
              Buffer.Decode_String (Payload, Ver.Next, Max_Address_Bytes);
         begin
            if Str.Status /= Ok then
               return Empty;
            end if;
            --  Address must be valid UTF-8 (validated on stored copy).
            declare
               Addr_Text : String (1 .. Str.Length);
            begin
               for I in 1 .. Str.Length loop
                  Addr_Text (I) := Str.Text (I);
               end loop;
               if not Status_Info.Is_Valid_Utf8
                 (Addr_Text (1 .. Str.Length))
               then
                  return Empty;
               end if;

               --  Field 3: U16 big-endian port.
               if not Buffer.U16_Ok (Payload, Str.Next) then
                  return Empty;
               end if;
               declare
                  Port_Val : constant Interfaces.Unsigned_16 :=
                    Buffer.Decode_U16 (Payload, Str.Next);
                  After_Port : constant Natural := Str.Next + 2;
               begin
                  if After_Port > Payload'Last + 1 then
                     return Empty;
                  end if;
                  if After_Port > Payload'Last then
                     --  Missing intention field.
                     return Empty;
                  end if;

                  --  Field 4: VarInt intention.
                  declare
                     Int : constant Varnum.Varint_Result :=
                       Varnum.Decode_Varint (Payload, After_Port);
                  begin
                     if Int.Status /= Ok then
                        return Empty;
                     end if;
                     --  Exact-consumption rule: no trailing bytes.
                     if Int.Next /= Payload'Last + 1 then
                        return Empty;
                     end if;
                     declare
                        Kind : Intention_Kind;
                     begin
                        if not Map_Intention (Int.Value, Kind) then
                           return Empty;
                        end if;
                        declare
                           V32 : constant Interfaces.Unsigned_32 := Ver.Value;
                           Pver : Integer;
                        begin
                           if V32 <= Interfaces.Unsigned_32 (Integer'Last) then
                              Pver := Integer (V32);
                           else
                              --  Wrap as signed 32-bit value.
                              Pver := Integer
                                (Interfaces.Integer_32
                                   (Interfaces.Integer_64 (V32) - 2 ** 32));
                           end if;
                           declare
                              Data : Handshake_Data;
                           begin
                              Data.Protocol_Version := Pver;
                              Data.Addr_Len := Str.Length;
                              Data.Server_Address := (others => ' ');
                              for I in 1 .. Str.Length loop
                                 Data.Server_Address (I) := Str.Text (I);
                              end loop;
                              Data.Port := Port_Number (Port_Val);
                              Data.Intention := Kind;
                              Data.Raw_Intention := Int.Value;
                              return (Status => Ok, Data => Data);
                           end;
                        end;
                     end;
                  end;
               end;
            end;
         end;
      end;
   exception
      when others =>
         return Empty;
   end Decode;

end Adacraft.Protocol.Handshake;
