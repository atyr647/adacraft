package Adacraft is
   Minecraft_Version : constant String := "26.3";
   Protocol_Version  : constant        := 777;
   Data_Version      : constant        := 5023;

   --  Minimal server configuration. Online_Mode defaults to True (online,
   --  matching vanilla); offline-mode servers skip encryption.
   --  R1.1/R1.2, A1: single boolean, reused by connection wiring.
   type Server_Config is record
      Online_Mode : Boolean := True;
   end record;

   Default_Server_Config : constant Server_Config := (Online_Mode => True);
end Adacraft;
