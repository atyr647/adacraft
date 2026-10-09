with Ada.Command_Line;
with Ada.Text_IO;
with GNAT.OS_Lib;
with GNAT.Sockets;
with Adacraft.Network;
with Adacraft;
--  Login is handled only in Adacraft.Network.Handle_Frame_Body; no
--  second login handler here (cleanup pass forbids duplicate blocks).

procedure Adacraft_Server is
   Port : GNAT.Sockets.Port_Type := 25565;

begin
   --  Event-driven server: Parse_Port -> Initialize_Listener ->
   --  Run_Event_Loop.  Per-connection dispatch (Handshake_Exchange /
   --  Status_Exchange / Login via Frame.Feed -> Packet_Decoder ->
   --  State.Table -> Login -> Packet_Encoder) lives in Adacraft.Network.
   --  Login branch (Handle_Frame_Body, Login state): well-formed Login
   --  Start (v=777 or v/=777, already transitioned to Login) answers one
   --  framed 777 Login Disconnect then clean-closes only that connection;
   --  invalid-in-Login closes with no reply.  Packet_Decoder is on the R1
   --  path via the Login gate decode.
   --  Parse_Port lives in Adacraft.Network so unit tests can with it
   --  directly; the server and the tests call the same implementation.
   if Ada.Command_Line.Argument_Count >= 1 then
      declare
         Arg : constant String := Ada.Command_Line.Argument (1);
         P   : GNAT.Sockets.Port_Type;
      begin
         Adacraft.Network.Parse_Port (Arg, P);
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
