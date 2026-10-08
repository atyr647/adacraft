with Adacraft.Protocol;

package Adacraft.Auth is
   type Digest is array (1 .. 16) of Adacraft.Protocol.Octet;

   --  Constitution 23 gate: offline derivation runs only when False.
   --  Default stays online so a server never silently runs offline.
   Online_Mode : Boolean := True;

   type Player_Identity is record
      UUID          : Digest  := [others => 0];
      Authenticated : Boolean := False;
      Is_Offline    : Boolean := False;
   end record;

   function Offline_UUID_For_Name (Name : String) return Digest
     with Pre => Name'Length in 1 .. 16;

   --  Compatibility alias: same vanilla UUIDv3 derivation.
   function Offline_UUID (Name : String) return Digest
     with Pre => Name'Length in 1 .. 16;

   function Offline_Identity_For_Name (Name : String) return Player_Identity
     with Pre => Name'Length in 1 .. 16;
end Adacraft.Auth;
