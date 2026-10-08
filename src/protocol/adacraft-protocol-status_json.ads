with Adacraft.Protocol.Status_Info;

package Adacraft.Protocol.Status_Json is

   use Adacraft.Protocol.Status_Info;

   --  Worst case: every MOTD byte expands to a 6-character \u00XX escape,
   --  plus fixed template overhead and bounded numeric fields.
   Max_Json_Length : constant :=
     256 * 6 + 32 * 6 + 256;

   function To_Json (Info : Status_Info.Status_Info) return String;
   --  Deterministic compact serializer. Fixed key order: version, players,
   --  description, enforcesSecureChat. Section 15 escaping policy.
   --  Pure function of Info; no timestamps, no nondeterminism.

end Adacraft.Protocol.Status_Json;
