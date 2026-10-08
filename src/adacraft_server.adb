with Ada.Command_Line;
with Ada.Text_IO;
with GNAT.Sockets;
with Adacraft;
with Adacraft.Network;

procedure Adacraft_Server is
   Port : GNAT.Sockets.Port_Type := 25565;
begin
   if Ada.Command_Line.Argument_Count >= 1 then
      Port := GNAT.Sockets.Port_Type'Value (Ada.Command_Line.Argument (1));
   end if;
   Ada.Text_IO.Put_Line
     ("AdaCraft " & Adacraft.Minecraft_Version
      & " protocol" & Adacraft.Protocol_Version'Image
      & " listening on" & Port'Image);
   Adacraft.Network.Serve (Port);
end Adacraft_Server;
