with Adacraft.Protocol;

package Adacraft.Auth is
   type Digest is array (1 .. 16) of Adacraft.Protocol.Octet;

   function MD5 (Data : Adacraft.Protocol.Octets) return Digest
     with Pre => Data'Length <= 256;

   function Offline_UUID (Name : String) return Digest
     with Pre => Name'Length in 1 .. 16;
end Adacraft.Auth;
