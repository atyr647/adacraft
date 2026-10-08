with Ada.Command_Line;

package body Differential.Args is

   function Host_Image (E : Endpoint) return String is
   begin
      if E.Host_Len = 0 then
         return "";
      end if;
      return E.Host (1 .. E.Host_Len);
   end Host_Image;

   function Parse_Endpoint (Text : String; E : out Endpoint) return Boolean is
      Colon : Natural := 0;
   begin
      E := (others => <>);
      for I in Text'Range loop
         if Text (I) = ':' then
            Colon := I;
         end if;
      end loop;
      if Colon = Text'First then
         return False;
      end if;
      if Colon = 0 or else Colon = Text'Last then
         return False;
      end if;
      declare
         Host_Part : constant String := Text (Text'First .. Colon - 1);
         Port_Part : constant String := Text (Colon + 1 .. Text'Last);
         P : Natural := 0;
      begin
         if Host_Part'Length < 1 or else Host_Part'Length > 256 then
            return False;
         end if;
         if Port_Part'Length < 1 or else Port_Part'Length > 5 then
            return False;
         end if;
         for C of Port_Part loop
            if C not in '0' .. '9' then
               return False;
            end if;
            P := P * 10 + (Character'Pos (C) - Character'Pos ('0'));
         end loop;
         if P < 1 or else P > 65_535 then
            return False;
         end if;
         E.Host (1 .. Host_Part'Length) := Host_Part;
         E.Host_Len := Host_Part'Length;
         E.Port := P;
         return True;
      end;
   end Parse_Endpoint;

   function Parse return Config is
      use Ada.Command_Line;
      Result : Config;
      Seen_Oracle : Boolean := False;
      Seen_Candidate : Boolean := False;
      Seen_Selftest : Boolean := False;
      Oracle_Text : String (1 .. 300) := (others => ' ');
      Oracle_Len : Natural := 0;
      Candidate_Text : String (1 .. 300) := (others => ' ');
      Candidate_Len : Natural := 0;
      I : Positive := 1;
   begin
      if Argument_Count = 0 then
         Result.Mode := Usage_Error;
         return Result;
      end if;
      while I <= Argument_Count loop
         declare
            A : constant String := Argument (I);
         begin
            if A = "--selftest" then
               if Seen_Selftest or Seen_Oracle or Seen_Candidate then
                  Result.Mode := Usage_Error;
                  return Result;
               end if;
               Seen_Selftest := True;
               I := I + 1;
            elsif A = "--oracle" then
               if Seen_Oracle or Seen_Selftest then
                  Result.Mode := Usage_Error;
                  return Result;
               end if;
               if I + 1 > Argument_Count then
                  Result.Mode := Usage_Error;
                  return Result;
               end if;
               Seen_Oracle := True;
               declare
                  V : constant String := Argument (I + 1);
               begin
                  if V'Length > Oracle_Text'Length then
                     Result.Mode := Usage_Error;
                     return Result;
                  end if;
                  Oracle_Text (1 .. V'Length) := V;
                  Oracle_Len := V'Length;
               end;
               I := I + 2;
            elsif A = "--candidate" then
               if Seen_Candidate or Seen_Selftest then
                  Result.Mode := Usage_Error;
                  return Result;
               end if;
               if I + 1 > Argument_Count then
                  Result.Mode := Usage_Error;
                  return Result;
               end if;
               Seen_Candidate := True;
               declare
                  V : constant String := Argument (I + 1);
               begin
                  if V'Length > Candidate_Text'Length then
                     Result.Mode := Usage_Error;
                     return Result;
                  end if;
                  Candidate_Text (1 .. V'Length) := V;
                  Candidate_Len := V'Length;
               end;
               I := I + 2;
            else
               Result.Mode := Usage_Error;
               return Result;
            end if;
         end;
      end loop;

      if Seen_Selftest then
         if Seen_Oracle or Seen_Candidate then
            Result.Mode := Usage_Error;
            return Result;
         end if;
         Result.Mode := Run_Selftest;
         return Result;
      end if;

      if not (Seen_Oracle and Seen_Candidate) then
         Result.Mode := Usage_Error;
         return Result;
      end if;

      if not Parse_Endpoint (Oracle_Text (1 .. Oracle_Len), Result.Oracle) then
         Result.Mode := Usage_Error;
         return Result;
      end if;
      if not Parse_Endpoint
        (Candidate_Text (1 .. Candidate_Len), Result.Candidate)
      then
         Result.Mode := Usage_Error;
         Result.Oracle := (others => <>);
         return Result;
      end if;
      Result.Mode := Run_Compare;
      return Result;
   end Parse;

   procedure Put_Usage (File : in out Ada.Text_IO.File_Type) is
      use Ada.Text_IO;
   begin
      Put_Line (File, "Usage:");
      Put_Line (File,
        "  differential-main --oracle <host:port> --candidate <host:port>");
      Put_Line (File, "  differential-main --selftest");
   end Put_Usage;

end Differential.Args;
