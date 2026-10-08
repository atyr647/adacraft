with Ada.Text_IO;
with Differential.Compare;

package body Differential.Report is

   function Trim_Left (S : String) return String is
      F : Positive := S'First;
   begin
      while F <= S'Last and then S (F) = ' ' loop
         F := F + 1;
      end loop;
      if F > S'Last then
         return "";
      end if;
      return S (F .. S'Last);
   end Trim_Left;

   function Entry_Image
     (E : Differential.Transcript.Transcript_Entry) return String
   is
      use Differential.Transcript;
   begin
      return "("
        & Direction_T'Image (E.Dir)
        & ","
        & Trim_Left (Direction_T'Pos (E.Dir)'Image)
        & ";"
        & E.State'Image
        & ";"
        & Trim_Left (Natural'Image (E.Packet_Id))
        & ")";
   end Entry_Image;

   function Outcome_Image
     (O : Differential.Transcript.Terminal_Outcome) return String
   is
   begin
      return Differential.Transcript.Terminal_Outcome'Image (O);
   end Outcome_Image;

   function Side_Image
     (T : Differential.Transcript.Transcript;
      Index : Natural) return String
   is
      use Differential.Transcript;
   begin
      if Index >= 1 and then Index <= Length (T) then
         return Entry_Image (Get (T, Index));
      else
         return Outcome_Image (Get_Outcome (T));
      end if;
   end Side_Image;

   procedure Put_Scenario
     (Name : String;
      Oracle : Differential.Transcript.Transcript;
      Candidate : Differential.Transcript.Transcript)
   is
      use Ada.Text_IO;
      use Differential.Transcript;
      use type Differential.Compare.Verdict;
      V : constant Differential.Compare.Verdict :=
        Differential.Compare.Compare (Oracle, Candidate);
   begin
      if V = Differential.Compare.Match then
         Put_Line (Name & " MATCH");
      else
         declare
            F : constant Natural :=
              Differential.Compare.First_Difference (Oracle, Candidate);
         begin
            Put_Line (Name
              & " DIVERGE first="
              & Trim_Left (Natural'Image (F))
              & " oracle="
              & Side_Image (Oracle, F)
              & " candidate="
              & Side_Image (Candidate, F));
         end;
      end if;
   end Put_Scenario;

   procedure Put_Summary
     (Total : Natural; Matched : Natural; Diverged : Natural)
   is
      use Ada.Text_IO;
   begin
      Put_Line ("summary total="
        & Trim_Left (Natural'Image (Total))
        & " match="
        & Trim_Left (Natural'Image (Matched))
        & " diverge="
        & Trim_Left (Natural'Image (Diverged)));
   end Put_Summary;

end Differential.Report;
