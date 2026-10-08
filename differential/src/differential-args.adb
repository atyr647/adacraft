with Ada.Command_Line;
with Ada.Strings.Unbounded;
with Ada.Text_IO;

package body Differential.Args is
   use Ada.Strings.Unbounded;

   procedure Print_Usage is
   begin
      Ada.Text_IO.Put_Line
        (Ada.Text_IO.Standard_Error,
         "Usage: differential-main --oracle HOST:PORT --candidate HOST:PORT");
      Ada.Text_IO.Put_Line
        (Ada.Text_IO.Standard_Error,
         "       differential-main --selftest");
   end Print_Usage;

   procedure Fail is
   begin
      Print_Usage;
      raise Usage_Error;
   end Fail;

   procedure Parse_Address
     (Text : String;
      Host : out Unbounded_String;
      Port : out Natural)
   is
      Separator : Natural := 0;
      Parsed    : Natural := 0;
   begin
      for Index in Text'Range loop
         if Text (Index) = ':' then
            Separator := Index;
         end if;
      end loop;

      if Separator = Text'First
        or else Separator = 0
        or else Separator = Text'Last
      then
         Fail;
      end if;

      for Index in Separator + 1 .. Text'Last loop
         if Text (Index) not in '0' .. '9' then
            Fail;
         end if;

         declare
            Digit : constant Natural :=
              Character'Pos (Text (Index)) - Character'Pos ('0');
         begin
            if Parsed > 6553 or else
              (Parsed = 6553 and then Digit > 5)
            then
               Fail;
            end if;
            Parsed := Parsed * 10 + Digit;
         end;
      end loop;

      if Parsed = 0 then
         Fail;
      end if;

      Host := To_Unbounded_String (Text (Text'First .. Separator - 1));
      Port := Parsed;
   end Parse_Address;

   function Parse return Options is
      Result        : Options;
      Have_Oracle   : Boolean := False;
      Have_Candidate : Boolean := False;
      Have_Selftest : Boolean := False;
      Index         : Positive := 1;
      Count         : constant Natural := Ada.Command_Line.Argument_Count;
   begin
      if Count = 0 then
         Fail;
      end if;

      while Index <= Count loop
         declare
            Argument : constant String := Ada.Command_Line.Argument (Index);
         begin
            if Argument = "--selftest" then
               if Have_Selftest then
                  Fail;
               end if;
               Have_Selftest := True;
               Result.Selftest := True;
               Index := Index + 1;
            elsif Argument = "--oracle" then
               if Have_Oracle or else Index = Count then
                  Fail;
               end if;
               Have_Oracle := True;
               Parse_Address
                 (Ada.Command_Line.Argument (Index + 1),
                  Result.Oracle_Host, Result.Oracle_Port);
               Index := Index + 2;
            elsif Argument = "--candidate" then
               if Have_Candidate or else Index = Count then
                  Fail;
               end if;
               Have_Candidate := True;
               Parse_Address
                 (Ada.Command_Line.Argument (Index + 1),
                  Result.Candidate_Host, Result.Candidate_Port);
               Index := Index + 2;
            else
               Fail;
            end if;
         end;
      end loop;

      if Have_Selftest then
         if Have_Oracle or else Have_Candidate then
            Fail;
         end if;
      elsif not Have_Oracle or else not Have_Candidate then
         Fail;
      end if;

      return Result;
   end Parse;
end Differential.Args;
