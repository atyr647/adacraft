with Ada.Streams;
with Ada.Unchecked_Conversion;
with Interfaces;
with Adacraft.Protocol.Varnum;

package body Adacraft.Protocol.Packet_Decoder is

   use type Ada.Streams.Stream_Element;
   use type Ada.Streams.Stream_Element_Offset;
   use type Interfaces.Integer_32;
   use type Interfaces.Integer_64;
   use type Interfaces.Unsigned_32;
   use type Interfaces.Unsigned_64;

   function To_I64 is new Ada.Unchecked_Conversion
     (Interfaces.Unsigned_64, Interfaces.Integer_64);

   function To_Octets (Raw : Body_Array) return Octets is
      R : Octets (1 .. Raw'Length);
   begin
      if Raw'Length = 0 then
         return Octets'(1 .. 0 => 0);
      end if;
      for J in 0 .. Raw'Length - 1 loop
         R (1 + J) :=
           Octet (Raw (Raw'First + Ada.Streams.Stream_Element_Offset (J)));
      end loop;
      return R;
   end To_Octets;

   function Decode
     (Raw    : Body_Array;
      Layout : Layout_Array) return Decode_Result
   is
      Fail : Decode_Result (Ok => False);
      Good : Decode_Result (Ok => True);
      Pos  : Ada.Streams.Stream_Element_Offset;
      Oct  : Octets := To_Octets (Raw);
      Idx  : Integer := 1;
   begin
      if Raw'Length = 0 then
         Fail.Reason := Empty_Body;
         return Fail;
      end if;
      if Layout'Length > Max_Fields then
         Fail.Reason := Truncated;
         return Fail;
      end if;

      declare
         Value    : Interfaces.Integer_32 := 0;
         Consumed : Natural := 0;
         Status   : Varnum.Status_Type;
      begin
         Varnum.Decode (Oct, 1, Value, Consumed, Status);
         case Status is
            when Varnum.Ok =>
               null;
            when Varnum.Truncated =>
               Fail.Reason := Truncated;
               return Fail;
            when Varnum.Overlong =>
               Fail.Reason := Overlong_Varint;
               return Fail;
            when Varnum.Buffer_Too_Small =>
               Fail.Reason := Truncated;
               return Fail;
         end case;
         if Value < 0
           or else Value > Interfaces.Integer_32 (Packet_Id_Type'Last)
         then
            Fail.Reason := Id_Out_Of_Range;
            return Fail;
         end if;
         Good.Id := Natural (Value);
         Idx := 1 + Consumed;
      end;

      Pos := Raw'First + Ada.Streams.Stream_Element_Offset (Idx - 1);
      Good.Count := Layout'Length;

      if Layout'Length > 0 then
         for I in Layout'Range loop
            declare
               K       : constant Field_Kind := Layout (I);
               Out_Pos : constant Positive := (I - Layout'First) + 1;
            begin
               case K is
                  when FK_Boolean =>
                     if Pos > Raw'Last then
                        Fail.Reason := Truncated;
                        return Fail;
                     end if;
                     if Raw (Pos) = 0 then
                        Good.Fields (Out_Pos) :=
                          (Kind => FK_Boolean, B => False);
                     elsif Raw (Pos) = 1 then
                        Good.Fields (Out_Pos) :=
                          (Kind => FK_Boolean, B => True);
                     else
                        Fail.Reason := Truncated;
                        return Fail;
                     end if;
                     Pos := Pos + 1;
                  when FK_Byte =>
                     if Pos > Raw'Last then
                        Fail.Reason := Truncated;
                        return Fail;
                     end if;
                     Good.Fields (Out_Pos) :=
                       (Kind => FK_Byte, U8 => Raw (Pos));
                     Pos := Pos + 1;
                  when FK_Int =>
                     if Pos > Raw'Last then
                        Fail.Reason := Truncated;
                        return Fail;
                     end if;
                     if Raw'Last - Pos + 1 < 4 then
                        Fail.Reason := Truncated;
                        return Fail;
                     end if;
                     declare
                        B0 : constant Interfaces.Unsigned_32 :=
                          Interfaces.Unsigned_32 (Raw (Pos));
                        B1 : constant Interfaces.Unsigned_32 :=
                          Interfaces.Unsigned_32 (Raw (Pos + 1));
                        B2 : constant Interfaces.Unsigned_32 :=
                          Interfaces.Unsigned_32 (Raw (Pos + 2));
                        B3 : constant Interfaces.Unsigned_32 :=
                          Interfaces.Unsigned_32 (Raw (Pos + 3));
                        U : constant Interfaces.Unsigned_32 :=
                          Interfaces.Shift_Left (B0, 24)
                          or Interfaces.Shift_Left (B1, 16)
                          or Interfaces.Shift_Left (B2, 8)
                          or B3;
                        S : Interfaces.Integer_32;
                     begin
                        if U >= 2 ** 31 then
                           S := Interfaces.Integer_32
                             (Interfaces.Integer_64 (U) - 2 ** 32);
                        else
                           S := Interfaces.Integer_32 (U);
                        end if;
                        Good.Fields (Out_Pos) :=
                          (Kind => FK_Int, I32 => S);
                     end;
                     Pos := Pos + 4;
                  when FK_Long =>
                     if Pos > Raw'Last then
                        Fail.Reason := Truncated;
                        return Fail;
                     end if;
                     if Raw'Last - Pos + 1 < 8 then
                        Fail.Reason := Truncated;
                        return Fail;
                     end if;
                     declare
                        U : Interfaces.Unsigned_64 := 0;
                     begin
                        for K2 in 0 .. 7 loop
                           declare
                              P : constant Interfaces.Unsigned_64 :=
                                Interfaces.Unsigned_64
                                  (Raw (Pos + SEO (K2)));
                           begin
                              U := U or Interfaces.Shift_Left
                                (P, (7 - K2) * 8);
                           end;
                        end loop;
                        declare
                           S : constant Interfaces.Integer_64 := To_I64 (U);
                        begin
                           Good.Fields (Out_Pos) :=
                             (Kind => FK_Long, I64 => S);
                        end;
                     end;
                     Pos := Pos + 8;
                  when FK_Varint =>
                     declare
                        Start    : constant Integer :=
                          Integer (Pos - Raw'First) + 1;
                        Value    : Interfaces.Integer_32 := 0;
                        Consumed : Natural := 0;
                        Status   : Varnum.Status_Type;
                     begin
                        if Pos > Raw'Last then
                           Fail.Reason := Truncated;
                           return Fail;
                        end if;
                        Varnum.Decode
                          (Oct, Start, Value, Consumed, Status);
                        case Status is
                           when Varnum.Ok =>
                              Good.Fields (Out_Pos) :=
                                (Kind => FK_Varint, V32 => Value);
                              Pos := Pos + SEO (Consumed);
                              Idx := Start + Consumed;
                           when Varnum.Truncated =>
                              Fail.Reason := Truncated;
                              return Fail;
                           when Varnum.Overlong =>
                              Fail.Reason := Overlong_Varint;
                              return Fail;
                           when Varnum.Buffer_Too_Small =>
                              Fail.Reason := Truncated;
                              return Fail;
                        end case;
                     end;
                  when FK_Varlong =>
                     declare
                        Start    : constant Integer :=
                          Integer (Pos - Raw'First) + 1;
                        Value    : Interfaces.Integer_64 := 0;
                        Consumed : Natural := 0;
                        Status   : Varnum.Status_Type;
                     begin
                        if Pos > Raw'Last then
                           Fail.Reason := Truncated;
                           return Fail;
                        end if;
                        Varnum.Decode_Varlong
                          (Oct, Start, Value, Consumed, Status);
                        case Status is
                           when Varnum.Ok =>
                              Good.Fields (Out_Pos) :=
                                (Kind => FK_Varlong, V64 => Value);
                              Pos := Pos + SEO (Consumed);
                              Idx := Start + Consumed;
                           when Varnum.Truncated =>
                              Fail.Reason := Truncated;
                              return Fail;
                           when Varnum.Overlong =>
                              Fail.Reason := Overlong_Varlong;
                              return Fail;
                           when Varnum.Buffer_Too_Small =>
                              Fail.Reason := Truncated;
                              return Fail;
                        end case;
                     end;
               end case;
            end;
         end loop;
      end if;

      if Pos /= Raw'Last + 1 then
         Fail.Reason := Trailing_Bytes;
         return Fail;
      end if;

      return Good;
   exception
      when others =>
         Fail.Reason := Truncated;
         return Fail;
   end Decode;

end Adacraft.Protocol.Packet_Decoder;
