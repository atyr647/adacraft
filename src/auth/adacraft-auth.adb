with Adacraft.Auth.MD5;

package body Adacraft.Auth is
   use type Adacraft.Protocol.Octet;
   subtype Octet is Adacraft.Protocol.Octet;
   subtype Octets is Adacraft.Protocol.Octets;

   function Offline_UUID_For_Name (Name : String) return Digest is
      Prefix : constant String := "OfflinePlayer:";
      Raw    : Octets (1 .. Prefix'Length + Name'Length);
      Result : Adacraft.Auth.Digest;
   begin
      for I in Prefix'Range loop
         Raw (I - Prefix'First + 1) := Octet (Character'Pos (Prefix (I)));
      end loop;
      for I in Name'Range loop
         Raw (Prefix'Length + (I - Name'First + 1)) :=
           Octet (Character'Pos (Name (I)));
      end loop;
      Result := Adacraft.Auth.MD5.Compute (Raw);
      --  UUID version 3, RFC 4122 variant.
      Result (7) := (Result (7) and 16#0F#) or 16#30#;
      Result (9) := (Result (9) and 16#3F#) or 16#80#;
      return Result;
   end Offline_UUID_For_Name;

   function Offline_UUID (Name : String) return Digest is
   begin
      return Offline_UUID_For_Name (Name);
   end Offline_UUID;

   function Offline_Identity_For_Name (Name : String) return Player_Identity is
   begin
      return (UUID          => Offline_UUID_For_Name (Name),
              Authenticated => False,
              Is_Offline    => True);
   end Offline_Identity_For_Name;
end Adacraft.Auth;
