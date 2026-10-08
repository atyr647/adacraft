package body Adacraft.Protocol.Status_Info is

   function Is_Valid_Utf8 (S : String) return Boolean is
      I : Positive := S'First;
   begin
      if S'Length = 0 then
         return True;
      end if;
      while I <= S'Last loop
         declare
            B0 : constant Natural := Character'Pos (S (I));
         begin
            if B0 <= 16#7F# then
               I := I + 1;
            elsif B0 in 16#C2# .. 16#DF# then
               if I + 1 > S'Last then
                  return False;
               end if;
               declare
                  B1 : constant Natural := Character'Pos (S (I + 1));
               begin
                  if B1 not in 16#80# .. 16#BF# then
                     return False;
                  end if;
               end;
               I := I + 2;
            elsif B0 in 16#E0# .. 16#EF# then
               if I + 2 > S'Last then
                  return False;
               end if;
               declare
                  B1 : constant Natural := Character'Pos (S (I + 1));
                  B2 : constant Natural := Character'Pos (S (I + 2));
               begin
                  if B1 not in 16#80# .. 16#BF#
                    or else B2 not in 16#80# .. 16#BF#
                  then
                     return False;
                  end if;
                  if B0 = 16#E0# and then B1 < 16#A0# then
                     return False;
                  end if;
                  if B0 = 16#ED# and then B1 > 16#9F# then
                     return False;
                  end if;
               end;
               I := I + 3;
            elsif B0 in 16#F0# .. 16#F4# then
               if I + 3 > S'Last then
                  return False;
               end if;
               declare
                  B1 : constant Natural := Character'Pos (S (I + 1));
                  B2 : constant Natural := Character'Pos (S (I + 2));
                  B3 : constant Natural := Character'Pos (S (I + 3));
               begin
                  if B1 not in 16#80# .. 16#BF#
                    or else B2 not in 16#80# .. 16#BF#
                    or else B3 not in 16#80# .. 16#BF#
                  then
                     return False;
                  end if;
                  if B0 = 16#F0# and then B1 < 16#90# then
                     return False;
                  end if;
                  if B0 = 16#F4# and then B1 > 16#8F# then
                     return False;
                  end if;
               end;
               I := I + 4;
            else
               return False;
            end if;
         end;
      end loop;
      return True;
   end Is_Valid_Utf8;

   function Create
     (Motd                 : String;
      Max_Players          : Natural := Default_Max_Players;
      Online_Players       : Natural := Default_Online;
      Enforces_Secure_Chat : Boolean := False;
      Version_Name         : String := Default_Version_Name;
      Protocol             : Integer := Default_Protocol) return Status_Info
   is
      Info : Status_Info;
   begin
      if Motd'Length > Max_Motd_Bytes then
         raise Invalid_Status_Info with "MOTD exceeds 256 bytes";
      end if;
      if not Is_Valid_Utf8 (Motd) then
         raise Invalid_Status_Info with "MOTD is not valid UTF-8";
      end if;
      if Version_Name'Length > Max_Version_Name_Bytes then
         raise Invalid_Status_Info with "version name too long";
      end if;
      if not Is_Valid_Utf8 (Version_Name) then
         raise Invalid_Status_Info with "version name is not valid UTF-8";
      end if;
      Info.Version_Len := Version_Name'Length;
      Info.Version_Txt := (others => ' ');
      for I in 1 .. Version_Name'Length loop
         Info.Version_Txt (I) :=
           Version_Name (Version_Name'First + I - 1);
      end loop;
      Info.Protocol := Protocol;
      Info.Max_Players := Max_Players;
      Info.Online := Online_Players;
      Info.Motd_Len := Motd'Length;
      Info.Motd_Txt := (others => ' ');
      for I in 1 .. Motd'Length loop
         Info.Motd_Txt (I) := Motd (Motd'First + I - 1);
      end loop;
      Info.Enforces := Enforces_Secure_Chat;
      return Info;
   end Create;

   function Default_Info return Status_Info is
   begin
      return Create (Default_Motd);
   end Default_Info;

   function Motd (Info : Status_Info) return String is
     (if Info.Motd_Len = 0 then ""
      else Info.Motd_Txt (1 .. Info.Motd_Len));

   function Max_Players (Info : Status_Info) return Natural is
     (Info.Max_Players);

   function Online_Players (Info : Status_Info) return Natural is
     (Info.Online);

   function Enforces_Secure_Chat (Info : Status_Info) return Boolean is
     (Info.Enforces);

   function Version_Name (Info : Status_Info) return String is
     (if Info.Version_Len = 0 then ""
      else Info.Version_Txt (1 .. Info.Version_Len));

   function Protocol_Number (Info : Status_Info) return Integer is
     (Info.Protocol);

end Adacraft.Protocol.Status_Info;
