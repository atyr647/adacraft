--  Lab-only capture orchestration: Run_Scenario with fresh TCP per
--  target per scenario, delegating I/O to Differential.Capture.Wire.
--  No socket/framing code here; no payload storage.

with Ada.Containers.Vectors;
with Interfaces;
with Adacraft.Protocol;
with Adacraft.Protocol.State;
with Differential.Args;
with Differential.Transcript;

package Differential.Capture is
   pragma Elaborate_Body;

   use type Interfaces.Unsigned_8;

   package Octet_Vectors is new Ada.Containers.Vectors
     (Index_Type   => Positive,
      Element_Type => Adacraft.Protocol.Octet);

   type Script_Step is record
      Dir  : Adacraft.Protocol.State.Packet_Direction :=
        Adacraft.Protocol.State.Serverbound;
      Id   : Adacraft.Protocol.State.Packet_Id :=
        Adacraft.Protocol.State.Packet_Id (0);
      Data : Octet_Vectors.Vector;
   end record;

   package Script_Vectors is new Ada.Containers.Vectors
     (Index_Type   => Positive,
      Element_Type => Script_Step);

   subtype Script is Script_Vectors.Vector;

   --  Stub provider until the corpus loader (#119) lands.
   type Empty_Provider is null record;

   function Empty_Script return Script;

   function Scenario_Count return Natural;

   function Count (P : Empty_Provider) return Natural;

   function To_Octets (Data : Octet_Vectors.Vector)
     return Adacraft.Protocol.Octets;

   function Run_Scenario
     (Endpoint : Args.Endpoint;
      Steps    : Script) return Transcript.Target_Result;

end Differential.Capture;
