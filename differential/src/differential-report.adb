with Ada.Strings.Unbounded;
with Differential.Transcript;

package body Differential.Report is
   function Difference_Text
     (Verdict : Differential.Compare.Verdict) return String
   is
      use type Differential.Compare.Difference_Kind;
      use type Differential.Compare.Verdict;
   begin
      case Verdict.Difference is
         when Differential.Compare.No_Difference =>
            return "difference";
         when Differential.Compare.State_Difference =>
            return "entry" & Natural'Image (Verdict.Entry_Index) & " state";
         when Differential.Compare.Direction_Difference =>
            return "entry" & Natural'Image (Verdict.Entry_Index) & " direction";
         when Differential.Compare.Packet_Id_Difference =>
            return "entry" & Natural'Image (Verdict.Entry_Index) & " packet-id";
         when Differential.Compare.Length_Difference =>
            return "length at entry" & Natural'Image (Verdict.Entry_Index);
         when Differential.Compare.Outcome_Difference =>
            return "outcome";
      end case;
   end Difference_Text;

   function Format
     (Scenarios : Scenario_Result_Vectors.Vector) return String
   is
      use Ada.Strings.Unbounded;
      use type Differential.Compare.Verdict;
      use type Scenario_Result_Vectors.Vector;

      Output  : Unbounded_String;
      Matches : Natural := 0;
      Diverges : Natural := 0;
   begin
      for Item of Scenarios loop
         Append (Output, To_String (Item.Name));
         if Item.Verdict.Is_Match then
            Append (Output, ": MATCH");
            Matches := Matches + 1;
         else
            Append
              (Output,
               ": DIVERGE " & Difference_Text (Item.Verdict));
            if Item.Verdict.Difference =
              Differential.Compare.Outcome_Difference
            then
               Append
                 (Output,
                  " (" & Differential.Transcript.Terminal_Outcome'Image
                    (Item.Verdict.Difference'Enum_Rep) & ")");
            end if;
            Diverges := Diverges + 1;
         end if;
         Append (Output, ASCII.LF);
      end loop;

      Append
        (Output,
         "total=" & Natural'Image (Natural (Scenarios.Length))
         & " match=" & Natural'Image (Matches)
         & " diverge=" & Natural'Image (Diverges));
      return To_String (Output);
   end Format;
end Differential.Report;
