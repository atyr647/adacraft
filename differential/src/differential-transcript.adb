package body Differential.Transcript is

   procedure Clear (T : out Transcript) is
   begin
      T.Length := 0;
      T.Outcome := Completed;
   end Clear;

   procedure Append (T : in out Transcript; Item : Transcript_Entry) is
   begin
      if T.Length < Max_Entries then
         T.Length := T.Length + 1;
         T.Entries (T.Length) := Item;
      end if;
   end Append;

   function Get_Entry (T : Transcript; Index : Positive) return Transcript_Entry is
   begin
      return T.Entries (Index);
   end Get_Entry;

   function Get_Length (T : Transcript) return Natural is
   begin
      return T.Length;
   end Get_Length;

   function Get_Outcome (T : Transcript) return Terminal_Outcome is
   begin
      return T.Outcome;
   end Get_Outcome;

   procedure Set_Outcome (T : in out Transcript; Value : Terminal_Outcome) is
   begin
      T.Outcome := Value;
   end Set_Outcome;

end Differential.Transcript;
