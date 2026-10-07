--  Private, read-only adapter for the #119 Golden Corpus format.
--
--  This package is one temporary seam. #119 owns the corpus format and will
--  provide the loader the driver should call; until that loader is available
--  the differential driver reads the format itself so that it can be built
--  and tested on its own. It only reads the format: it does not author or
--  extend it, and it changes nothing under src/protocol/. Delete this
--  package once the #119 loader lands.
--
--  Self-contained on purpose: it does not depend on the test tree.

with Ada.Containers.Vectors;
with Ada.Strings.Unbounded;
with Interfaces;
with Adacraft.Protocol.State;

package Differential.Corpus is

   subtype Unbounded_String is Ada.Strings.Unbounded.Unbounded_String;

   Max_Steps     : constant := 1024;
   Max_File_Size : constant := 1_048_576;

   type Direction is (Serverbound, Clientbound);
   type Outcome is (Accepted, Rejected, Incomplete);

   package Byte_Vectors is new Ada.Containers.Vectors
     (Positive, Interfaces.Unsigned_8);

   --  One corpus step. Raw holds the bytes of the step's input field, the
   --  complete frame including its length prefix, exactly as the corpus
   --  spells it. A step may name a packet id instead of spelling it out in
   --  the bytes; when it does, Has_Packet_Id is True.
   type Step is record
      Line            : Natural := 0;
      Dir             : Direction := Serverbound;
      Raw             : Byte_Vectors.Vector;
      Expected        : Outcome := Accepted;
      Has_Packet_Id   : Boolean := False;
      Packet_Id       : Natural := 0;
      Has_State_After : Boolean := False;
      State_After     : Adacraft.Protocol.State.Connection_State :=
        Adacraft.Protocol.State.Handshake;
   end record;

   package Step_Vectors is new Ada.Containers.Vectors (Positive, Step);

   --  Name is the scenario's id. The order of a Load is the file-name order
   --  of the corpus directory, so a run is reproducible.
   type Scenario is record
      Path      : Unbounded_String;
      Name      : Unbounded_String;
      Name_Line : Natural := 1;
      Initial   : Adacraft.Protocol.State.Connection_State :=
        Adacraft.Protocol.State.Handshake;
      Steps     : Step_Vectors.Vector;
   end record;

   package Scenario_Vectors is new Ada.Containers.Vectors
     (Positive, Scenario);

   --  Corpus-level problems are returned as data, each with its own kind, so
   --  a caller can tell a bad format from an unreadable file.
   type Error_Kind is
     (Unreadable_Directory,
      File_Too_Large,
      Unreadable_File,
      Empty_File,
      Bad_Format_Version,
      Malformed_Line,
      Invalid_Key,
      Duplicate_Key,
      Missing_Field,
      Invalid_Value,
      Bad_Hex,
      Too_Many_Steps,
      No_Steps,
      Duplicate_Name,
      Other);

   type Error is record
      Kind   : Error_Kind := Other;
      Path   : Unbounded_String;
      Line   : Natural := 0;
      Reason : Unbounded_String;
   end record;

   package Error_Vectors is new Ada.Containers.Vectors (Positive, Error);

   function Format_Error (E : Error) return String;

   --  Parses one scenario out of corpus text. Returns True when the call
   --  appended no error. Path is used only in error records.
   function Parse
     (Text   : String;
      Path   : String;
      S      : out Scenario;
      Errors : in out Error_Vectors.Vector) return Boolean;

   --  Reads every non-template "*.scenario" file of Dir, in file-name order,
   --  and returns the scenarios that parsed cleanly, in that order. Names
   --  starting with '_' are templates and are ignored.
   procedure Load
     (Dir       : String;
      Scenarios : out Scenario_Vectors.Vector;
      Errors    : out Error_Vectors.Vector);

end Differential.Corpus;
