with Ada.Characters.Handling;
with Ada.Command_Line;
with Ada.Directories;
with Ada.Strings.Fixed;
with Ada.Text_IO;

--  DR-1: the shipped source closure (src/, generated/, and the bin/adacraft
--  Makefile rule) must not contain or name Differential units.
--  Run from the repository root.
procedure Test_Diff_Build_Isolation is
   use Ada.Directories;
   Failures : Natural := 0;

   function Lower (S : String) return String is
     (Ada.Characters.Handling.To_Lower (S));

   procedure Fail (Msg : String) is
   begin
      Ada.Text_IO.Put_Line ("FAIL " & Msg);
      Failures := Failures + 1;
   end Fail;

   procedure Scan_File (Path : String) is
      F : Ada.Text_IO.File_Type;
   begin
      Ada.Text_IO.Open (F, Ada.Text_IO.In_File, Path);
      while not Ada.Text_IO.End_Of_File (F) loop
         declare
            L : constant String :=
              Lower (Ada.Strings.Fixed.Trim
                       (Ada.Text_IO.Get_Line (F), Ada.Strings.Both));
         begin
            if L'Length > 5 and then L (L'First .. L'First + 4) = "with "
              and then Ada.Strings.Fixed.Index (L, "differential") > 0
            then
               Fail (Path & " withs a Differential unit");
            end if;
         end;
      end loop;
      Ada.Text_IO.Close (F);
   end Scan_File;

   procedure Scan_Dir (Dir : String) is
      S : Search_Type;
      E : Directory_Entry_Type;
   begin
      if not Exists (Dir) then
         Fail ("missing directory " & Dir);
         return;
      end if;
      Start_Search (S, Dir, "", (others => True));
      while More_Entries (S) loop
         Get_Next_Entry (S, E);
         declare
            Name : constant String := Simple_Name (E);
            Full : constant String := Full_Name (E);
         begin
            if Name = "." or else Name = ".." then
               null;
            elsif Kind (E) = Directory then
               Scan_Dir (Full);
            else
               if Ada.Strings.Fixed.Index (Lower (Name), "differential") > 0
               then
                  Fail ("Differential file in shipped tree: " & Full);
               end if;
               if Extension (Name) = "ads" or else Extension (Name) = "adb"
               then
                  Scan_File (Full);
               end if;
            end if;
         end;
      end loop;
      End_Search (S);
   end Scan_Dir;

   procedure Scan_Makefile is
      F  : Ada.Text_IO.File_Type;
      In_Rule : Boolean := False;
   begin
      Ada.Text_IO.Open (F, Ada.Text_IO.In_File, "Makefile");
      while not Ada.Text_IO.End_Of_File (F) loop
         declare
            L : constant String := Ada.Text_IO.Get_Line (F);
         begin
            if L'Length >= 12 and then L (L'First .. L'First + 11) = "bin/adacraft"
              and then Ada.Strings.Fixed.Index (L, ":") > 0
              and then L (L'First + 12) = ':'
            then
               In_Rule := True;
            elsif L'Length = 0 or else L (L'First) /= ASCII.HT then
               In_Rule := False;
            end if;
            if In_Rule
              and then Ada.Strings.Fixed.Index (Lower (L), "differential") > 0
            then
               Fail ("shipped adacraft rule mentions differential");
            end if;
         end;
      end loop;
      Ada.Text_IO.Close (F);
   end Scan_Makefile;
begin
   Scan_Dir ("src");
   Scan_Dir ("generated");
   Scan_Makefile;
   if Failures > 0 then
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
   end if;
end Test_Diff_Build_Isolation;
