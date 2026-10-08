package body Differential.Transcript is

   function Empty_Transcript
     (Outcome : Terminal_Outcome := Completed) return Transcript
   is
      T : Transcript;
   begin
      T.Outcome := Outcome;
      return T;
   end Empty_Transcript;

   procedure Append (T : in out Transcript; E : Transcript_Entry) is
   begin
      if Natural (Entry_Vectors.Length (T.Entries)) < Max_Entries then
         Entry_Vectors.Append (T.Entries, E);
      end if;
   end Append;

   procedure Set_Outcome (T : in out Transcript; O : Terminal_Outcome) is
   begin
      T.Outcome := O;
   end Set_Outcome;

   function Length (T : Transcript) return Natural is
   begin
      return Natural (Entry_Vectors.Length (T.Entries));
   end Length;

   function Get (T : Transcript; Index : Positive) return Transcript_Entry is
   begin
      return Entry_Vectors.Element (T.Entries, Index);
   end Get;

   function Get_Outcome (T : Transcript) return Terminal_Outcome is
   begin
      return T.Outcome;
   end Get_Outcome;

end Differential.Transcript;
