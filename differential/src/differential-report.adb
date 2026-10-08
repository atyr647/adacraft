with Ada.Text_IO;
with Adacraft.Protocol.State;

package body Differential.Report is

   function Strip (S : String) return String is
      First : Positive := S'First;
   begin
      while First <= S'Last and then S (First) = ' ' loop
         First := First + 1;
      end loop;
      if First > S'Last then
         return "0";
      end if;
      return S (First .. S'Last);
   end Strip;

   function Nat_Image (N : Natural) return String is
   begin
      return Strip (Natural'Image (N));
   end Nat_Image;

   function Id_Image
     (Id : Adacraft.Protocol.State.Packet_Id) return String
   is
   begin
      return Strip (Adacraft.Protocol.State.Packet_Id'Image (Id));
   end Id_Image;

   function Image_Of (E : Transcript.Transcript_Entry) return String is
   begin
      return
        Adacraft.Protocol.State.Connection_State'Image (E.State)
        & "/"
        & Adacraft.Protocol.State.Packet_Direction'Image (E.Direction)
        & "/"
        & Id_Image (E.Packet_Id);
   end Image_Of;

   function Image_Of (O : Transcript.Terminal_Outcome) return String is
   begin
      return Transcript.Terminal_Outcome'Image (O);
   end Image_Of;

   procedure Put_Verdict
     (Name    : in String;
      Verdict : in Compare.Verdict;
      Detail  : in Compare.Comparison_Result)
   is
      use type Compare.Verdict;
      use type Compare.Divergence_Kind;
   begin
      if Verdict = Compare.MATCH then
         Ada.Text_IO.Put_Line (Name & ": MATCH");
         return;
      end if;
      if Detail.Kind = Compare.Outcome_Difference then
         Ada.Text_IO.Put_Line
           (Name & ": DIVERGE outcome mismatch");
      elsif Detail.Kind = Compare.Length_Mismatch then
         Ada.Text_IO.Put_Line
           (Name & ": DIVERGE length at"
            & " " & Nat_Image (Detail.First_Index)
            & " oracle=" & Image_Of (Detail.Oracle_Entry)
            & " candidate=" & Image_Of (Detail.Candidate_Entry));
      else
         Ada.Text_IO.Put_Line
           (Name & ": DIVERGE at"
            & " " & Nat_Image (Detail.First_Index)
            & " oracle=" & Image_Of (Detail.Oracle_Entry)
            & " candidate=" & Image_Of (Detail.Candidate_Entry));
      end if;
   end Put_Verdict;

   procedure Put_Summary
     (Total    : in Natural;
      Matched  : in Natural;
      Diverged : in Natural)
   is
   begin
      Ada.Text_IO.Put_Line
        ("summary: total=" & Nat_Image (Total)
         & " match=" & Nat_Image (Matched)
         & " diverge=" & Nat_Image (Diverged));
   end Put_Summary;

end Differential.Report;
