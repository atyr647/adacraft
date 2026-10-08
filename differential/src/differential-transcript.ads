--  Lab-only transcript model for the differential driver.
--  Ordered Transcript_Entry(state,direction,packet ID) sequence plus one
--  closed terminal outcome. Payloads are never stored.
with Adacraft.Protocol.State;
with Ada.Containers.Vectors;

package Differential.Transcript is

   type Transcript_Entry is record
      State     : Adacraft.Protocol.State.Connection_State;
      Direction : Adacraft.Protocol.State.Packet_Direction;
      Packet_Id : Adacraft.Protocol.State.Packet_Id;
   end record;

   package Entry_Vectors is new Ada.Containers.Vectors
     (Index_Type   => Natural,
      Element_Type => Transcript_Entry);

   type Terminal_Outcome is
     (Completed,
      Peer_Closed,
      Timeout,
      Malformed_Frame_Rejected,
      State_Machine_Rejected,
      Connection_Failure);

   type Transcript is record
      Entries : Entry_Vectors.Vector;
      Outcome : Terminal_Outcome := Completed;
   end record;

   function Length (T : Transcript) return Natural;

   function Element (T : Transcript; Index : Positive) return Transcript_Entry;

   procedure Append (T : in out Transcript; Item : Transcript_Entry);

   procedure Set_Outcome (T : in out Transcript; Value : Terminal_Outcome);

   function Get_Outcome (T : Transcript) return Terminal_Outcome;

   procedure Clear (T : in out Transcript);

end Differential.Transcript;
