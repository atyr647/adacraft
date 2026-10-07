with Ada.Characters.Latin_1;
with Ada.Strings.Fixed;

package body Differential.Report is

   package SU renames Ada.Strings.Unbounded;
   package O renames Differential.Obs;
   package C renames Differential.Compare;

   function Img (N : Natural) return String is
     (Ada.Strings.Fixed.Trim (Natural'Image (N), Ada.Strings.Left));

   function Image (C : Category) return String is
     (case C is
         when Matched        => "matched",
         when Mismatched     => "mismatched",
         when Infrastructure => "infrastructure");

   function Tally_Of (Results : Result_Vectors.Vector) return Tally is
      T : Tally;
   begin
      for R of Results loop
         case R.Cat is
            when Matched        => T.Matched := T.Matched + 1;
            when Mismatched     => T.Mismatched := T.Mismatched + 1;
            when Infrastructure => T.Infrastructure := T.Infrastructure + 1;
         end case;
      end loop;
      return T;
   end Tally_Of;

   function Q (S : String) return String is
      Hex : constant String := "0123456789abcdef";
      R   : SU.Unbounded_String;
   begin
      SU.Append (R, '"');
      for Ch of S loop
         case Ch is
            when '"'  => SU.Append (R, "\""");
            when '\'  => SU.Append (R, "\\");
            when Ada.Characters.Latin_1.LF => SU.Append (R, "\n");
            when others =>
               if Character'Pos (Ch) < 32 then
                  SU.Append
                    (R, "\u00"
                     & Hex (Character'Pos (Ch) / 16 + 1)
                     & Hex (Character'Pos (Ch) mod 16 + 1));
               else
                  SU.Append (R, Ch);
               end if;
         end case;
      end loop;
      SU.Append (R, '"');
      return SU.To_String (R);
   end Q;

   function Render_Json
     (Prov    : Provenance;
      Results : Result_Vectors.Vector) return String
   is
      J     : SU.Unbounded_String;
      T     : constant Tally := Tally_Of (Results);
      First : Boolean := True;

      procedure Sep (F : in out Boolean) is
      begin
         if not F then
            SU.Append (J, ",");
         end if;
         F := False;
      end Sep;
   begin
      SU.Append (J, "{""body"":{");
      SU.Append (J, """ignore_list_version"":" & Img (Ignore_List_Version));
      SU.Append (J, ",""normalization_version"":"
                    & Img (Normalization_Version));
      SU.Append (J, ",""results"":[");
      for R of Results loop
         Sep (First);
         SU.Append (J, "{""category"":" & Q (Image (R.Cat)));
         SU.Append (J, ",""detail"":" & Q (SU.To_String (R.Detail)));
         SU.Append (J, ",""diffs"":[");
         declare
            F2 : Boolean := True;
         begin
            for D of R.Diffs loop
               Sep (F2);
               SU.Append (J, "{""adacraft"":" & Q (SU.To_String
                            (D.Adacraft_Value)));
               SU.Append (J, ",""kind"":" & Q (C.Image (D.Kind)));
               SU.Append (J, ",""oracle"":" & Q (SU.To_String
                            (D.Oracle_Value)));
               SU.Append (J, ",""path"":" & Q (SU.To_String (D.Path)));
               SU.Append (J, ",""step"":" & Img (D.Step) & "}");
            end loop;
         end;
         SU.Append (J, "],""id"":" & Q (SU.To_String (R.Id)));
         SU.Append (J, ",""ignored"":[");
         declare
            F3 : Boolean := True;
         begin
            for Cur in R.Unlisted.Iterate loop
               Sep (F3);
               SU.Append (J, "{""path"":" & Q (O.Field_Maps.Key (Cur))
                          & ",""present"":true,""summary"":"
                          & Q (O.Field_Maps.Element (Cur)) & "}");
            end loop;
         end;
         SU.Append (J, "]}");
      end loop;
      SU.Append (J, "],""schema_version"":"
                    & Img (Comparison_Schema_Version));
      SU.Append (J, ",""tally"":{""infrastructure"":"
                    & Img (T.Infrastructure)
                    & ",""matched"":" & Img (T.Matched)
                    & ",""mismatched"":" & Img (T.Mismatched) & "}}");
      SU.Append (J, ",""provenance"":{""corpus_id"":"
                    & Q (SU.To_String (Prov.Corpus_Id)));
      SU.Append (J, ",""jar_path"":" & Q (SU.To_String (Prov.Jar_Path)));
      SU.Append (J, ",""jar_sha256"":" & Q (SU.To_String (Prov.Jar_Sha256)));
      SU.Append (J, ",""java_version"":"
                    & Q (SU.To_String (Prov.Java_Version)));
      SU.Append (J, ",""observed_protocol"":"
                    & Q (SU.To_String (Prov.Observed_Protocol)) & "}}");
      return SU.To_String (J) & Ada.Characters.Latin_1.LF;
   end Render_Json;

   function Render_Summary
     (Results : Result_Vectors.Vector) return String
   is
      S : SU.Unbounded_String;
      T : constant Tally := Tally_Of (Results);
      NL : constant Character := Ada.Characters.Latin_1.LF;
   begin
      for R of Results loop
         SU.Append (S, SU.To_String (R.Id) & ": " & Image (R.Cat));
         if R.Cat = Mismatched then
            SU.Append (S, " (" & Img (Natural (R.Diffs.Length))
                          & " diffs)");
         elsif R.Cat = Infrastructure and then SU.Length (R.Detail) > 0 then
            SU.Append (S, " (" & SU.To_String (R.Detail) & ")");
         end if;
         SU.Append (S, NL);
      end loop;
      SU.Append (S, "matched=" & Img (T.Matched)
                    & " mismatched=" & Img (T.Mismatched)
                    & " infrastructure=" & Img (T.Infrastructure) & NL);
      return SU.To_String (S);
   end Render_Summary;

end Differential.Report;
