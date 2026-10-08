with Ada.Streams;
with Differential.Args;
with Differential.Transcript;

package Differential.Capture is

   --  Lab-only network capture.  Sockets via GNAT.Sockets only.
   --  Framing/decoding/state only through shipped units
   --  (Frame Encode, Frame Decode, Ingress reassembly, Varnum, State).
   --  No driver-owned VarInt/length-prefix/framing codec.
   --  Fresh TCP connection per scenario per target.

   Read_Timeout : constant Duration := 2.0;

   Env_Error : exception;
   --  Raised on connect/send/select failure (usage/env, exit 2).

   Max_Body_Length    : constant := 4_096;
   Max_Bodies         : constant := 64;
   Max_Scenario_Count : constant := 256;

   subtype Body_Length is Natural range 0 .. Max_Body_Length;
   subtype Body_Index is Positive range 1 .. Max_Bodies;

   type Body_Data is array (1 .. Max_Body_Length) of Ada.Streams.Stream_Element;

   type Serverbound_Body is record
      Length : Body_Length := 0;
      Data   : Body_Data := (others => 0);
   end record;

   type Body_List is array (Body_Index) of Serverbound_Body;

   --  Abstract scenario iterator.  Concrete #119 corpus binding is
   --  deferred (Q1); a later task supplies a concrete child type.
   type Scenario_Descriptor is record
      Name       : String (1 .. Differential.Transcript.Max_Name_Length) :=
        (others => ' ');
      Name_Len   : Differential.Transcript.Name_Length_Range := 0;
      Body_Count : Natural range 0 .. Max_Bodies := 0;
      Bodies     : Body_List;
   end record;

   function Scenario_Name (S : Scenario_Descriptor) return String;

   type Provider is abstract tagged limited null record;

   function Count (P : Provider) return Natural is abstract;

   procedure Get
     (P    : in out Provider;
      Index : Positive;
      Item  : out Scenario_Descriptor) is abstract;

   type Result_Array is
     array (Positive range <>) of Differential.Transcript.Scenario_Result;

   --  Capture one scenario against one endpoint (fresh TCP connection).
   --  Raises Env_Error on connect failure (not a divergence).
   procedure Capture_One
     (Target   : Differential.Args.Endpoint;
      Scenario : Scenario_Descriptor;
      Result   : out Differential.Transcript.Scenario_Result);

   --  Run every scenario in provider order, oracle then candidate.
   --  Raises Env_Error on any connect failure (outranks divergence).
   procedure Run_All
     (Oracle    : Differential.Args.Endpoint;
      Candidate : Differential.Args.Endpoint;
      Source    : in out Provider'Class;
      Oracle_Out    : out Result_Array;
      Candidate_Out : out Result_Array;
      Total         : out Natural);

end Differential.Capture;
