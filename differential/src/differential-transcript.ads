with Adacraft.Protocol.State;

package Differential.Transcript is

   type Direction is (C_To_S, S_To_C);

   type Terminal_Outcome is
     (Completed, Closed_By_Peer, Timeout, Protocol_Error);

   type Transcript_Entry is record
      State     : Adacraft.Protocol.State.Connection_State;
      Dir       : Direction;
      Packet_ID : Adacraft.Protocol.State.Packet_Id;
   end record;

   --  Transcript storage bound only; all framing/VarInt limits are
   --  reused from the shipped Adacraft.Protocol units, none defined here.
   Max_Entries : constant Positive := 1_024;

   type Entry_Array is array (1 .. Max_Entries) of Transcript_Entry;

   type Transcript is record
      Entries : Entry_Array;
      Length  : Natural := 0;
      Outcome : Terminal_Outcome := Completed;
   end record;

   procedure Clear (T : out Transcript);

   procedure Append (T : in out Transcript; Item : Transcript_Entry);

   function Get_Entry (T : Transcript; Index : Positive) return Transcript_Entry;

   function Get_Length (T : Transcript) return Natural;

   function Get_Outcome (T : Transcript) return Terminal_Outcome;

   procedure Set_Outcome (T : in out Transcript; Value : Terminal_Outcome);

end Differential.Transcript;
