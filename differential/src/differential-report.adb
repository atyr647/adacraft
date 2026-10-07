with Ada.Strings;
with Ada.Strings.Fixed;
with Ada.Text_IO;

package body Differential.Report is

   function Img (N : Natural) return String
   is (Ada.Strings.Fixed.Trim (Natural'Image (N), Ada.Strings.Both));

   procedure Put (Line : String) is
   begin
      Ada.Text_IO.Put_Line (Line);
   end Put;

   procedure Pass (Name : String) is
   begin
      Put ("PASS " & Name);
   end Pass;

   procedure Diff (Name : String; Oracle, Subject : Compare.Sequence) is
      I : constant Natural := Compare.First_Diff (Oracle, Subject);
   begin
      Put ("DIFF " & Name);
      if I > 0 then
         Put ("  first difference at index " & Img (I));
         Put ("  oracle:  " & Compare.Describe (Oracle, I));
         Put ("  subject: " & Compare.Describe (Subject, I));
      end if;
   end Diff;

   procedure Error (Name : String; Reason : String) is
   begin
      Put ("ERROR " & Name & ": " & Reason);
   end Error;

   procedure Summary (Passed, Differed, Errored : Natural) is
   begin
      Put ("SUMMARY pass=" & Img (Passed) & " diff=" & Img (Differed)
           & " error=" & Img (Errored));
   end Summary;

end Differential.Report;
