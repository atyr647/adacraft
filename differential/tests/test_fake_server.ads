with Ada.Containers.Vectors;
with Ada.Strings.Unbounded;
with GNAT.Sockets;

--  In-process scripted loopback listener on 127.0.0.1, ephemeral port.
--  The bound port is reported to the test code only; it is never printed.
package Test_Fake_Server is

   type Action_Kind is (Send_Bytes, Send_Raw, Close, Silence, Refuse);

   type Action is record
      Kind : Action_Kind := Close;
      Data : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   package Action_Vectors is new Ada.Containers.Vectors (Positive, Action);

   type Server is limited private;

   --  The script is replayed on every accepted connection. A script whose
   --  first action is Refuse leaves nothing listening on the port.
   procedure Start (S : in out Server; Script : Action_Vectors.Vector);

   function Port (S : Server) return Natural;

   --  Number of connections accepted so far.
   function Accepts (S : Server) return Natural;

   procedure Stop (S : in out Server);

   function Send (Data : String) return Action;
   function Raw (Data : String) return Action;
   function Close_Now return Action;
   function Hold_Silent return Action;
   function Refuse_All return Action;

private

   protected type Flag is
      procedure Stop;
      function Stopped return Boolean;
   private
      Flagged : Boolean := False;
   end Flag;

   protected type Counter is
      procedure Inc;
      function Value return Natural;
   private
      N : Natural := 0;
   end Counter;

   type Instance;
   type Instance_Access is access Instance;

   task type Worker is
      entry Go (I : Instance_Access);
   end Worker;

   type Instance is limited record
      Listener  : GNAT.Sockets.Socket_Type := GNAT.Sockets.No_Socket;
      Bound     : Natural := 0;
      Script    : Action_Vectors.Vector;
      Stop_Flag : Flag;
      Count     : Counter;
      Started   : Boolean := False;
      W         : Worker;
   end record;

   type Server is limited record
      Impl : Instance_Access := null;
   end record;

end Test_Fake_Server;
