with Adacraft.Protocol.State;
with Ada.Containers.Vectors;

--  Lab-only transcript model. Ordered sequence of packet descriptors
--  plus exactly one terminal outcome kind per target and scenario.
--  Payload is never recorded.

package Differential.Transcript is

   type Direction_Kind is (Serverbound, Clientbound);

   type Terminal_Outcome is
     (Completed,
      Peer_Closed,
      Timeout,
      Protocol_Error,
      Connect_Failure);

   type Transcript_Entry is record
      State     : Adacraft.Protocol.State.Connection_State;
      Direction : Direction_Kind;
      Packet_Id : Natural;
   end record;

   package Transcript_Vectors is new Ada.Containers.Vectors
     (Index_Type   => Natural,
      Element_Type => Transcript_Entry);

   subtype Transcript_Vector is Transcript_Vectors.Vector;

   type Transcript is record
      Entries : Transcript_Vector;
      Outcome : Terminal_Outcome := Completed;
   end record;

   function Length (T : Transcript) return Natural;

   procedure Append (T : in out Transcript; Item : Transcript_Entry);

   function Element_At
     (T : Transcript; Index : Natural) return Transcript_Entry
   with Pre => Index < Length (T);

   procedure Set_Outcome (T : in out Transcript; Value : Terminal_Outcome);

   procedure Clear (T : in out Transcript);

   function Direction_Image (D : Direction_Kind) return String;

   function Outcome_Image (O : Terminal_Outcome) return String;

   function State_Image
     (S : Adacraft.Protocol.State.Connection_State) return String;

   function Transcript_Entry_Image (Item : Transcript_Entry) return String;

end Differential.Transcript;
