with Interfaces;

package body Adacraft.Auth.MD5 is

   use type Interfaces.Unsigned_64;
   use type Interfaces.Unsigned_32;
   use type Interfaces.Unsigned_8;

   type Word is mod 2 ** 32;
   type Block is array (0 .. 15) of Word;

   K : constant array (0 .. 63) of Word :=
     [16#D76AA478#, 16#E8C7B756#, 16#242070DB#, 16#C1BDCEEE#,
      16#F57C0FAF#, 16#4787C62A#, 16#A8304613#, 16#FD469501#,
      16#698098D8#, 16#8B44F7AF#, 16#FFFF5BB1#, 16#895CD7BE#,
      16#6B901122#, 16#FD987193#, 16#A679438E#, 16#49B40821#,
      16#F61E2562#, 16#C040B340#, 16#265E5A51#, 16#E9B6C7AA#,
      16#D62F105D#, 16#02441453#, 16#D8A1E681#, 16#E7D3FBC8#,
      16#21E1CDE6#, 16#C33707D6#, 16#F4D50D87#, 16#455A14ED#,
      16#A9E3E905#, 16#FCEFA3F8#, 16#676F02D9#, 16#8D2A4C8A#,
      16#FFFA3942#, 16#8771F681#, 16#6D9D6122#, 16#FDE5380C#,
      16#A4BEEA44#, 16#4BDECFA9#, 16#F6BB4B60#, 16#BEBFBC70#,
      16#289B7EC6#, 16#EAA127FA#, 16#D4EF3085#, 16#04881D05#,
      16#D9D4D039#, 16#E6DB99E5#, 16#1FA27CF8#, 16#C4AC5665#,
      16#F4292244#, 16#432AFF97#, 16#AB9423A7#, 16#FC93A039#,
      16#655B59C3#, 16#8F0CCC92#, 16#FFEFF47D#, 16#85845DD1#,
      16#6FA87E4F#, 16#FE2CE6E0#, 16#A3014314#, 16#4E0811A1#,
      16#F7537E82#, 16#BD3AF235#, 16#2AD7D2BB#, 16#EB86D391#];

   S : constant array (0 .. 63) of Natural :=
     [7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22,
      5, 9, 14, 20, 5, 9, 14, 20, 5, 9, 14, 20, 5, 9, 14, 20,
      4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23,
      6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21];

   function Rotl (X : Word; N : Natural) return Word is
      U : constant Interfaces.Unsigned_32 := Interfaces.Unsigned_32 (X);
   begin
      return Word (Interfaces.Rotate_Left (U, N));
   end Rotl;

   function Load (Padded : Octets; Offset : Positive) return Block is
      Result : Block := [others => 0];
   begin
      for I in 0 .. 15 loop
         declare
            Base : constant Positive := Offset + I * 4;
         begin
            Result (I) :=
              Word (Padded (Base))
              or Word (Padded (Base + 1)) * 2 ** 8
              or Word (Padded (Base + 2)) * 2 ** 16
              or Word (Padded (Base + 3)) * 2 ** 24;
         end;
      end loop;
      return Result;
   end Load;

   function MD5 (Data : Octets) return Digest is
      Bits   : constant Interfaces.Unsigned_64 :=
        Interfaces.Unsigned_64 (Data'Length) * Interfaces.Unsigned_64 (8);
      Pad    : Octets (1 .. 320) := [others => 0];
      Length : Natural := Data'Length;
      Blocks : Natural;
      A      : Word := 16#67452301#;
      B      : Word := 16#EFCDAB89#;
      C      : Word := 16#98BADCFE#;
      D      : Word := 16#10325476#;
      Result : Digest := [others => 0];
   begin
      for I in Data'Range loop
         Pad (1 + (I - Data'First)) := Data (I);
      end loop;
      Length := Length + 1;
      Pad (Length) := 16#80#;
      while (Length mod 64) /= 56 loop
         Length := Length + 1;
         Pad (Length) := 0;
      end loop;
      for I in 0 .. 7 loop
         Length := Length + 1;
         Pad (Length) :=
           Octet (Interfaces.Shift_Right (Bits, I * 8) and 16#FF#);
      end loop;

      Blocks := Length / 64;
      for Block_Index in 0 .. Blocks - 1 loop
         declare
            M  : constant Block := Load (Pad, 1 + Block_Index * 64);
            AA : Word := A;
            BB : Word := B;
            CC : Word := C;
            DD : Word := D;
            F  : Word;
            G  : Natural;
         begin
            for I in 0 .. 63 loop
               if I < 16 then
                  F := (BB and CC) or ((not BB) and DD);
                  G := I;
               elsif I < 32 then
                  F := (DD and BB) or ((not DD) and CC);
                  G := (5 * I + 1) mod 16;
               elsif I < 48 then
                  F := BB xor CC xor DD;
                  G := (3 * I + 5) mod 16;
               else
                  F := CC xor (BB or (not DD));
                  G := (7 * I) mod 16;
               end if;
               F := F + AA + K (I) + M (G);
               AA := DD;
               DD := CC;
               CC := BB;
               BB := BB + Rotl (F, S (I));
            end loop;
            A := A + AA;
            B := B + BB;
            C := C + CC;
            D := D + DD;
         end;
      end loop;

      declare
         Words : constant array (0 .. 3) of Word := [A, B, C, D];
      begin
         for W in 0 .. 3 loop
            for Byt in 0 .. 3 loop
               Result (1 + W * 4 + Byt) :=
                 Octet
                   (Interfaces.Shift_Right
                      (Interfaces.Unsigned_32 (Words (W)), Byt * 8) and 16#FF#);
            end loop;
         end loop;
      end;
      return Result;
   end MD5;

   function Name_UUID_From_Bytes (Data : Octets) return Digest is
      Result : Digest := MD5 (Data);
   begin
      Result (7) := (Result (7) and 16#0F#) or 16#30#;
      Result (9) := (Result (9) and 16#3F#) or 16#80#;
      return Result;
   end Name_UUID_From_Bytes;

   function Offline_UUID (Name : String) return Digest is
      Prefix : constant String := "OfflinePlayer:";
      Raw    : Octets (1 .. Prefix'Length + Name'Length);
   begin
      for I in Prefix'Range loop
         Raw (I - Prefix'First + 1) := Octet (Character'Pos (Prefix (I)));
      end loop;
      for I in Name'Range loop
         Raw (Prefix'Length + (I - Name'First + 1)) :=
           Octet (Character'Pos (Name (I)));
      end loop;
      return Name_UUID_From_Bytes (Raw);
   end Offline_UUID;

end Adacraft.Auth.MD5;
