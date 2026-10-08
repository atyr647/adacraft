package body Differential.Transcript is

   function Length (T : Transcript) return Natural is
   begin
      return Natural (T.Entries.Length);
   end Length;

   function Element (T : Transcript; Index : Positive) return Transcript_Entry is
   begin
      return T.Entries.Element (Index - 1);
   end Element;

   procedure Append (T : in out Transcript; Item : Transcript_Entry) is
   begin
      T.Entries.Append (Item);
   end Append;

   procedure Set_Outcome (T : in out Transcript; Value : Terminal_Outcome) is
   begin
      T.Outcome := Value;
   end Set_Outcome;

   function Get_Outcome (T : Transcript) return Terminal_Outcome is
   begin
      return T.Outcome;
   end Get_Outcome;

   procedure Clear (T : in out Transcript) is
   begin
      T.Entries.Clear;
      T.Outcome := Completed;
   end Clear;

end Differential.Transcript;
