with Ada.Containers.Indefinite_Ordered_Maps;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;

package body Differential.Normalize is

   package O renames Differential.Obs;
   package SU renames Ada.Strings.Unbounded;

   package Id_Maps is new Ada.Containers.Indefinite_Ordered_Maps
     (Key_Type => String, Element_Type => Natural);

   package Kv is new Ada.Containers.Indefinite_Ordered_Maps
     (Key_Type => String, Element_Type => String);

   Bad_Json : exception;

   function Img (N : Natural) return String is
     (Ada.Strings.Fixed.Trim (Natural'Image (N), Ada.Strings.Left));

   function Is_Ignored (Path : String) return Boolean is
      Start : Natural := Ignore_List'First;
   begin
      for I in Ignore_List'Range loop
         if Ignore_List (I) = ' ' then
            if Ignore_List (Start .. I - 1) = Path then
               return True;
            end if;
            Start := I + 1;
         end if;
      end loop;
      return Ignore_List (Start .. Ignore_List'Last) = Path;
   end Is_Ignored;

   function Is_Volatile_Key (Quoted : String) return Boolean is
     (Quoted in """id""" | """uuid""" | """entity_id""");

   function Canon
     (S     : String;
      Remap : Boolean;
      Ids   : in out Id_Maps.Map) return String
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

      function Parse_String return String is
         Start : constant Natural := Pos;
      begin
         if Pos > S'Last or else S (Pos) /= '"' then
            raise Bad_Json;
         end if;
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
         return S (Start .. Pos - 1);
      end Parse_String;

      function Parse_Value (Depth : Natural) return String is
      begin
         if Depth > 32 then
            raise Bad_Json;
         end if;
         Ws;
         if Pos > S'Last then
            raise Bad_Json;
         end if;
         case S (Pos) is
            when '"' =>
               return Parse_String;
            when '[' =>
               declare
                  R     : SU.Unbounded_String;
                  First : Boolean := True;
               begin
                  Pos := Pos + 1;
                  Ws;
                  if Pos <= S'Last and then S (Pos) = ']' then
                     Pos := Pos + 1;
                     return "[]";
                  end if;
                  SU.Append (R, "[");
                  loop
                     if not First then
                        SU.Append (R, ",");
                     end if;
                     First := False;
                     SU.Append (R, Parse_Value (Depth + 1));
                     Ws;
                     if Pos > S'Last then
                        raise Bad_Json;
                     elsif S (Pos) = ',' then
                        Pos := Pos + 1;
                     elsif S (Pos) = ']' then
                        Pos := Pos + 1;
                        exit;
                     else
                        raise Bad_Json;
                     end if;
                  end loop;
                  SU.Append (R, "]");
                  return SU.To_String (R);
               end;
            when '{' =>
               declare
                  M : Kv.Map;
                  R : SU.Unbounded_String;
                  Firstp : Boolean := True;
               begin
                  Pos := Pos + 1;
                  Ws;
                  if Pos <= S'Last and then S (Pos) = '}' then
                     Pos := Pos + 1;
                     return "{}";
                  end if;
                  loop
                     Ws;
                     declare
                        Key : constant String := Parse_String;
                     begin
                        Ws;
                        if Pos > S'Last or else S (Pos) /= ':' then
                           raise Bad_Json;
                        end if;
                        Pos := Pos + 1;
                        declare
                           V : String := Parse_Value (Depth + 1);
                        begin
                           if Remap and then Is_Volatile_Key (Key)
                             and then V'Length > 0
                             and then V (V'First) not in '{' | '['
                           then
                              if not Ids.Contains (V) then
                                 Ids.Insert (V, Natural (Ids.Length) + 1);
                              end if;
                              M.Include (Key, Img (Ids.Element (V)));
                           else
                              M.Include (Key, V);
                           end if;
                        end;
                     end;
                     Ws;
                     if Pos > S'Last then
                        raise Bad_Json;
                     elsif S (Pos) = ',' then
                        Pos := Pos + 1;
                     elsif S (Pos) = '}' then
                        Pos := Pos + 1;
                        exit;
                     else
                        raise Bad_Json;
                     end if;
                  end loop;
                  SU.Append (R, "{");
                  for C in M.Iterate loop
                     if not Firstp then
                        SU.Append (R, ",");
                     end if;
                     Firstp := False;
                     SU.Append (R, Kv.Key (C) & ":" & Kv.Element (C));
                  end loop;
                  SU.Append (R, "}");
                  return SU.To_String (R);
               end;
            when others =>
               declare
                  Start : constant Natural := Pos;
               begin
                  while Pos <= S'Last
                    and then S (Pos) not in
                      ',' | '}' | ']' | ' ' | ASCII.HT | ASCII.LF | ASCII.CR
                  loop
                     Pos := Pos + 1;
                  end loop;
                  if Pos = Start then
                     raise Bad_Json;
                  end if;
                  return S (Start .. Pos - 1);
               end;
         end case;
      end Parse_Value;

      Result : constant String := Parse_Value (0);
   begin
      Ws;
      if Pos <= S'Last then
         raise Bad_Json;
      end if;
      return Result;
   end Canon;

   function Canonical_Json (Text : String) return String is
      Ids : Id_Maps.Map;
   begin
      return Canon (Text, False, Ids);
   exception
      when Bad_Json =>
         return Text;
   end Canonical_Json;

   function Lift_Text (Value : String) return String is
     (if Value'Length > 0 and then Value (Value'First) = '"'
      then "{""text"":" & Value & "}"
      else Value);

   function Tagged_Summary (Path, Summary : String) return String is
   begin
      if Summary'Length >= 8
        and then Summary (Summary'First .. Summary'First + 7) = "ignored:"
      then
         return Summary;
      elsif Summary'Length >= 9
        and then Summary (Summary'First .. Summary'First + 8) = "unlisted:"
      then
         return Summary;
      elsif Is_Ignored (Path) then
         return "ignored:" & Summary;
      else
         return "unlisted:" & Summary;
      end if;
   end Tagged_Summary;

   function Normalize
     (Observation : Differential.Obs.Observation)
      return Differential.Obs.Observation
   is
      Ids    : Id_Maps.Map;
      Unused : Id_Maps.Map;
      Result : O.Observation;
   begin
      Result.Scenario_Id := Observation.Scenario_Id;
      for Src of Observation.Steps loop
         declare
            Dst : O.Step_Observation;
         begin
            Dst.State := Src.State;
            Dst.Result := Src.Result;
            for C in Src.Unlisted.Iterate loop
               Dst.Unlisted.Include
                 (O.Field_Maps.Key (C),
                  Tagged_Summary
                    (O.Field_Maps.Key (C), O.Field_Maps.Element (C)));
            end loop;
            for C in Src.Fields.Iterate loop
               declare
                  Key : constant String := O.Field_Maps.Key (C);
                  Raw : constant String := O.Field_Maps.Element (C);
               begin
                  if O.Is_Compared_Field (Key) and then not Is_Ignored (Key)
                  then
                     declare
                        V1 : String := Canonical_Json (Raw);
                     begin
                        if Key = O.F_Status_Description
                          or else Key = O.F_Login_Reason
                        then
                           V1 := Lift_Text (V1);
                        end if;
                        begin
                           Dst.Fields.Include (Key, Canon (V1, True, Ids));
                        exception
                           when Bad_Json =>
                              Dst.Fields.Include (Key, V1);
                        end;
                     end;
                  else
                     Dst.Unlisted.Include
                       (Key,
                        Tagged_Summary
                          (Key, "size" & Img (Raw'Length)));
                  end if;
               end;
            end loop;
            Result.Steps.Append (Dst);
         end;
      end loop;
      pragma Unreferenced (Unused);
      return Result;
   end Normalize;

end Differential.Normalize;
