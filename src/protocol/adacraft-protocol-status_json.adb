with Adacraft.Protocol.Frame;

package body Adacraft.Protocol.Status_Json is

   function Trim_Image (V : Integer) return String is
      Img : constant String := Integer'Image (V);
   begin
      return Img (Img'First + 1 .. Img'Last);
   end Trim_Image;

   function Trim_Image_Nat (V : Natural) return String is
      Img : constant String := Natural'Image (V);
   begin
      return Img (Img'First + 1 .. Img'Last);
   end Trim_Image_Nat;

   function Hex_Digit (N : Natural) return Character is
   begin
      if N < 10 then
         return Character'Val (Character'Pos ('0') + N);
      else
         return Character'Val (Character'Pos ('a') + N - 10);
      end if;
   end Hex_Digit;

   function Escape_Into (S : String) return String is
      Buf : String (1 .. S'Length * 6);
      Pos : Natural := 0;
   begin
      for I in S'Range loop
         declare
            C : constant Natural := Character'Pos (S (I));
         begin
            case C is
               when 16#22# => --  '"'
                  Buf (Pos + 1) := '\';
                  Buf (Pos + 2) := '"';
                  Pos := Pos + 2;
               when 16#5C# => --  '\'
                  Buf (Pos + 1) := '\';
                  Buf (Pos + 2) := '\';
                  Pos := Pos + 2;
               when 16#08# =>
                  Buf (Pos + 1) := '\';
                  Buf (Pos + 2) := 'b';
                  Pos := Pos + 2;
               when 16#0C# =>
                  Buf (Pos + 1) := '\';
                  Buf (Pos + 2) := 'f';
                  Pos := Pos + 2;
               when 16#0A# =>
                  Buf (Pos + 1) := '\';
                  Buf (Pos + 2) := 'n';
                  Pos := Pos + 2;
               when 16#0D# =>
                  Buf (Pos + 1) := '\';
                  Buf (Pos + 2) := 'r';
                  Pos := Pos + 2;
               when 16#09# =>
                  Buf (Pos + 1) := '\';
                  Buf (Pos + 2) := 't';
                  Pos := Pos + 2;
               when 16#00# .. 16#1F# =>
                  Buf (Pos + 1) := '\';
                  Buf (Pos + 2) := 'u';
                  Buf (Pos + 3) := '0';
                  Buf (Pos + 4) := '0';
                  Buf (Pos + 5) := Hex_Digit (C / 16);
                  Buf (Pos + 6) := Hex_Digit (C mod 16);
                  Pos := Pos + 6;
               when others =>
                  Pos := Pos + 1;
                  Buf (Pos) := S (I);
            end case;
         end;
      end loop;
      if Pos = 0 then
         return "";
      else
         return Buf (1 .. Pos);
      end if;
   end Escape_Into;

   function To_Json (Info : Status_Info.Status_Info) return String is
      VN   : constant String := Status_Info.Version_Name (Info);
      PN   : constant String := Trim_Image (Status_Info.Protocol_Number (Info));
      MX   : constant String :=
        Trim_Image_Nat (Status_Info.Max_Players (Info));
      ON   : constant String :=
        Trim_Image_Nat (Status_Info.Online_Players (Info));
      MO   : constant String := Status_Info.Motd (Info);
      EVN  : constant String := Escape_Into (VN);
      EMOT : constant String := Escape_Into (MO);
      EB   : constant String :=
        (if Status_Info.Enforces_Secure_Chat (Info) then "true" else "false");
      Result : constant String :=
        "{""version"":{""name"":""" & EVN & """,""protocol"":" & PN
        & "},""players"":{""max"":" & MX & ",""online"":" & ON
        & "},""description"":{""text"":""" & EMOT & """}"
        & ",""enforcesSecureChat"":" & EB & "}";
   begin
      pragma Assert (Result'Length <= Max_Json_Length);
      pragma Assert
        (Result'Length <= Adacraft.Protocol.Frame.Max_Frame_Body_Length);
      pragma Assert
        (Result'Length <= Adacraft.Protocol.Max_Packet_Length);
      return Result;
   end To_Json;

end Adacraft.Protocol.Status_Json;
