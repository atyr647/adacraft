--  Lab-only deterministic report rendering body. No I/O, no clock,
--  no addresses/ports/timing; output is a pure function of inputs.
with Ada.Characters.Latin_1;
with Adacraft.Protocol.State;

package body Differential.Report is

   function Trim_Left (S : String) return String is
      First : Natural := S'First;
   begin
      while First <= S'Last and then (S (First) = ' ' or else S (First) = ASCII.HT) loop
         First := First + 1;
      end loop;
      if First > S'Last then
         return "";
      end if;
      return S (First .. S'Last);
   end Trim_Left;

   function Nat_Image (Value : Natural) return String is
   begin
      return Trim_Left (Natural'Image (Value));
   end Nat_Image;

   function Entry_Image
     (Item : Differential.Transcript.Transcript_Entry) return String
   is
      use Adacraft.Protocol.State;
      State_Text : constant String :=
        Trim_Left (Connection_State'Image (Item.State));
      Dir_Text : constant String :=
        Trim_Left (Packet_Direction'Image (Item.Direction));
      Id_Text : constant String :=
        Trim_Left (Packet_Id'Image (Item.Packet_Id));
   begin
      return State_Text & "/" & Dir_Text & "/" & Id_Text;
   end Entry_Image;

   function Outcome_Image
     (Value : Differential.Transcript.Terminal_Outcome) return String
   is
   begin
      return Trim_Left
        (Differential.Transcript.Terminal_Outcome'Image (Value));
   end Outcome_Image;

   function Verdict_Detail (V : Differential.Compare.Verdict) return String is
      use Differential.Compare;
   begin
      case V.Difference is
         when No_Difference =>
            return "";
         when First_Diff_Index =>
            return " first-diff=" & Nat_Image (V.Index)
              & " left=" & Entry_Image (V.Left_Entry)
              & " right=" & Entry_Image (V.Right_Entry);
         when Length_Mismatch =>
            return " length-mismatch"
              & " left=" & Nat_Image (V.Left_Len)
              & " right=" & Nat_Image (V.Right_Len);
         when Outcome_Mismatch =>
            return " outcome-mismatch"
              & " left=" & Outcome_Image (V.Left_Out)
              & " right=" & Outcome_Image (V.Right_Out);
      end case;
   end Verdict_Detail;

   function Render (Results : Result_Array) return String is
      use Differential.Compare;
      LF    : constant Character := Ada.Characters.Latin_1.LF;
      Text  : Unbounded_String := Null_Unbounded_String;
      Total : Natural := 0;
      Match : Natural := 0;
   begin
      for I in Results'Range loop
         Total := Total + 1;
         declare
            Name : constant String := To_String (Results (I).Name);
         begin
            if Results (I).Outcome.Kind = Differential.Compare.Match then
               Match := Match + 1;
               Append (Text, Name & ": MATCH" & LF);
            else
               Append
                 (Text,
                  Name & ": DIVERGE"
                  & Verdict_Detail (Results (I).Outcome) & LF);
            end if;
         end;
      end loop;
      Append
        (Text,
         "total=" & Nat_Image (Total)
         & " match=" & Nat_Image (Match)
         & " diverge=" & Nat_Image (Total - Match) & LF);
      return To_String (Text);
   end Render;

end Differential.Report;
