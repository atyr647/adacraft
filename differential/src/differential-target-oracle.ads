with Ada.Finalization;
with Ada.Strings.Unbounded;
with GNAT.Sockets;

--  Oracle adapter: runs the official server.jar as a subprocess per
--  scenario in a fresh temporary directory, driven through
--  Differential.Client (no second wire implementation).
package Differential.Target.Oracle is

   Required_Java_Major : constant := 25;
   Required_Protocol   : constant := 777;

   type Probe_Result is record
      Ready    : Boolean := False;
      Protocol : Natural := 0;
      Detail   : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   --  One bounded readiness probe of the status endpoint. Null in Config
   --  selects the default (Client-driven status exchange).
   type Probe_Func is access function
     (Port    : GNAT.Sockets.Port_Type;
      Timeout : Duration) return Probe_Result;

   type Config is record
      Java_Path     : Ada.Strings.Unbounded.Unbounded_String :=
        Ada.Strings.Unbounded.To_Unbounded_String ("java");
      Jar_Path      : Ada.Strings.Unbounded.Unbounded_String;
      Work_Root     : Ada.Strings.Unbounded.Unbounded_String;  --  "" = TMPDIR
      Ready_Timeout : Duration := 120.0;
      Probe         : Probe_Func := null;
   end record;

   type Oracle_Target is limited new Differential.Target.Target with record
      Cfg : Config;
   end record;

   overriding function Run_Scenario
     (T        : in out Oracle_Target;
      Scenario : Differential.Scenario.Projection;
      Timeout  : Duration) return Run_Result;

   --  The single place that decides the generated server files.
   function Properties (Port : GNAT.Sockets.Port_Type) return String;

   procedure Write_Server_Files
     (Dir : String; Port : GNAT.Sockets.Port_Type);

   --  Owns the server process; Finalize kills it (and its children), so
   --  teardown survives every exit path including exceptions.
   type Process_Owner is limited new Ada.Finalization.Limited_Controlled
     with private;

   procedure Start
     (Owner : in out Process_Owner;
      Java  : String;
      Jar   : String;
      Dir   : String;
      Log   : String;
      Ok    : out Boolean);

   procedure Stop (Owner : in out Process_Owner);

   function Is_Running (Owner : Process_Owner) return Boolean;

   overriding procedure Finalize (Owner : in out Process_Owner);

private

   type Process_Owner is limited new Ada.Finalization.Limited_Controlled
   with record
      Pid     : Integer := 0;
      Running : Boolean := False;
   end record;

end Differential.Target.Oracle;
