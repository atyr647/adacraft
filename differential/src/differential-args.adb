with Ada.Command_Line;
with Ada.Text_IO;

package body Differential.Args is

   use Ada.Strings.Unbounded;

   function Try_Parse_Endpoint
     (Text   : in String;
      Result : out Endpoint) return Boolean
   is
      Sep : Natural := 0;
   begin
      Result := (Host => Null_Unbounded_String, Port => 0);
      for I in Text'Range loop
         if Text (I) = ':' then
            Sep := I;
         end if;
      end loop;
      if Sep = 0 then
         return False;
      end if;
      if Sep = Text'First then
         return False;
      end if;
      if Sep = Text'Last then
         return False;
      end if;
      declare
         Host_Part : constant String := Text (Text'First .. Sep - 1);
         Port_Part : constant String := Text (Sep + 1 .. Text'Last);
         Value     : Natural := 0;
      begin
         if Host_Part'Length = 0 or else Port_Part'Length = 0 then
            return False;
         end if;
         for C of Port_Part loop
            if C not in '0' .. '9' then
               return False;
            end if;
         end loop;
         begin
            Value := Natural'Value (Port_Part);
         exception
            when Constraint_Error =>
               return False;
         end;
         if Value < 1 or else Value > 65_535 then
            return False;
         end if;
         Result.Host := To_Unbounded_String (Host_Part);
         Result.Port := Value;
         return True;
      end;
   end Try_Parse_Endpoint;

   procedure Print_Usage is
   begin
      Ada.Text_IO.Put_Line
        (File => Ada.Text_IO.Standard_Error,
         Item => "usage: differential-main " &
           "--oracle HOST:PORT --candidate HOST:PORT | --selftest");
   end Print_Usage;

   procedure Parse_Command_Line
     (Is_Selftest : out Boolean;
      Oracle      : out Endpoint;
      Candidate   : out Endpoint;
      Valid       : out Boolean)
   is
      use Ada.Command_Line;
      Has_Oracle    : Boolean := False;
      Has_Candidate : Boolean := False;
      Saw_Selftest  : Boolean := False;
      Failed        : Boolean := False;
      I             : Positive := 1;
   begin
      Is_Selftest := False;
      Oracle := (Host => Null_Unbounded_String, Port => 0);
      Candidate := (Host => Null_Unbounded_String, Port => 0);
      Valid := False;
      if Argument_Count = 0 then
         return;
      end if;
      while I <= Argument_Count loop
         declare
            A : constant String := Argument (I);
         begin
            if A = "--selftest" then
               if Saw_Selftest then
                  Failed := True;
               end if;
               Saw_Selftest := True;
               I := I + 1;
            elsif A = "--oracle" then
               if Has_Oracle then
                  Failed := True;
               end if;
               if I = Argument_Count then
                  Failed := True;
                  I := I + 1;
               else
                  declare
                     EP : Endpoint;
                     Ok : Boolean;
                  begin
                     Ok := Try_Parse_Endpoint (Argument (I + 1), EP);
                     if Ok then
                        Oracle := EP;
                        Has_Oracle := True;
                     else
                        Failed := True;
                     end if;
                     I := I + 2;
                  end;
               end if;
            elsif A = "--candidate" then
               if Has_Candidate then
                  Failed := True;
               end if;
               if I = Argument_Count then
                  Failed := True;
                  I := I + 1;
               else
                  declare
                     EP : Endpoint;
                     Ok : Boolean;
                  begin
                     Ok := Try_Parse_Endpoint (Argument (I + 1), EP);
                     if Ok then
                        Candidate := EP;
                        Has_Candidate := True;
                     else
                        Failed := True;
                     end if;
                     I := I + 2;
                  end;
               end if;
            else
               Failed := True;
               I := I + 1;
            end if;
         end;
      end loop;
      if Failed then
         Valid := False;
         return;
      end if;
      if Saw_Selftest then
         if Has_Oracle or else Has_Candidate then
            Valid := False;
            return;
         end if;
         if Argument_Count /= 1 then
            Valid := False;
            return;
         end if;
         Is_Selftest := True;
         Valid := True;
         return;
      end if;
      if Has_Oracle and then Has_Candidate then
         Is_Selftest := False;
         Valid := True;
      else
         Valid := False;
      end if;
   end Parse_Command_Line;

end Differential.Args;
