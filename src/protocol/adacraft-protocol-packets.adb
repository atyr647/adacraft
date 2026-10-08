with Adacraft.Protocol.Frame;
with Adacraft.Protocol.Ids;
with Adacraft.Protocol.Varnum;

package body Adacraft.Protocol.Packets is
   function Decode_Handshake (Payload : Octets) return Handshake is
      Result  : Handshake;
      Version : Varnum.Varint_Result;
      Address : Buffer.String_Decode;
      Intent  : Varnum.Varint_Result;
   begin
      if Payload'Length = 0 then
         Result.Status := Rejected;
         return Result;
      end if;
      Version := Varnum.Decode_Varint (Payload, Payload'First);
      if Version.Status /= Ok then
         Result.Status := Version.Status;
         return Result;
      end if;
      Address := Buffer.Decode_String (Payload, Version.Next, 255);
      if Address.Status /= Ok then
         Result.Status := Rejected;
         return Result;
      end if;
      if Address.Next > Payload'Last or else Payload'Last - Address.Next < 1 then
         Result.Status := Rejected;
         return Result;
      end if;
      if Address.Next > Natural'Last - 2
        or else Address.Next + 2 > Payload'Last + 1
      then
         Result.Status := Rejected;
         return Result;
      end if;
      Intent := Varnum.Decode_Varint (Payload, Address.Next + 2);
      if Intent.Status /= Ok or else Intent.Next /= Payload'Last + 1 then
         Result.Status := Rejected;
         return Result;
      end if;
      Result.Status := Ok;
      Result.Version := Version.Value;
      Result.Addr_Len := Address.Length;
      Result.Address (1 .. Address.Length) := Address.Text (1 .. Address.Length);
      Result.Port := Buffer.Decode_U16 (Payload, Address.Next);
      Result.Intent := Intent.Value;
      Result.Next := Intent.Next;
      return Result;
   end Decode_Handshake;

   procedure Encode_Status_Response (W : in out Buffer.Writer) is
      JSON : constant String :=
        "{""version"":{""name"":""26.3"",""protocol"":777},"
        & """players"":{""max"":20,""online"":0},"
        & """description"":{""text"":""AdaCraft""}}";
   begin
      Buffer.Put_Varint (W, Interfaces.Unsigned_32 (Ids.Protocol_Id (Ids.Cb_Status_Status_Response)));
      Buffer.Put_String (W, JSON);
   end Encode_Status_Response;

   procedure Encode_Pong (W : in out Buffer.Writer; Payload : Interfaces.Unsigned_64) is
   begin
      Buffer.Put_Varint (W, Interfaces.Unsigned_32 (Ids.Protocol_Id (Ids.Cb_Status_Pong_Response)));
      Buffer.Put_U64 (W, Payload);
   end Encode_Pong;

   procedure Encode_Login_Disconnect (W : in out Buffer.Writer; Reason : String) is
      JSON : constant String := "{""text"":""" & Reason & """}";
   begin
      Buffer.Put_Varint
        (W, Interfaces.Unsigned_32 (Ids.Protocol_Id (Ids.Cb_Login_Login_Disconnect)));
      Buffer.Put_String (W, JSON);
   end Encode_Login_Disconnect;

   function Frame (W : in out Buffer.Writer; Payload : Buffer.Writer) return Boolean is
   begin
      if Payload.Failed or else Payload.Len = 0 then
         return False;
      end if;
      Buffer.Reset (W);
      Buffer.Put_Varint (W, Interfaces.Unsigned_32 (Payload.Len));
      Buffer.Put_Bytes (W, Payload.Data (1 .. Payload.Len));
      return not W.Failed;
   end Frame;

   function Decode_Ping (Payload : Octets) return Ping is
   begin
      if not Buffer.U64_Ok (Payload, Payload'First) or else Payload'Length /= 8 then
         return (Status => Rejected, Value => 0);
      end if;
      return (Status => Ok, Value => Buffer.Decode_U64 (Payload, Payload'First));
   end Decode_Ping;

   procedure Touch_Frame_Max is
      Dummy : Natural := Adacraft.Protocol.Frame.Max_Frame_Body_Length;
      pragma Unreferenced (Dummy);
   begin
      null;
   end Touch_Frame_Max;

   function Decode
     (Raw : Byte_Array;
      Layout : Field_Kind_Array) return Decode_Result
   is
      use type Interfaces.Integer_32;
      use type Interfaces.Integer_64;
      use type Interfaces.Unsigned_8;
      use type Interfaces.Unsigned_32;
      use type Interfaces.Unsigned_64;

      Ok_Res   : Decode_Result (Ok => True);
      Pos      : Natural := 0;
      Last     : Natural := 0;
      Idone    : Boolean := False;

      function Remaining return Natural is
        (if Pos > Last then 0 else Last - Pos + 1);

      procedure Fail (E : Decode_Error_Kind; R : out Decode_Result) is
      begin
         R := (Ok => False, Err => E);
      end Fail;
   begin
      if Raw'Length = 0 then
         return (Ok => False, Err => Truncated);
      end if;
      if Raw'Length > Adacraft.Protocol.Frame.Max_Frame_Body_Length then
         return (Ok => False, Err => Invalid_Field_Value);
      end if;
      if Layout'Length > Max_Decode_Fields then
         return (Ok => False, Err => Invalid_Field_Value);
      end if;

      Pos := Raw'First;
      Last := Raw'First + Raw'Length - 1;

      --  Packet ID via Varnum VarInt.
      declare
         V : Interfaces.Integer_32 := 0;
         C : Natural := 0;
         S : Varnum.Status_Type := Varnum.Truncated;
      begin
         if Pos < Raw'First or else Pos > Last then
            return (Ok => False, Err => Truncated);
         end if;
         Varnum.Decode (Raw, Pos, V, C, S);
         case S is
            when Varnum.Ok =>
               null;
            when Varnum.Truncated =>
               return (Ok => False, Err => Truncated);
            when Varnum.Overlong =>
               return (Ok => False, Err => Overlong);
            when Varnum.Buffer_Too_Small =>
               return (Ok => False, Err => Truncated);
         end case;
         if V < 0 then
            return (Ok => False, Err => Invalid_Packet_Id);
         end if;
         Ok_Res.Id := Natural (V);
         Pos := Pos + C;
      end;
      Idone := True;

      Ok_Res.Num_Fields := Layout'Length;
      for I in 1 .. Layout'Length loop
         declare
            K : constant Field_Kind := Layout (Layout'First + I - 1);
         begin
            case K is
               when K_Boolean =>
                  if Pos > Last then
                     return (Ok => False, Err => Truncated);
                  end if;
                  if Raw (Pos) = 16#00# then
                     Ok_Res.Fields (I) := (Kind => K_Boolean, B => False);
                  elsif Raw (Pos) = 16#01# then
                     Ok_Res.Fields (I) := (Kind => K_Boolean, B => True);
                  else
                     return (Ok => False, Err => Invalid_Field_Value);
                  end if;
                  Pos := Pos + 1;
               when K_Byte =>
                  if Pos > Last then
                     return (Ok => False, Err => Truncated);
                  end if;
                  Ok_Res.Fields (I) := (Kind => K_Byte, Y => Raw (Pos));
                  Pos := Pos + 1;
               when K_Int =>
                  if Remaining < 4 then
                     return (Ok => False, Err => Truncated);
                  end if;
                  declare
                     U : Interfaces.Unsigned_32 :=
                       Interfaces.Shift_Left
                         (Interfaces.Unsigned_32 (Raw (Pos)), 24)
                       or Interfaces.Shift_Left
                         (Interfaces.Unsigned_32 (Raw (Pos + 1)), 16)
                       or Interfaces.Shift_Left
                         (Interfaces.Unsigned_32 (Raw (Pos + 2)), 8)
                       or Interfaces.Unsigned_32 (Raw (Pos + 3));
                     Sv : Interfaces.Integer_32;
                  begin
                     if U >= 2 ** 31 then
                        Sv := Interfaces.Integer_32
                          (Interfaces.Integer_64 (U) - 2 ** 32);
                     else
                        Sv := Interfaces.Integer_32 (U);
                     end if;
                     Ok_Res.Fields (I) := (Kind => K_Int, I32 => Sv);
                  end;
                  Pos := Pos + 4;
               when K_Long =>
                  if Remaining < 8 then
                     return (Ok => False, Err => Truncated);
                  end if;
                  declare
                     U : Interfaces.Unsigned_64 :=
                       Interfaces.Shift_Left
                         (Interfaces.Unsigned_64 (Raw (Pos)), 56)
                       or Interfaces.Shift_Left
                         (Interfaces.Unsigned_64 (Raw (Pos + 1)), 48)
                       or Interfaces.Shift_Left
                         (Interfaces.Unsigned_64 (Raw (Pos + 2)), 40)
                       or Interfaces.Shift_Left
                         (Interfaces.Unsigned_64 (Raw (Pos + 3)), 32)
                       or Interfaces.Shift_Left
                         (Interfaces.Unsigned_64 (Raw (Pos + 4)), 24)
                       or Interfaces.Shift_Left
                         (Interfaces.Unsigned_64 (Raw (Pos + 5)), 16)
                       or Interfaces.Shift_Left
                         (Interfaces.Unsigned_64 (Raw (Pos + 6)), 8)
                       or Interfaces.Unsigned_64 (Raw (Pos + 7));
                     Sv : Interfaces.Integer_64;
                  begin
                     if U >= 2 ** 63 then
                        Sv := Interfaces.Integer_64 (U - 2 ** 63)
                          + Interfaces.Integer_64'First;
                     else
                        Sv := Interfaces.Integer_64 (U);
                     end if;
                     Ok_Res.Fields (I) := (Kind => K_Long, I64 => Sv);
                  end;
                  Pos := Pos + 8;
               when K_Varint =>
                  declare
                     V : Interfaces.Integer_32 := 0;
                     C : Natural := 0;
                     S : Varnum.Status_Type := Varnum.Truncated;
                  begin
                     if Pos > Last then
                        return (Ok => False, Err => Truncated);
                     end if;
                     Varnum.Decode (Raw, Pos, V, C, S);
                     case S is
                        when Varnum.Ok =>
                           null;
                        when Varnum.Truncated =>
                           return (Ok => False, Err => Truncated);
                        when Varnum.Overlong =>
                           return (Ok => False, Err => Overlong);
                        when Varnum.Buffer_Too_Small =>
                           return (Ok => False, Err => Truncated);
                     end case;
                     Ok_Res.Fields (I) := (Kind => K_Varint, I32 => V);
                     Pos := Pos + C;
                  end;
               when K_Varlong =>
                  declare
                     V : Interfaces.Integer_64 := 0;
                     C : Natural := 0;
                     S : Varnum.Status_Type := Varnum.Truncated;
                  begin
                     if Pos > Last then
                        return (Ok => False, Err => Truncated);
                     end if;
                     Varnum.Decode_Varlong (Raw, Pos, V, C, S);
                     case S is
                        when Varnum.Ok =>
                           null;
                        when Varnum.Truncated =>
                           return (Ok => False, Err => Truncated);
                        when Varnum.Overlong =>
                           return (Ok => False, Err => Overlong);
                        when Varnum.Buffer_Too_Small =>
                           return (Ok => False, Err => Truncated);
                     end case;
                     Ok_Res.Fields (I) := (Kind => K_Varlong, I64 => V);
                     Pos := Pos + C;
                  end;
               when K_String =>
                  declare
                     L32 : Interfaces.Integer_32 := 0;
                     C   : Natural := 0;
                     S   : Varnum.Status_Type := Varnum.Truncated;
                  begin
                     if Pos > Last then
                        return (Ok => False, Err => Truncated);
                     end if;
                     Varnum.Decode (Raw, Pos, L32, C, S);
                     case S is
                        when Varnum.Ok =>
                           null;
                        when Varnum.Truncated =>
                           return (Ok => False, Err => Truncated);
                        when Varnum.Overlong =>
                           return (Ok => False, Err => Overlong);
                        when Varnum.Buffer_Too_Small =>
                           return (Ok => False, Err => Truncated);
                     end case;
                     if L32 < 0 then
                        return (Ok => False, Err => String_Too_Long);
                     end if;
                     if L32 > Interfaces.Integer_32 (String_Max) then
                        return (Ok => False, Err => String_Too_Long);
                     end if;
                     Pos := Pos + C;
                     declare
                        L : constant Natural := Natural (L32);
                     begin
                        if L > Remaining then
                           return (Ok => False, Err => Truncated);
                        end if;
                        Ok_Res.Fields (I) :=
                          (Kind => K_String, S_Len => L,
                           S_Data => (others => ' '));
                        for J in 1 .. L loop
                           Ok_Res.Fields (I).S_Data (J) :=
                             Character'Val (Natural (Raw (Pos + J - 1)));
                        end loop;
                        Pos := Pos + L;
                     end;
                  end;
            end case;
         end;
      end loop;

      if Pos /= Last + 1 then
         return (Ok => False, Err => Trailing_Bytes);
      end if;
      return Ok_Res;
   exception
      when others =>
         return (Ok => False, Err => Invalid_Field_Value);
   end Decode;

   function Decode_Login_Hello (Payload : Octets) return Login_Hello is
      Result : Login_Hello;
      Name   : Buffer.String_Decode;
   begin
      if Payload'Length = 0 then
         Result.Status := Rejected;
         return Result;
      end if;
      Name := Buffer.Decode_String (Payload, Payload'First, 16);
      if Name.Status /= Ok or else Name.Length = 0 then
         Result.Status := Rejected;
         return Result;
      end if;
      if Name.Next > Payload'Last or else Payload'Last - Name.Next + 1 /= 16 then
         Result.Status := Rejected;
         return Result;
      end if;
      Result.Status := Ok;
      Result.Name_Len := Name.Length;
      Result.Name (1 .. Name.Length) := Name.Text (1 .. Name.Length);
      for I in 1 .. 16 loop
         Result.Uuid (I) := Payload (Name.Next + I - 1);
      end loop;
      return Result;
   end Decode_Login_Hello;
end Adacraft.Protocol.Packets;
