with Ada.Strings;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;

package body Differential.Extract is

   package SU renames Ada.Strings.Unbounded;
   package C renames Differential.Client;
   package O renames Differential.Obs;
   use type C.PS.Connection_State;

   function Img (N : Natural) return String is
     (Ada.Strings.Fixed.Trim (Natural'Image (N), Ada.Strings.Left));

   --  Reads a VarInt-prefixed string that must fill the payload exactly.
   procedure Read_Str
     (Payload : String; Text : out SU.Unbounded_String; Ok : out Boolean)
   is
      Len   : Natural := 0;
      Shift : Natural := 0;
      Pos   : Natural := Payload'First;
      B     : Natural;
      Done  : Boolean := False;
   begin
      Text := SU.Null_Unbounded_String;
      Ok := False;
      for K in 1 .. 3 loop
         exit when Pos > Payload'Last;
         B := Character'Pos (Payload (Pos));
         Len := Len + (B mod 128) * (2 ** Shift);
         Shift := Shift + 7;
         Pos := Pos + 1;
         if B < 128 then
            Done := True;
            exit;
         end if;
      end loop;
      if Done and then Payload'Last - Pos + 1 = Len then
         Text := SU.To_Unbounded_String (Payload (Pos .. Payload'Last));
         Ok := True;
      end if;
   end Read_Str;

   --  Removes whitespace outside strings.
   function Compact (S : String) return String is
      R     : String (1 .. S'Length);
      N     : Natural := 0;
      In_S  : Boolean := False;
      Esc   : Boolean := False;
   begin
      for Ch of S loop
         if In_S then
            N := N + 1;
            R (N) := Ch;
            if Esc then
               Esc := False;
            elsif Ch = '\' then
               Esc := True;
            elsif Ch = '"' then
               In_S := False;
            end if;
         elsif Ch = '"' then
            In_S := True;
            N := N + 1;
            R (N) := Ch;
         elsif Ch not in ' ' | ASCII.HT | ASCII.LF | ASCII.CR then
            N := N + 1;
            R (N) := Ch;
         end if;
      end loop;
      return R (1 .. N);
   end Compact;

   Bad_Json : exception;

   procedure Parse_Status
     (S : String; Step : in out O.Step_Observation)
   is
      Pos : Natural := S'First;

      procedure Ws is
      begin
         while Pos <= S'Last
           and then S (Pos) in ' ' | ASCII.HT | ASCII.LF | ASCII.CR
         loop
            Pos := Pos + 1;
         end loop;
      end Ws;

      procedure Skip_String is
      begin
         Pos := Pos + 1;
         while Pos <= S'Last and then S (Pos) /= '"' loop
            if S (Pos) = '\' then
               Pos := Pos + 1;
            end if;
            Pos := Pos + 1;
         end loop;
         if Pos > S'Last then
            raise Bad_Json;
         end if;
         Pos := Pos + 1;
      end Skip_String;

      procedure Skip_Value is
         Depth : Natural := 0;
      begin
         if Pos > S'Last then
            raise Bad_Json;
         end if;
         case S (Pos) is
            when '"' =>
               Skip_String;
            when '{' | '[' =>
               loop
                  if Pos > S'Last then
                     raise Bad_Json;
                  end if;
                  case S (Pos) is
                     when '"' =>
                        Skip_String;
                     when '{' | '[' =>
                        Depth := Depth + 1;
                        Pos := Pos + 1;
                     when '}' | ']' =>
                        Depth := Depth - 1;
                        Pos := Pos + 1;
                     when others =>
                        Pos := Pos + 1;
                  end case;
                  exit when Depth = 0;
               end loop;
            when others =>
               while Pos <= S'Last
                 and then S (Pos) not in
                   ',' | '}' | ']' | ' ' | ASCII.HT | ASCII.LF | ASCII.CR
               loop
                  Pos := Pos + 1;
               end loop;
         end case;
      end Skip_Value;

      function Kind (V : String) return String is
        (if V'Length = 0 then "empty"
         elsif V (V'First) = '"' then "string"
         elsif V (V'First) = '[' then "array"
         elsif V (V'First) = '{' then "object"
         else "scalar");

      procedure Handle (Path, Value : String) is
         Added : Boolean;
         Name  : constant String := "status." & Path;
      begin
         if O.Is_Compared_Field (Name) then
            O.Set_Field (Step, Name, Value, Added);
         else
            O.Add_Unlisted
              (Step, Name, Kind (Value) & ":" & Img (Value'Length));
         end if;
      end Handle;

      procedure Parse_Object (Prefix : String; Depth : Natural) is
      begin
         if Depth > 8 or else Pos > S'Last or else S (Pos) /= '{' then
            raise Bad_Json;
         end if;
         Pos := Pos + 1;
         Ws;
         if Pos <= S'Last and then S (Pos) = '}' then
            Pos := Pos + 1;
            return;
         end if;
         loop
            Ws;
            if Pos > S'Last or else S (Pos) /= '"' then
               raise Bad_Json;
            end if;
            declare
               KS : constant Natural := Pos + 1;
            begin
               Skip_String;
               declare
                  Key  : constant String := S (KS .. Pos - 2);
                  Full : constant String := Prefix & Key;
                  Start : Natural;
               begin
                  Ws;
                  if Pos > S'Last or else S (Pos) /= ':' then
                     raise Bad_Json;
                  end if;
                  Pos := Pos + 1;
                  Ws;
                  Start := Pos;
                  if Pos <= S'Last and then S (Pos) = '{'
                    and then not O.Is_Compared_Field ("status." & Full)
                  then
                     Parse_Object (Full & ".", Depth + 1);
                  else
                     Skip_Value;
                     Handle (Full, Compact (S (Start .. Pos - 1)));
                  end if;
               end;
            end;
            Ws;
            if Pos > S'Last then
               raise Bad_Json;
            end if;
            if S (Pos) = ',' then
               Pos := Pos + 1;
            elsif S (Pos) = '}' then
               Pos := Pos + 1;
               exit;
            else
               raise Bad_Json;
            end if;
         end loop;
      end Parse_Object;
   begin
      Ws;
      Parse_Object ("", 0);
   end Parse_Status;

   function Extract_Step
     (Log         : C.Step_Log;
      Send_Failed : Boolean := False) return O.Step_Observation
   is
      Step      : O.Step_Observation;
      Bad       : Boolean := False;
      Rejected  : Boolean := False;
      Added     : Boolean;
      St        : constant C.PS.Connection_State := Log.State_After;
   begin
      Step.State := St;
      if not Log.Sent and then not Send_Failed then
         return Step;  --  skipped (clientbound-only) step
      end if;
      for P of Log.Packets loop
         declare
            Text : SU.Unbounded_String;
            Ok   : Boolean;
         begin
            if P.Id = Natural'Last then
               Bad := True;
            elsif St = C.PS.Status and then P.Id = 0 then
               Read_Str (SU.To_String (P.Payload), Text, Ok);
               if Ok then
                  begin
                     Parse_Status (SU.To_String (Text), Step);
                  exception
                     when Bad_Json =>
                        Bad := True;
                  end;
               else
                  Bad := True;
               end if;
            elsif St = C.PS.Status and then P.Id = 1 then
               O.Add_Unlisted
                 (Step, "status.pong",
                  "present:" & Img (SU.Length (P.Payload)));
            elsif St = C.PS.Login and then P.Id = 0 then
               Read_Str (SU.To_String (P.Payload), Text, Ok);
               if Ok then
                  Rejected := True;
                  O.Set_Field (Step, O.F_Login_Outcome, """rejected""", Added);
                  O.Set_Field
                    (Step, O.F_Login_Reason,
                     Compact (SU.To_String (Text)), Added);
               else
                  Bad := True;
               end if;
            else
               O.Add_Unlisted
                 (Step, "packet." & Img (P.Id),
                  "unrecognised:" & Img (SU.Length (P.Payload)));
            end if;
         end;
      end loop;

      if Send_Failed then
         Step.Result := O.Terminal;
      elsif Log.Framing_Error or else Bad then
         Step.Result := O.Malformed;
      elsif Rejected then
         Step.Result := O.Rejected;
      elsif Log.Closed then
         Step.Result := O.Disconnected;
         if St = C.PS.Login then
            O.Set_Field (Step, O.F_Login_Outcome, """disconnected""", Added);
         end if;
      elsif Log.No_Data then
         Step.Result := O.Timeout;
      else
         Step.Result := O.Ok;
      end if;
      return Step;
   end Extract_Step;

   function Extract
     (Output      : C.Run_Output;
      Scenario_Id : String) return O.Observation
   is
      R    : O.Observation;
      Last : constant Natural := Natural (Output.Steps.Length);
      I    : Natural := 0;
   begin
      R.Scenario_Id := SU.To_Unbounded_String (Scenario_Id);
      for L of Output.Steps loop
         I := I + 1;
         R.Steps.Append
           (Extract_Step (L, Output.Failed and then I = Last
                             and then not L.Sent));
      end loop;
      return R;
   end Extract;

end Differential.Extract;
