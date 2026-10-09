with Adacraft.Protocol;

package Adacraft.Auth.MD5 is
   pragma Pure;

   subtype Octet is Adacraft.Protocol.Octet;
   subtype Octets is Adacraft.Protocol.Octets;

   type Digest is array (1 .. 16) of Octet;

   function MD5 (Data : Octets) return Digest
     with Pre => Data'Length <= 256;

   function Name_UUID_From_Bytes (Data : Octets) return Digest
     with Pre => Data'Length <= 256;

   function Offline_UUID (Name : String) return Digest
     with Pre => Name'Length in 1 .. 16;

end Adacraft.Auth.MD5;
