with Adacraft.Protocol.State;
with Ada.Containers;
with Ada.Containers.Bounded_Vectors;

package Differential.Transcript is

   type Direction_T is (Serverbound, Clientbound);

   type Terminal_Outcome is
     (Completed, Peer_Closed, Protocol_Error, Timeout, Connect_Failed);

   type Transcript_Entry is record
      State     : Adacraft.Protocol.State.Connection_State;
      Dir       : Direction_T;
      Packet_Id : Natural;
   end record;

   Max_Entries : constant Ada.Containers.Count_Type := 256;

   package Entry_Vectors is new Ada.Containers.Bounded_Vectors
     (Index_Type   => Positive,
      Element_Type => Transcript_Entry);

   type Transcript is record
      Entries : Entry_Vectors.Vector (Capacity => Max_Entries);
      Outcome : Terminal_Outcome := Completed;
   end record;

   function Empty_Transcript
     (Outcome : Terminal_Outcome := Completed) return Transcript;

   procedure Append (T : in out Transcript; E : Transcript_Entry);

   procedure Set_Outcome (T : in out Transcript; O : Terminal_Outcome);

   function Length (T : Transcript) return Natural;

   function Get (T : Transcript; Index : Positive) return Transcript_Entry;

   function Get_Outcome (T : Transcript) return Terminal_Outcome;

end Differential.Transcript;
