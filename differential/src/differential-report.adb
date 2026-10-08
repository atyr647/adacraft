with Ada.Strings.Unbounded;

package body Differential.Report is

   use Ada.Strings.Unbounded;

   function Make_Result
     (Name   : String;
      Result : Compare.Comparison_Result) return Named_Result
   is
   begin
      return (Name   => To_Unbounded_String (Name),
              Result => Result);
   end Make_Result;

   function Scenario_Line (Item : Named_Result) return String is
      Name : constant String := To_String (Item.Name);
   begin
      if Item.Result.Outcome_Verdict = Compare.Match then
         return "MATCH " & Name;
      end if;
      return "DIVERGE " & Name & " " & Compare.First_Detail (Item.Result);
   end Scenario_Line;

   function Nat_Image (N : Natural) return String is
      Img : constant String := Natural'Image (N);
   begin
      return Img (Img'First + 1 .. Img'Last);
   end Nat_Image;

   function Summary_Line
     (Total    : Natural;
      Matched  : Natural;
      Diverged : Natural) return String
   is
   begin
      return "total=" & Nat_Image (Total)
        & " match=" & Nat_Image (Matched)
        & " diverge=" & Nat_Image (Diverged);
   end Summary_Line;

end Differential.Report;
