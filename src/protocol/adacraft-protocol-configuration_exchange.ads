--  The CONFIGURATION state (docs/PROTOCOL.md, Configuration): what the
--  server sends and how it reads the client's answers. The bytes sent are
--  the oracle's, from Adacraft.Protocol.Configuration_Data (generated/);
--  nothing here builds a registry or a tag.
package Adacraft.Protocol.Configuration_Exchange is

   --  A packet body given in hex (two digits an octet), as the generated
   --  data holds it.
   function From_Hex (Hex : String) return Octets
     with Pre => Hex'Length mod 2 = 0;

   --  Whether a serverbound Select Known Packs payload (after its packet
   --  id) is well formed and names the minecraft:core pack at version 26.3.
   --  Malformed (a count or string past the end, a negative count, more
   --  than Max_Known_Packs, bytes left over): False.
   Max_Known_Packs : constant := 64;
   function Names_Core_Pack (Payload : Octets) return Boolean;

end Adacraft.Protocol.Configuration_Exchange;
