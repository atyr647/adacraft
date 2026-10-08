with Ada.Command_Line;
with Ada.Text_IO;
with GNAT.Sockets;
with Adacraft.Network;
with Adacraft.Protocol.Status_Info;

procedure Adacraft_Server is
   Port : GNAT.Sockets.Port_Type := 25565;
   Info : Adacraft.Protocol.Status_Info.Status_Info :=
     Adacraft.Protocol.Status_Info.Default_Info;
   pragma Unreferenced (Info);
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
