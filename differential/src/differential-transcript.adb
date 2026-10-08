package body Differential.Transcript is

   function Length (T : Transcript) return Natural is
   begin
      return Natural (T.Entries.Length);
   end Length;

   procedure Append (T : in out Transcript; Item : Transcript_Entry) is
   begin
      T.Entries.Append (Item);
   end Append;

   function Element_At
     (T : Transcript; Index : Natural) return Transcript_Entry
   is
   begin
      return T.Entries.Element (Index);
   end Element_At;

   procedure Set_Outcome (T : in out Transcript; Value : Terminal_Outcome) is
   begin
      T.Outcome := Value;
   end Set_Outcome;

   procedure Clear (T : in out Transcript) is
   begin
      T.Entries.Clear;
      T.Outcome := Completed;
   end Clear;

   function Direction_Image (D : Direction_Kind) return String is
   begin
      case D is
         when Serverbound =>
            return "serverbound";
         when Clientbound =>
            return "clientbound";
      end case;
   end Direction_Image;

   function Outcome_Image (O : Terminal_Outcome) return String is
   begin
      case O is
         when Completed =>
            return "completed";
         when Peer_Closed =>
            return "peer-closed";
         when Timeout =>
            return "timeout";
         when Protocol_Error =>
            return "protocol-error";
         when Connect_Failure =>
            return "connect-failure";
      end case;
   end Outcome_Image;

   function State_Image
     (S : Adacraft.Protocol.State.Connection_State) return String
   is
   begin
      return Adacraft.Protocol.State.Connection_State'Image (S);
   end State_Image;

   function Transcript_Entry_Image (Item : Transcript_Entry) return String is
      Id_Image : constant String := Natural'Image (Item.Packet_Id);
   begin
      return
        State_Image (Item.State)
        & " " & Direction_Image (Item.Direction)
        & " " & Id_Image (Id_Image'First + 1 .. Id_Image'Last);
   end Transcript_Entry_Image;

end Differential.Transcript;
