with Ada.Characters.Handling;
with Ada.Strings;
with Ada.Strings.Fixed;

package body Differential.Obs is

   use Adacraft.Protocol.State;

   function Low (S : String) return String
   is (Ada.Characters.Handling.To_Lower (S));

   function Img (Id : Packet_Id) return String
   is (Ada.Strings.Fixed.Trim (Packet_Id'Image (Id), Ada.Strings.Both));

   function To_String (O : Observation) return String is
   begin
      case O.Kind is
         when Packet_Obs =>
            return "packet state=" & Low (Connection_State'Image (O.State))
              & " dir=" & Low (Packet_Direction'Image (O.Direction))
              & " id=" & Img (O.Id);
         when Connect_Failed =>
            return "connect-failed";
         when Closed_By_Peer =>
            return "closed-by-peer";
         when Receive_Timeout =>
            return "receive-timeout";
         when Malformed =>
            return "malformed reason="
              & Low (Malformed_Reason'Image (O.Reason));
         when Invalid_In_State =>
            return "invalid-in-state state="
              & Low (Connection_State'Image (O.Bad_State))
              & " id=" & Img (O.Bad_Id);
      end case;
   end To_String;

end Differential.Obs;
