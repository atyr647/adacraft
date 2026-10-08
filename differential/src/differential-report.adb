with Ada.Strings.Unbounded;
with Differential.Transcript;

package body Differential.Report is
   function Natural_Text (Value : Natural) return String is
      Image : constant String := Natural'Image (Value);
   begin
      return Image (Image'First + 1 .. Image'Last);
   end Natural_Text;

   function Difference_Text
     (Verdict : Differential.Compare.Verdict) return String
   is
   begin
      case Verdict.Difference is
         when Differential.Compare.No_Difference =>
            return "unspecified";
         when Differential.Compare.State_Difference =>
            return "entry " & Natural_Text (Verdict.Entry_Index) & " state";
         when Differential.Compare.Direction_Difference =>
            return "entry " & Natural_Text (Verdict.Entry_Index) & " direction";
         when Differential.Compare.Packet_Id_Difference =>
            return "entry " & Natural_Text (Verdict.Entry_Index) & " packet-id";
         when Differential.Compare.Length_Difference =>
            return "length at entry " & Natural_Text (Verdict.Entry_Index);
         when Differential.Compare.Outcome_Difference =>
            return "terminal outcome";
      end case;
   end Difference_Text;

   function Format
     (Scenarios : Scenario_Result_Vectors.Vector) return String
   is
      use Ada.Strings.Unbounded;

      Output   : Unbounded_String;
      Matches  : Natural := 0;
      Diverges : Natural := 0;
   begin
      for Item of Scenarios loop
         Append (Output, To_String (Item.Name));
         if Item.Verdict.Is_Match then
            Append (Output, ": MATCH");
            Matches := Matches + 1;
         else
            Append (Output, ": DIVERGE " & Difference_Text (Item.Verdict));
            Diverges := Diverges + 1;
         end if;
         Append (Output, ASCII.LF);
      end loop;

      Append
        (Output,
         "total=" & Natural_Text (Natural (Scenarios.Length))
         & " match=" & Natural_Text (Matches)
         & " diverge=" & Natural_Text (Diverges));
      return To_String (Output);
   end Format;
end Differential.Report;
