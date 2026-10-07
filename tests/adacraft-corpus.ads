with Ada.Containers.Vectors;
with Ada.Strings.Unbounded;
with Interfaces;
with Adacraft.Protocol.State;

package Adacraft.Corpus is

   Max_Steps     : constant := 1024;
   Max_File_Size : constant := 1_048_576;

   type Category is
     (Handshake, Status, Login, Authentication, Encryption, Configuration,
      Known_Packs, Registries, Play, Spawn, Movement, Block_Interaction,
      Inventory, Commands, Disconnect);

   type Provenance is (Hand_Authored, Captured, Regression);
   type Direction is (Serverbound, Clientbound);
   type Outcome is (Accepted, Rejected, Incomplete);

   use type Interfaces.Unsigned_8;

   package Byte_Vectors is new Ada.Containers.Vectors
     (Positive, Interfaces.Unsigned_8);

   type Step is record
      Line                   : Natural := 0;
      Dir                    : Direction := Serverbound;
      Input                  : Byte_Vectors.Vector;
      Expected               : Outcome := Rejected;
      Has_Packet_Id          : Boolean := False;
      Packet_Id              : Natural := 0;
      Has_State_After        : Boolean := False;
      State_After            : Adacraft.Protocol.State.Connection_State :=
        Adacraft.Protocol.State.Handshake;
      Canonical              : Boolean := False;
      Has_Rejection_Category : Boolean := False;
      Rejection_Category     : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   package Step_Vectors is new Ada.Containers.Vectors (Positive, Step);

   type Scenario is record
      Path             : Ada.Strings.Unbounded.Unbounded_String;
      Id               : Ada.Strings.Unbounded.Unbounded_String;
      Id_Line          : Natural := 1;
      Title            : Ada.Strings.Unbounded.Unbounded_String;
      Description      : Ada.Strings.Unbounded.Unbounded_String;
      Cat              : Category := Handshake;
      Protocol_Version : Natural := 0;
      Prov             : Provenance := Hand_Authored;
      Initial_State    : Adacraft.Protocol.State.Connection_State :=
        Adacraft.Protocol.State.Handshake;
      Has_Final_State  : Boolean := False;
      Final_State      : Adacraft.Protocol.State.Connection_State :=
        Adacraft.Protocol.State.Handshake;
      Has_Reference    : Boolean := False;
      Reference        : Ada.Strings.Unbounded.Unbounded_String;
      Steps            : Step_Vectors.Vector;
   end record;

   type Error is record
      Path   : Ada.Strings.Unbounded.Unbounded_String;
      Line   : Natural := 0;
      Reason : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   package Error_Vectors is new Ada.Containers.Vectors (Positive, Error);
   package Scenario_Vectors is new Ada.Containers.Vectors (Positive, Scenario);
   package Name_Vectors is new Ada.Containers.Vectors
     (Positive, Ada.Strings.Unbounded.Unbounded_String,
      "=" => Ada.Strings.Unbounded."=");

end Adacraft.Corpus;
