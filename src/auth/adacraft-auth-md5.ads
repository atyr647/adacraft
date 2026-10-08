with Adacraft.Protocol;

private package Adacraft.Auth.MD5 is
   --  Private RFC 1321 MD5 helper. Only the Auth parent (and its other
   --  children) may with this unit; it is not part of the public API.

   function Compute (Data : Adacraft.Protocol.Octets)
     return Adacraft.Auth.Digest
     with Pre => Data'Length <= 256;

end Adacraft.Auth.MD5;
