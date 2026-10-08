with Interfaces;
with Adacraft.Protocol.Varnum;

package body Adacraft.Protocol.Packet_Decoder is

   procedure Decode
     (Input     : in  Octets;
      Layout    : in  Field_Layout;
      Packet_Id : out Interfaces.Integer_32;
      Fields    : out Decoded_Fields;
      Status    : out Decode_Status)
   is
      Pos : Integer := Input'First;

      function Remaining return Natural is
      begin
         if Pos > Input'Last then
            return 0;
         else
            return Natural (Input'Last - Pos + 1);
         end if;
      end Remaining;

   begin
      --  Init all out params on entry so early reject leaves defined values.
      Packet_Id := 0;
      Fields.Length := 0;
      Fields.Values :=
        (others => (Kind => Kind_VarInt, VarInt_Value => 0));
      Status := Rejected;

      --  Trailing-bytes choice: trailing bytes after the last layout field
      --  are ignored (accepted as Success). Strictness decision belongs
      --  to #248; this item only requires reject paths exist.
      begin
         if Layout.Length > Max_Fields then
            Status := Rejected;
            return;
         end if;

         if Input'Length = 0 then
            Status := Rejected;
            return;
         end if;

         Pos := Input'First;

         --  Step 1: packet ID via shipped Varnum VarInt decode only.
         declare
            V : Interfaces.Integer_32 := 0;
            C : Natural := 0;
            S : Varnum.Status_Type := Varnum.Truncated;
         begin
            Varnum.Decode (Input, Pos, V, C, S);
            if S /= Varnum.Ok then
               Status := Rejected;
               return;
            end if;
            Packet_Id := V;
            Pos := Pos + C;
         end;

         --  Step 2: fields in layout order.
         for I in 1 .. Layout.Length loop
            declare
               K : constant Field_Kind := Layout.Kinds (I);
            begin
               case K is
                  when Kind_VarInt =>
                     declare
                        V : Interfaces.Integer_32 := 0;
                        C : Natural := 0;
                        S : Varnum.Status_Type := Varnum.Truncated;
                     begin
                        if Pos > Input'Last then
                           Status := Rejected;
                           return;
                        end if;
                        Varnum.Decode (Input, Pos, V, C, S);
                        if S /= Varnum.Ok then
                           Status := Rejected;
                           return;
                        end if;
                        Pos := Pos + C;
                        Fields.Values (I) :=
                          (Kind => Kind_VarInt, VarInt_Value => V);
                     end;

                  when Kind_VarLong =>
                     declare
                        V : Interfaces.Integer_64 := 0;
                        C : Natural := 0;
                        S : Varnum.Status_Type := Varnum.Truncated;
                     begin
                        if Pos > Input'Last then
                           Status := Rejected;
                           return;
                        end if;
                        Varnum.Decode_Varlong (Input, Pos, V, C, S);
                        if S /= Varnum.Ok then
                           Status := Rejected;
                           return;
                        end if;
                        Pos := Pos + C;
                        Fields.Values (I) :=
                          (Kind => Kind_VarLong, VarLong_Value => V);
                     end;

                  when Kind_Byte =>
                     if Remaining < 1 then
                        Status := Rejected;
                        return;
                     end if;
                     declare
                        B : constant Interfaces.Unsigned_8 := Input (Pos);
                     begin
                        if B <= 16#7F# then
                           Fields.Values (I) :=
                             (Kind => Kind_Byte,
                              Byte_Value => Interfaces.Integer_8 (B));
                        else
                           Fields.Values (I) :=
                             (Kind => Kind_Byte,
                              Byte_Value =>
                                Interfaces.Integer_8
                                  (Integer (B) - 256));
                        end if;
                     end;
                     Pos := Pos + 1;

                  when Kind_Short =>
                     if Remaining < 2 then
                        Status := Rejected;
                        return;
                     end if;
                     declare
                        B1 : constant Natural := Natural (Input (Pos));
                        B2 : constant Natural := Natural (Input (Pos + 1));
                        U  : constant Interfaces.Unsigned_16 :=
                          Interfaces.Unsigned_16 (B1 * 256 + B2);
                     begin
                        if U <= 16#7FFF# then
                           Fields.Values (I) :=
                             (Kind => Kind_Short,
                              Short_Value => Interfaces.Integer_16 (U));
                        else
                           Fields.Values (I) :=
                             (Kind => Kind_Short,
                              Short_Value =>
                                Interfaces.Integer_16
                                  (Integer (U) - 65_536));
                        end if;
                     end;
                     Pos := Pos + 2;

                  when Kind_Int =>
                     if Remaining < 4 then
                        Status := Rejected;
                        return;
                     end if;
                     declare
                        U : Interfaces.Unsigned_32 := 0;
                     begin
                        for J in 0 .. 3 loop
                           U :=
                             U * 256 +
                             Interfaces.Unsigned_32 (Input (Pos + J));
                        end loop;
                        if U <= Interfaces.Unsigned_32
                          (Interfaces.Integer_32'Last)
                        then
                           Fields.Values (I) :=
                             (Kind => Kind_Int,
                              Int_Value => Interfaces.Integer_32 (U));
                        else
                           declare
                              K2 : constant Interfaces.Unsigned_32 :=
                                U - 16#8000_0000#;
                           begin
                              Fields.Values (I) :=
                                (Kind => Kind_Int,
                                 Int_Value =>
                                   Interfaces.Integer_32'First +
                                   Interfaces.Integer_32 (K2));
                           end;
                        end if;
                     end;
                     Pos := Pos + 4;

                  when Kind_Long =>
                     if Remaining < 8 then
                        Status := Rejected;
                        return;
                     end if;
                     declare
                        U : Interfaces.Unsigned_64 := 0;
                     begin
                        for J in 0 .. 7 loop
                           U :=
                             U * 256 +
                             Interfaces.Unsigned_64 (Input (Pos + J));
                        end loop;
                        if U <= Interfaces.Unsigned_64
                          (Interfaces.Integer_64'Last)
                        then
                           Fields.Values (I) :=
                             (Kind => Kind_Long,
                              Long_Value => Interfaces.Integer_64 (U));
                        else
                           declare
                              K2 : constant Interfaces.Unsigned_64 :=
                                U - 16#8000_0000_0000_0000#;
                           begin
                              Fields.Values (I) :=
                                (Kind => Kind_Long,
                                 Long_Value =>
                                   Interfaces.Integer_64'First +
                                   Interfaces.Integer_64 (K2));
                           end;
                        end if;
                     end;
                     Pos := Pos + 8;

                  when Kind_String =>
                     declare
                        L : Interfaces.Integer_32 := 0;
                        C : Natural := 0;
                        S : Varnum.Status_Type := Varnum.Truncated;
                     begin
                        if Pos > Input'Last then
                           Status := Rejected;
                           return;
                        end if;
                        Varnum.Decode (Input, Pos, L, C, S);
                        if S /= Varnum.Ok then
                           Status := Rejected;
                           return;
                        end if;
                        Pos := Pos + C;
                        if L < 0
                          or else L > Interfaces.Integer_32 (String_Max)
                        then
                           Status := Rejected;
                           return;
                        end if;
                        if Natural (L) > Remaining then
                           Status := Rejected;
                           return;
                        end if;
                        if L = 0 then
                           Fields.Values (I) :=
                             (Kind => Kind_String,
                              String_Value =>
                                Bounded_Strings.Null_Bounded_String);
                        else
                           declare
                              N   : constant Natural := Natural (L);
                              Tmp : String (1 .. N);
                           begin
                              for J in 1 .. N loop
                                 Tmp (J) :=
                                   Character'Val
                                     (Natural (Input (Pos + J - 1)));
                              end loop;
                              Fields.Values (I) :=
                                (Kind => Kind_String,
                                 String_Value =>
                                   Bounded_Strings.To_Bounded_String (Tmp));
                           end;
                           Pos := Pos + Natural (L);
                        end if;
                     end;

                  when Kind_Boolean =>
                     if Remaining < 1 then
                        Status := Rejected;
                        return;
                     end if;
                     if Input (Pos) = 16#00# then
                        Fields.Values (I) :=
                          (Kind => Kind_Boolean, Boolean_Value => False);
                     elsif Input (Pos) = 16#01# then
                        Fields.Values (I) :=
                          (Kind => Kind_Boolean, Boolean_Value => True);
                     else
                        Status := Rejected;
                        return;
                     end if;
                     Pos := Pos + 1;
               end case;
            end;
         end loop;

         Fields.Length := Layout.Length;
         Status := Success;
      exception
         when others =>
            Packet_Id := 0;
            Fields.Length := 0;
            Fields.Values :=
              (others => (Kind => Kind_VarInt, VarInt_Value => 0));
            Status := Rejected;
      end;
   exception
      when others =>
         Packet_Id := 0;
         Fields.Length := 0;
         Fields.Values :=
           (others => (Kind => Kind_VarInt, VarInt_Value => 0));
         Status := Rejected;
   end Decode;

end Adacraft.Protocol.Packet_Decoder;
