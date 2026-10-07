with Ada.Containers.Vectors;
with Ada.Strings.Unbounded;
with GNAT.Sockets;
with Adacraft.Protocol;
with Adacraft.Protocol.State;
with Differential.Scenario;

--  The single client-side scenario executor: the only unit in the harness
--  that touches the wire. Both targets are driven through it, so they see
--  identical actions by construction.
package Differential.Client is

   package PS renames Adacraft.Protocol.State;

   Settle_Time : constant Duration := 0.02;

   type Recv_Status is (Data, Quiet, Closed);

   type Transport is limited interface;

   procedure Send
     (T    : in out Transport;
      Data : Adacraft.Protocol.Octets;
      Ok   : out Boolean) is abstract;

   --  Waits up to Wait for bytes; Last = 0 unless Status = Data.
   procedure Receive
     (T      : in out Transport;
      Wait   : Duration;
      Buffer : out Adacraft.Protocol.Octets;
      Last   : out Natural;
      Status : out Recv_Status) is abstract;

   type Received_Packet is record
      Id      : Natural := 0;
      Payload : Ada.Strings.Unbounded.Unbounded_String;  --  raw bytes
   end record;

   package Packet_Vectors is new Ada.Containers.Vectors
     (Positive, Received_Packet);

   type Step_Log is record
      Index          : Positive := 1;
      Sent           : Boolean := False;
      Closed         : Boolean := False;
      No_Data        : Boolean := True;
      Raw_Count      : Natural := 0;
      Framing_Error  : Boolean := False;
      State_After    : PS.Connection_State := PS.Handshake;
      Packets        : Packet_Vectors.Vector;
   end record;

   package Step_Log_Vectors is new Ada.Containers.Vectors
     (Positive, Step_Log);

   type Run_Output is record
      Transcript : Ada.Strings.Unbounded.Unbounded_String;
      Steps      : Step_Log_Vectors.Vector;
      Failed     : Boolean := False;
      Detail     : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   function Hex (Bytes : Adacraft.Protocol.Octets) return String;

   --  Drives Scenario over T. The transcript depends only on Scenario
   --  (never on what the target answered).
   procedure Execute
     (T        : in out Transport'Class;
      Scenario : Differential.Scenario.Projection;
      Output   : out Run_Output);

   --  Real TCP loopback transport.
   type Tcp_Transport is limited new Transport with private;

   procedure Connect
     (T    : in out Tcp_Transport;
      Port : GNAT.Sockets.Port_Type;
      Ok   : out Boolean);

   procedure Disconnect (T : in out Tcp_Transport);

   overriding procedure Send
     (T    : in out Tcp_Transport;
      Data : Adacraft.Protocol.Octets;
      Ok   : out Boolean);

   overriding procedure Receive
     (T      : in out Tcp_Transport;
      Wait   : Duration;
      Buffer : out Adacraft.Protocol.Octets;
      Last   : out Natural;
      Status : out Recv_Status);

private

   type Tcp_Transport is limited new Transport with record
      Sock      : GNAT.Sockets.Socket_Type := GNAT.Sockets.No_Socket;
      Connected : Boolean := False;
   end record;

end Differential.Client;
