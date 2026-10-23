package Adacraft.Protocol.Version
  with SPARK_Mode => On
is
   --  Single source for the pinned target:
   --  Minecraft Java Edition 26.3, protocol 777, data version 5023.

   Minecraft_Version : constant String := "26.3";
   Protocol_Version  : constant        := 777;
   Data_Version      : constant        := 5023;

end Adacraft.Protocol.Version;
