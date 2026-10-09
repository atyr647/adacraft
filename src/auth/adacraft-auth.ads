with Adacraft.Protocol;

package Adacraft.Auth is
   type Digest is array (1 .. 16) of Adacraft.Protocol.Octet;

   type Identity_Kind is (Offline, Online_Authenticated_Reserved);

   type Server_Auth_Mode is (Online, Offline);

   subtype Name_Length_Range is Natural range 0 .. 16;

   --  Discriminated so offline is marked by type/variant and can never
   --  be misread as a future online-authenticated identity.
   type Player_Identity (Kind : Identity_Kind := Offline) is record
      UUID        : Digest := (others => 0);
      Name_Length : Name_Length_Range := 0;
      Name        : String (1 .. 16) := (others => ' ');
   end record;

   function Offline_UUID (Name : String) return Digest
     with Pre => Name'Length in 1 .. 16;
end Adacraft.Auth;
