with Adacraft.Protocol.State;

package body Differential.Transcript is

   function Length (T : Transcript) return Entry_Count is
   begin
      return T.Count;
   end Length;

   function Get (T : Transcript; Index : Positive) return Entry is
   begin
      return T.Entries (Index);
   end Get;

   procedure Clear (T : in out Transcript) is
   begin
      T.Count := 0;
   end Clear;

   procedure Append
     (T       : in out Transcript;
      Item    : Entry;
      Success : out Boolean)
   is
   begin
      if T.Count >= Max_Entries then
         Success := False;
         return;
      end if;
      T.Count := T.Count + 1;
      T.Entries (T.Count) := Item;
      Success := True;
   end Append;

   function Name_Str (S : Scenario_Result) return String is
   begin
      if S.Name_Len = 0 then
         return "";
      end if;
      return S.Name (1 .. S.Name_Len);
   end Name_Str;

   procedure Set_Name (S : in out Scenario_Result; Name : String) is
      N : constant Natural := Natural'Min (Name'Length, Max_Name_Length);
   begin
      S.Name_Len := N;
      S.Name := (others => ' ');
      if N > 0 then
         declare
            J : Natural := 0;
         begin
            for I in Name'Range loop
               exit when J >= N;
               J := J + 1;
               S.Name (J) := Name (I);
            end loop;
         end;
      end if;
   end Set_Name;

end Differential.Transcript;
