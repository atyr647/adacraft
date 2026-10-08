with Adacraft.Protocol.State;

package Differential.Transcript is

   --  Ordered transcript of (state, direction, packet id) observations.
   --  No payload is stored.  Bounded arrays only; no Ada.Containers use.

   Max_Name_Length : constant := 128;
   Max_Entries     : constant := 1_024;

   subtype Name_Length_Range is Natural range 0 .. Max_Name_Length;
   subtype Entry_Count is Natural range 0 .. Max_Entries;
   subtype Entry_Index is Positive range 1 .. Max_Entries;

   type Transcript_Entry is record
      State     : Adacraft.Protocol.State.Connection_State :=
        Adacraft.Protocol.State.Handshake;
      Direction : Adacraft.Protocol.State.Packet_Direction :=
        Adacraft.Protocol.State.Serverbound;
      Id        : Adacraft.Protocol.State.Packet_Id := 0;
   end record;

   type Entry_Array is array (Entry_Index) of Transcript_Entry;

   type Transcript is record
      Count   : Entry_Count := 0;
      Entries : Entry_Array;
   end record;

   type Scenario_Result is record
      Name_Len : Name_Length_Range := 0;
      Name     : String (1 .. Max_Name_Length) := (others => ' ');
      Entries  : Transcript;
      Outcome  : Differential.Outcome := Differential.Completed;
   end record;

   function Length (T : Transcript) return Entry_Count;

   function Get (T : Transcript; Index : Positive) return Transcript_Entry
     with Pre => Index >= 1 and then Index <= T.Count;

   procedure Clear (T : in out Transcript);

   procedure Append
     (T       : in out Transcript;
      Item    : Transcript_Entry;
      Success : out Boolean);

   function Name_Str (S : Scenario_Result) return String;

   procedure Set_Name (S : in out Scenario_Result; Name : String);

end Differential.Transcript;
