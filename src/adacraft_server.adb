with Ada.Command_Line;
with Ada.Text_IO;
with GNAT.OS_Lib;
with GNAT.Sockets;
with Adacraft.Network;
with Adacraft;

procedure Adacraft_Server is
   Port : GNAT.Sockets.Port_Type := 25565;

   --  Strict port parsing: rejects empty, non-digit (incl. "-N"),
   --  0 and > 65535.  Raises Constraint_Error on any bad value; the
   --  caller prints the one-line stderr message and exits non-zero
   --  with no exception trace.
   procedure Parse_Port (Image : String; Port : out GNAT.Sockets.Port_Type) is
      use GNAT.Sockets;
      V : Natural := 0;
   begin
      if Image'Length = 0 then
         raise Constraint_Error with "empty port";
      end if;
      for I in Image'Range loop
         if Image (I) < '0' or else Image (I) > '9' then
            raise Constraint_Error with "non-digit port";
         end if;
         V := V * 10 + (Character'Pos (Image (I)) - Character'Pos ('0'));
         if V > 65535 then
            raise Constraint_Error with "port too large";
         end if;
      end loop;
      if V < 1 or else V > 65535 then
         raise Constraint_Error with "port out of range";
      end if;
      Port := Port_Type (V);
   end Parse_Port;

begin
   --  Event-driven server: Parse_Port -> Initialize_Listener ->
   --  Run_Event_Loop.  Per-connection dispatch (Handshake_Exchange /
   --  Status_Exchange via Frame.Feed) lives in Adacraft.Network.
   if Ada.Command_Line.Argument_Count >= 1 then
      declare
         Arg : constant String := Ada.Command_Line.Argument (1);
         P   : GNAT.Sockets.Port_Type;
      begin
         Parse_Port (Arg, P);
         Port := P;
      exception
         when others =>
            Ada.Text_IO.Put_Line
              (Ada.Text_IO.Standard_Error,
               "adacraft_server: invalid port """ & Arg
               & """: must be 1..65535");
            GNAT.OS_Lib.OS_Exit (1);
      end;
   end if;
   Ada.Text_IO.Put_Line
     ("AdaCraft " & Adacraft.Minecraft_Version
      & " protocol" & Adacraft.Protocol_Version'Image
      & " listening on" & Port'Image);
   declare
      use GNAT.Sockets;
      Listener : Socket_Type;
   begin
      Adacraft.Network.Initialize_Listener (Port, Listener);
      Adacraft.Network.Run_Event_Loop (Listener);
   end;
end Adacraft_Server;
