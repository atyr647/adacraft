with Ada.Text_IO;

package body Differential.Report is

   function Trim_Image (Value : Natural) return String is
      Img : constant String := Natural'Image (Value);
   begin
      return Img (Img'First + 1 .. Img'Last);
   end Trim_Image;

   function Render
     (Name    : String;
      Matched : Boolean;
      Detail  : String := "") return String
   is
   begin
      if Matched then
         if Detail = "" then
            return Name & " MATCH";
         else
            return Name & " MATCH " & Detail;
         end if;
      else
         if Detail = "" then
            return Name & " DIVERGE";
         else
            return Name & " DIVERGE " & Detail;
         end if;
      end if;
   end Render;

   function Render_Summary
     (Total    : Natural;
      Matched  : Natural;
      Diverged : Natural) return String
   is
   begin
      return "total=" & Trim_Image (Total)
        & " match=" & Trim_Image (Matched)
        & " diverge=" & Trim_Image (Diverged);
   end Render_Summary;

   function First_Diff_Detail
     (Oracle           : Differential.Transcript.Transcript;
      Candidate        : Differential.Transcript.Transcript;
      First_Index      : Natural;
      Outcome_Mismatch : Boolean) return String
   is
      use Differential.Transcript;
      OL : constant Natural := Get_Length (Oracle);
      CL : constant Natural := Get_Length (Candidate);
      OO : constant Terminal_Outcome := Get_Outcome (Oracle);
      CO : constant Terminal_Outcome := Get_Outcome (Candidate);
   begin
      if Outcome_Mismatch then
         return "first diff outcome oracle=" & OO'Image
           & " candidate=" & CO'Image;
      end if;
      if First_Index = 0 then
         return "first diff length oracle=" & Trim_Image (OL)
           & " candidate=" & Trim_Image (CL);
      end if;
      if First_Index > OL or else First_Index > CL then
         return "first diff index=" & Trim_Image (First_Index)
           & " length oracle=" & Trim_Image (OL)
           & " candidate=" & Trim_Image (CL);
      end if;
      declare
         OE : constant Transcript_Entry := Get_Entry (Oracle, First_Index);
         CE : constant Transcript_Entry := Get_Entry (Candidate, First_Index);
      begin
         return "first diff index=" & Trim_Image (First_Index)
           & " oracle=(" & OE.State'Image & "," & OE.Dir'Image
           & "," & Trim_Image (Natural (OE.Packet_ID)) & ")"
           & " candidate=(" & CE.State'Image & "," & CE.Dir'Image
           & "," & Trim_Image (Natural (CE.Packet_ID)) & ")";
      end;
   end First_Diff_Detail;

   procedure Put_Report (Line : String) is
   begin
      Ada.Text_IO.Put_Line (Line);
   end Put_Report;

   procedure Put_Report
     (Name    : String;
      Matched : Boolean;
      Detail  : String := "")
   is
   begin
      Ada.Text_IO.Put_Line (Render (Name, Matched, Detail));
   end Put_Report;

   procedure Put_Summary
     (Total    : Natural;
      Matched  : Natural;
      Diverged : Natural)
   is
   begin
      Ada.Text_IO.Put_Line (Render_Summary (Total, Matched, Diverged));
   end Put_Summary;

end Differential.Report;
