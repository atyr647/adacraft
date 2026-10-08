with Ada.Command_Line;
with Ada.Strings.Unbounded;
with Ada.Text_IO;

package body Differential.Args is
   use Ada.Strings.Unbounded;

   Usage : constant String :=
     "Usage: differential --selftest | --oracle <host>:<port> " &
     "--candidate <host>:<port>";

   procedure Invalid_Arguments is
   begin
      Ada.Text_IO.Put_Line (Ada.Text_IO.Standard_Error, Usage);
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
   end Invalid_Arguments;

   function Parse_Endpoint (Value : String; Result : out Endpoint)
                            return Boolean
   is
      Separator : Natural := 0;
      Port_Value : Natural := 0;
   begin
      for Index in Value'Range loop
         if Value (Index) = ':' then
            if Separator /= 0 then
               return False;
            end if;
            Separator := Index;
         end if;
      end loop;

      if Separator = 0 or else Separator = Value'First
        or else Separator = Value'Last
      then
         return False;
      end if;

      for Index in Separator + 1 .. Value'Last loop
         if Value (Index) not in '0' .. '9' then
            return False;
         end if;
         declare
            Digit : constant Natural :=
              Character'Pos (Value (Index)) - Character'Pos ('0');
         begin
            if Port_Value > (65_535 - Digit) / 10 then
               return False;
            end if;
            Port_Value := Port_Value * 10 + Digit;
         end;
      end loop;

      if Port_Value not in 1 .. 65_535 then
         return False;
      end if;

      Result :=
        (Host => To_Unbounded_String (Value (Value'First .. Separator - 1)),
         Port => Port_Value);
      return True;
   end Parse_Endpoint;

   procedure Parse (Result : out Options) is
      Oracle_Set    : Boolean := False;
      Candidate_Set : Boolean := False;
      Selftest_Set  : Boolean := False;
      Valid         : Boolean := True;
      Index         : Positive := 1;
      Count         : constant Natural := Ada.Command_Line.Argument_Count;
      Arg           : Unbounded_String;
   begin
      Result := (Selftest => False, Oracle => <>, Candidate => <>);

      while Index <= Count and then Valid loop
         Arg := To_Unbounded_String (Ada.Command_Line.Argument (Index));
         if To_String (Arg) = "--selftest" then
            if Selftest_Set or else Oracle_Set or else Candidate_Set
              or else Index /= Count
            then
               Valid := False;
            else
               Selftest_Set := True;
               Result.Selftest := True;
            end if;
            Index := Index + 1;
         elsif To_String (Arg) = "--oracle"
           or else To_String (Arg) = "--candidate"
         then
            if Index = Count then
               Valid := False;
               Index := Index + 1;
            else
               declare
                  Is_Oracle : constant Boolean := To_String (Arg) = "--oracle";
                  Value : constant String :=
                    Ada.Command_Line.Argument (Index + 1);
               begin
                  if Is_Oracle then
                     if Oracle_Set
                       or else not Parse_Endpoint (Value, Result.Oracle)
                     then
                        Valid := False;
                     else
                        Oracle_Set := True;
                     end if;
                  else
                     if Candidate_Set
                       or else not Parse_Endpoint (Value, Result.Candidate)
                     then
                        Valid := False;
                     else
                        Candidate_Set := True;
                     end if;
                  end if;
               end;
               Index := Index + 2;
            end if;
         else
            Valid := False;
            Index := Index + 1;
         end if;
      end loop;

      if not Selftest_Set
        and then not (Oracle_Set and Candidate_Set)
      then
         Valid := False;
      end if;

      if not Valid then
         Invalid_Arguments;
      end if;
   end Parse;
end Differential.Args;
