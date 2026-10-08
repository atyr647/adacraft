with Ada.Streams;
with Ada.Unchecked_Conversion;
with Interfaces;
with Adacraft.Protocol.Frame;
with Adacraft.Protocol.Varnum;

package body Adacraft.Protocol.Packet_Encoder is

   use type Adacraft.Protocol.Varnum.Status_Type;
   use type Ada.Streams.Stream_Element;
   use type Ada.Streams.Stream_Element_Offset;
   use type Interfaces.Unsigned_32;
   use type Interfaces.Unsigned_64;

   function To_U32 is new Ada.Unchecked_Conversion
     (Interfaces.Integer_32, Interfaces.Unsigned_32);
   function To_U64 is new Ada.Unchecked_Conversion
     (Interfaces.Integer_64, Interfaces.Unsigned_64);

   procedure Append_Element (E : in out Encoder_Type; V : Byte) is
   begin
      if E.Failed or else not E.Started then
         E.Failed := True;
         return;
      end if;
      if E.Count >= E.Capacity
        or else E.Count >= Adacraft.Protocol.Frame.Max_Frame_Body_Length
      then
         E.Failed := True;
         return;
      end if;
      E.Storage (Ada.Streams.Stream_Element_Offset (E.Count + 1)) := V;
      E.Count := E.Count + 1;
   end Append_Element;

   procedure Append_Raw
     (E : in out Encoder_Type; Data : Ada.Streams.Stream_Element_Array) is
      Data_Len : constant Natural := Natural (Data'Length);
   begin
      if E.Failed or else not E.Started then
         E.Failed := True;
         return;
      end if;
      if Data_Len = 0 then
         return;
      end if;
      if E.Count + Data_Len > E.Capacity
        or else E.Count + Data_Len >
          Adacraft.Protocol.Frame.Max_Frame_Body_Length
      then
         E.Failed := True;
         return;
      end if;
      for I in 1 .. Data_Len loop
         E.Storage (Ada.Streams.Stream_Element_Offset (E.Count + I)) :=
           Data (Data'First + Ada.Streams.Stream_Element_Offset (I) - 1);
      end loop;
      E.Count := E.Count + Data_Len;
   end Append_Raw;

   procedure Start_Packet (E : in out Encoder_Type; Packet_Id : Natural) is
      Buf     : Adacraft.Protocol.Octets (1 .. 5) := (others => 0);
      Written : Natural := 0;
      Status  : Adacraft.Protocol.Varnum.Status_Type;
      Value   : Interfaces.Integer_32;
   begin
      E.Count := 0;
      E.Failed := False;
      E.Started := True;
      E.Storage := (others => 0);
      if Packet_Id > Natural (Interfaces.Integer_32'Last) then
         E.Failed := True;
         return;
      end if;
      Value := Interfaces.Integer_32 (Packet_Id);
      Adacraft.Protocol.Varnum.Encode (Value, Buf, Buf'First, Written, Status);
      if Status /= Adacraft.Protocol.Varnum.Ok then
         E.Failed := True;
         return;
      end if;
      if Written > E.Capacity then
         E.Failed := True;
         return;
      end if;
      for I in 1 .. Written loop
         E.Storage (Ada.Streams.Stream_Element_Offset (I)) :=
           Ada.Streams.Stream_Element (Buf (I));
      end loop;
      E.Count := Written;
   end Start_Packet;

   procedure Write_Boolean (E : in out Encoder_Type; V : Boolean) is
   begin
      if V then
         Append_Element (E, 16#01#);
      else
         Append_Element (E, 16#00#);
      end if;
   end Write_Boolean;

   procedure Write_Byte (E : in out Encoder_Type; V : Byte) is
   begin
      Append_Element (E, V);
   end Write_Byte;

   procedure Write_Int (E : in out Encoder_Type; V : Interfaces.Integer_32) is
      U : constant Interfaces.Unsigned_32 := To_U32 (V);
      B : Ada.Streams.Stream_Element_Array (1 .. 4);
   begin
      B (1) := Ada.Streams.Stream_Element
        (Interfaces.Shift_Right (U, 24) and 16#FF#);
      B (2) := Ada.Streams.Stream_Element
        (Interfaces.Shift_Right (U, 16) and 16#FF#);
      B (3) := Ada.Streams.Stream_Element
        (Interfaces.Shift_Right (U, 8) and 16#FF#);
      B (4) := Ada.Streams.Stream_Element (U and 16#FF#);
      Append_Raw (E, B);
   end Write_Int;

   procedure Write_Long (E : in out Encoder_Type; V : Interfaces.Integer_64) is
      U : constant Interfaces.Unsigned_64 := To_U64 (V);
      B : Ada.Streams.Stream_Element_Array (1 .. 8);
   begin
      B (1) := Ada.Streams.Stream_Element
        (Interfaces.Shift_Right (U, 56) and 16#FF#);
      B (2) := Ada.Streams.Stream_Element
        (Interfaces.Shift_Right (U, 48) and 16#FF#);
      B (3) := Ada.Streams.Stream_Element
        (Interfaces.Shift_Right (U, 40) and 16#FF#);
      B (4) := Ada.Streams.Stream_Element
        (Interfaces.Shift_Right (U, 32) and 16#FF#);
      B (5) := Ada.Streams.Stream_Element
        (Interfaces.Shift_Right (U, 24) and 16#FF#);
      B (6) := Ada.Streams.Stream_Element
        (Interfaces.Shift_Right (U, 16) and 16#FF#);
      B (7) := Ada.Streams.Stream_Element
        (Interfaces.Shift_Right (U, 8) and 16#FF#);
      B (8) := Ada.Streams.Stream_Element (U and 16#FF#);
      Append_Raw (E, B);
   end Write_Long;

   procedure Get_Framed
     (E      : in out Encoder_Type;
      Output : out Ada.Streams.Stream_Element_Array;
      Last   : out Ada.Streams.Stream_Element_Offset)
   is
      Prefix     : Adacraft.Protocol.Frame.Prefix_Buffer;
      Prefix_Len : Ada.Streams.Stream_Element_Offset;
      Need       : Ada.Streams.Stream_Element_Offset;
   begin
      if E.Failed
        or else not E.Started
        or else E.Count > Adacraft.Protocol.Frame.Max_Frame_Body_Length
      then
         E.Failed := True;
         if Output'First > Ada.Streams.Stream_Element_Offset'First then
            Last := Output'First - 1;
         else
            Last := Output'First;
         end if;
         return;
      end if;
      Adacraft.Protocol.Frame.Write_Length_Prefix
        (Adacraft.Protocol.Frame.Frame_Body_Length (E.Count),
         Prefix, Prefix_Len);
      Need := Prefix_Len + Ada.Streams.Stream_Element_Offset (E.Count);
      if Output'Length < Need then
         E.Failed := True;
         if Output'First > Ada.Streams.Stream_Element_Offset'First then
            Last := Output'First - 1;
         else
            Last := Output'First;
         end if;
         return;
      end if;
      for I in 1 .. Prefix_Len loop
         Output (Output'First + I - 1) :=
           Prefix (Positive (I));
      end loop;
      for I in 1 .. E.Count loop
         Output (Output'First + Prefix_Len +
                 Ada.Streams.Stream_Element_Offset (I) - 1) :=
           E.Storage (Ada.Streams.Stream_Element_Offset (I));
      end loop;
      Last := Output'First + Need - 1;
   end Get_Framed;

   function From_U32 (U : Interfaces.Unsigned_32) return Interfaces.Integer_32 is
      Half : constant Interfaces.Unsigned_32 := 2 ** 31;
   begin
      if U < Half then
         return Interfaces.Integer_32 (U);
      else
         --  Map [2**31 .. 2**32-1] onto [-2**31 .. -1] without overflow.
         return Interfaces.Integer_32 (U - Half) + Interfaces.Integer_32'First;
      end if;
   end From_U32;

   function From_U64 (U : Interfaces.Unsigned_64) return Interfaces.Integer_64 is
      Half : constant Interfaces.Unsigned_64 := 2 ** 63;
   begin
      if U < Half then
         return Interfaces.Integer_64 (U);
      else
         return Interfaces.Integer_64 (U - Half) + Interfaces.Integer_64'First;
      end if;
   end From_U64;

   procedure Decode
     (Body   : in Body_Bytes;
      Layout : in Layout_Array;
      Result : out Decode_Result)
   is
      Len      : constant Natural := Natural (Body'Length);
      Pos      : Natural := 0;
      Id_Buf   : Adacraft.Protocol.Octets (1 .. 5) := (others => 0);
      Id_Take  : Natural;
      Id_Val   : Interfaces.Integer_32 := 0;
      Consumed : Natural := 0;
      V_Status : Adacraft.Protocol.Varnum.Status_Type;
      Values   : Bounded_Values;
      Count    : Field_Count := 0;
      First    : Natural;
   begin
      --  Default to Truncated so every path assigns Result fully.
      Result := (Status => Truncated, Error_Offset => 0);

      if Layout'Length > Max_Decoded_Fields then
         Result := (Status => Invalid_Length, Error_Offset => 0);
         return;
      end if;

      if Len = 0
        or else Len > Adacraft.Protocol.Frame.Max_Frame_Body_Length
      then
         Result := (Status => Truncated, Error_Offset => 0);
         return;
      end if;

      First := Body'First;

      --  Packet ID via Varnum on a bounded 5-byte window (no local codec,
      --  no allocation from untrusted lengths).
      Id_Take := Natural'Min (Len, 5);
      for I in 1 .. Id_Take loop
         Id_Buf (I) :=
           Adacraft.Protocol.Octet (Body (First + I - 1));
      end loop;
      Adacraft.Protocol.Varnum.Decode
        (Id_Buf (1 .. Id_Take), 1, Id_Val, Consumed, V_Status);
      case V_Status is
         when Adacraft.Protocol.Varnum.Ok =>
            null;
         when Adacraft.Protocol.Varnum.Overlong =>
            Result := (Status => Overlong_Varint, Error_Offset => 0);
            return;
         when Adacraft.Protocol.Varnum.Truncated
            | Adacraft.Protocol.Varnum.Buffer_Too_Small =>
            Result := (Status => Truncated, Error_Offset => 0);
            return;
      end case;

      if Id_Val < 0 then
         Result := (Status => Id_Out_Of_Range, Error_Offset => 0);
         return;
      end if;

      Pos := Consumed;
      Count := 0;

      for Lx in Layout'Range loop
         pragma Loop_Invariant (Pos <= Len);
         pragma Loop_Invariant (Count <= Field_Count'Last);
         declare
            K : constant Field_Kind := Layout (Lx);
         begin
            case K is
               when Field_Boolean =>
                  if Pos >= Len then
                     Result := (Status => Truncated, Error_Offset => Pos);
                     return;
                  end if;
                  declare
                     B : constant Byte := Body (First + Pos);
                  begin
                     Pos := Pos + 1;
                     Count := Count + 1;
                     if B = 16#00# then
                        Values (Count) :=
                          (Kind => Field_Boolean, Bool_Val => False);
                     elsif B = 16#01# then
                        Values (Count) :=
                          (Kind => Field_Boolean, Bool_Val => True);
                     else
                        Result :=
                          (Status => Invalid_Length,
                           Error_Offset => Pos - 1);
                        return;
                     end if;
                  end;
               when Field_Byte =>
                  if Pos >= Len then
                     Result := (Status => Truncated, Error_Offset => Pos);
                     return;
                  end if;
                  Count := Count + 1;
                  Values (Count) :=
                    (Kind => Field_Byte, Byte_Val => Body (First + Pos));
                  Pos := Pos + 1;
               when Field_Int =>
                  if Pos + 4 > Len then
                     Result := (Status => Truncated, Error_Offset => Pos);
                     return;
                  end if;
                  declare
                     U : Interfaces.Unsigned_32 := 0;
                  begin
                     for J in 0 .. 3 loop
                        U := Interfaces.Shift_Left (U, 8)
                          or Interfaces.Unsigned_32
                               (Body (First + Pos + J));
                     end loop;
                     Pos := Pos + 4;
                     Count := Count + 1;
                     Values (Count) :=
                       (Kind => Field_Int, Int_Val => From_U32 (U));
                  end;
               when Field_Long =>
                  if Pos + 8 > Len then
                     Result := (Status => Truncated, Error_Offset => Pos);
                     return;
                  end if;
                  declare
                     U : Interfaces.Unsigned_64 := 0;
                  begin
                     for J in 0 .. 7 loop
                        U := Interfaces.Shift_Left (U, 8)
                          or Interfaces.Unsigned_64
                               (Body (First + Pos + J));
                     end loop;
                     Pos := Pos + 8;
                     Count := Count + 1;
                     Values (Count) :=
                       (Kind => Field_Long, Long_Val => From_U64 (U));
                  end;
            end case;
         end;
      end loop;

      if Pos /= Len then
         Result := (Status => Trailing_Bytes, Error_Offset => Pos);
         return;
      end if;

      Result := (Status => Ok,
                 Packet_Id => Natural (Id_Val),
                 Count => Count,
                 Values => Values);
   end Decode;

   procedure Get_Body
     (E     : in Encoder_Type;
      Data  : out Ada.Streams.Stream_Element_Array;
      Last  : out Ada.Streams.Stream_Element_Offset)
   is
      N : constant Natural := Natural'Min (E.Count, Natural (Data'Length));
   begin
      if N = 0 then
         if Data'First > Ada.Streams.Stream_Element_Offset'First then
            Last := Data'First - 1;
         else
            Last := Data'First;
         end if;
         return;
      end if;
      for I in 1 .. N loop
         Data (Data'First + Ada.Streams.Stream_Element_Offset (I) - 1) :=
           E.Storage (Ada.Streams.Stream_Element_Offset (I));
      end loop;
      Last := Data'First + Ada.Streams.Stream_Element_Offset (N) - 1;
   end Get_Body;

   function Has_Failed (E : Encoder_Type) return Boolean is
   begin
      return E.Failed;
   end Has_Failed;

   function Length (E : Encoder_Type) return Natural is
   begin
      return E.Count;
   end Length;

end Adacraft.Protocol.Packet_Encoder;
