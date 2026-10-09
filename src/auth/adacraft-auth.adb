with Adacraft.Auth.MD5;
with Adacraft.Protocol;

package body Adacraft.Auth is

   function Offline_UUID (Name : String) return Digest is
      Md : Adacraft.Auth.MD5.Digest := Adacraft.Auth.MD5.Offline_UUID (Name);
      Result : Digest := (others => 0);
   begin
      for I in Result'Range loop
         Result (I) := Adacraft.Protocol.Octet (Md (I));
      end loop;
      return Result;
   end Offline_UUID;
end Adacraft.Auth;
