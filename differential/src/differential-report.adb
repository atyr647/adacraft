with Ada.Command_Line;
with Ada.Text_IO;
with Adacraft.Protocol.State;

package body Differential.Report is

   function Trim_Image (Value : Integer) return String is
      Raw : constant String := Integer'Image (Value);
   begin
      if Raw'Length > 0 and then Raw (Raw'First) = ' ' then
         return Raw (Raw'First + 1 .. Raw'Last);
      else
         return Raw;
      end if;
   end Trim_Image;

   function Nat_Image (Value : Natural) return String is
   begin
      return Trim_Image (Integer (Value));
   end Nat_Image;

   function Outcome_Image (Value : Differential.Outcome) return String is
   begin
      case Value is
         when Differential.Completed =>
            return "Completed";
         when Differential.Peer_Closed =>
            return "Peer_Closed";
         when Differential.Read_Timeout =>
            return "Read_Timeout";
         when Differential.Malformed_Frame =>
            return "Malformed_Frame";
         when Differential.Invalid_State_Or_Direction =>
            return "Invalid_State_Or_Direction";
      end case;
   end Outcome_Image;

   function Entry_Image
     (Item : Differential.Transcript.Transcript_Entry) return String
   is
      State_Txt : constant String :=
        Adacraft.Protocol.State.Connection_State'Image (Item.State);
      Dir_Txt   : constant String :=
        Adacraft.Protocol.State.Packet_Direction'Image (Item.Direction);
      Id_Txt    : constant String :=
        Trim_Image (Integer (Item.Id));
   begin
      return "(" & State_Txt & "," & Dir_Txt & "," & Id_Txt & ")";
   end Entry_Image;

   function Match_Line (Name : String) return String is
   begin
      return Name & " MATCH";
   end Match_Line;

   function Diverge_Line (Name : String; Detail : String) return String is
   begin
      if Detail'Length = 0 then
         return Name & " DIVERGE";
      else
         return Name & " DIVERGE " & Detail;
      end if;
   end Diverge_Line;

   function Summary_Line
     (Total    : Natural;
      Matched  : Natural;
      Diverged : Natural) return String
   is
   begin
      return "total=" & Nat_Image (Total)
        & " matched=" & Nat_Image (Matched)
        & " diverged=" & Nat_Image (Diverged);
   end Summary_Line;

   function Length_Detail
     (Expected_Length : Natural;
      Got_Length      : Natural;
      Index           : Natural) return String
   is
   begin
      return "length expected=" & Nat_Image (Expected_Length)
        & " got=" & Nat_Image (Got_Length)
        & " index=" & Nat_Image (Index);
   end Length_Detail;

   function Entry_Detail
     (Index           : Positive;
      Expected_Entry  : Differential.Transcript.Transcript_Entry;
      Got_Entry       : Differential.Transcript.Transcript_Entry) return String
   is
   begin
      return "index=" & Nat_Image (Index)
        & " expected=" & Entry_Image (Expected_Entry)
        & " got=" & Entry_Image (Got_Entry);
   end Entry_Detail;

   function Outcome_Detail
     (Expected : Differential.Outcome;
      Got      : Differential.Outcome) return String
   is
   begin
      return "outcome expected=" & Outcome_Image (Expected)
        & " got=" & Outcome_Image (Got);
   end Outcome_Detail;

   procedure Put_Match (Name : String) is
   begin
      Ada.Text_IO.Put_Line (Match_Line (Name));
   end Put_Match;

   procedure Put_Diverge (Name : String; Detail : String) is
   begin
      Ada.Text_IO.Put_Line (Diverge_Line (Name, Detail));
   end Put_Diverge;

   procedure Put_Summary
     (Total    : Natural;
      Matched  : Natural;
      Diverged : Natural)
   is
   begin
      Ada.Text_IO.Put_Line (Summary_Line (Total, Matched, Diverged));
   end Put_Summary;

   function Exit_For
     (Diverged  : Natural;
      Env_Error : Boolean) return Differential.Exit_Code
   is
   begin
      if Env_Error then
         return Differential.Environment_Error;
      elsif Diverged > 0 then
         return Differential.Divergence;
      else
         return Differential.Success;
      end if;
   end Exit_For;

   procedure Apply_Exit
     (Diverged  : Natural;
      Env_Error : Boolean)
   is
      Code : constant Differential.Exit_Code :=
        Exit_For (Diverged, Env_Error);
   begin
      case Code is
         when Differential.Success =>
            Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Success);
         when Differential.Divergence =>
            Ada.Command_Line.Set_Exit_Status (1);
         when Differential.Environment_Error =>
            Ada.Command_Line.Set_Exit_Status (2);
      end case;
   end Apply_Exit;

end Differential.Report;
