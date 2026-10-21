with Interfaces;
with Adacraft.Protocol.Configuration_Data;
with Adacraft.Protocol.Varnum;

package body Adacraft.Protocol.Configuration_Exchange is

   use type Interfaces.Unsigned_8;
   use type Interfaces.Unsigned_32;

   package CD renames Adacraft.Protocol.Configuration_Data;

   function From_Hex (Hex : String) return Octets is
      function Digit (C : Character) return Octet is
        (case C is
            when '0' .. '9' => Character'Pos (C) - Character'Pos ('0'),
            when 'A' .. 'F' => Character'Pos (C) - Character'Pos ('A') + 10,
            when 'a' .. 'f' => Character'Pos (C) - Character'Pos ('a') + 10,
            when others     => raise Constraint_Error with "not hex");
      Result : Octets (1 .. Hex'Length / 2);
   begin
      for I in Result'Range loop
         Result (I) := Digit (Hex (Hex'First + 2 * (I - 1))) * 16
           + Digit (Hex (Hex'First + 2 * (I - 1) + 1));
      end loop;
      return Result;
   end From_Hex;

   function Names_Core_Pack (Payload : Octets) return Boolean is
      use type Adacraft.Protocol.Status_Kind;
      Pos   : Positive := Payload'First;
      Found : Boolean := False;
      Count : Natural;

      --  The next string, its bounds in Payload; False when it runs past
      --  the end.
      procedure Next_String (First, Last : out Natural; Ok : out Boolean) is
         R : Adacraft.Protocol.Varnum.Varint_Result;
      begin
         First := 0;
         Last := 0;
         Ok := False;
         if Pos > Payload'Last then
            return;
         end if;
         R := Adacraft.Protocol.Varnum.Decode_Varint (Payload, Pos);
         if R.Status /= Adacraft.Protocol.Ok or else R.Value > 32_767
           or else R.Next + Natural (R.Value) - 1 > Payload'Last
         then
            return;
         end if;
         First := R.Next;
         Last := R.Next + Natural (R.Value) - 1;
         Pos := Last + 1;
         Ok := True;
      end Next_String;

      function Text (First, Last : Natural) return String is
         S : String (1 .. Last - First + 1);
      begin
         for I in S'Range loop
            S (I) := Character'Val (Payload (First + I - 1));
         end loop;
         return S;
      end Text;
   begin
      if Payload'Length = 0 then
         return False;
      end if;
      declare
         R : constant Adacraft.Protocol.Varnum.Varint_Result :=
           Adacraft.Protocol.Varnum.Decode_Varint (Payload, Pos);
      begin
         if R.Status /= Adacraft.Protocol.Ok or else R.Value > Max_Known_Packs then
            return False;
         end if;
         Count := Natural (R.Value);
         Pos := R.Next;
      end;
      for Each in 1 .. Count loop
         declare
            NF, NL, IdF, IdL, VF, VL : Natural;
            Ok1, Ok2, Ok3 : Boolean;
         begin
            Next_String (NF, NL, Ok1);
            if not Ok1 then
               return False;
            end if;
            Next_String (IdF, IdL, Ok2);
            if not Ok2 then
               return False;
            end if;
            Next_String (VF, VL, Ok3);
            if not Ok3 then
               return False;
            end if;
            if Text (NF, NL) = CD.Known_Pack_Namespace and then Text (IdF, IdL) = CD.Known_Pack_Id
              and then Text (VF, VL) = CD.Known_Pack_Version
            then
               Found := True;
            end if;
         end;
      end loop;
      return Found and then Pos = Payload'Last + 1;
   end Names_Core_Pack;

end Adacraft.Protocol.Configuration_Exchange;
