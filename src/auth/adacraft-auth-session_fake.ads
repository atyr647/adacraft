--  Deterministic fake for the online-auth Session_Check contract.
--  Depends on Adacraft.Auth.Session; no network, file, or clock I/O.
--  No GNAT.Sockets, Ada.Text_IO, Ada.Calendar, file or clock calls.

with Adacraft.Auth.Session;

package Adacraft.Auth.Session_Fake is

   package Session renames Adacraft.Auth.Session;

   type Script_Mode is (Return_Accepted, Replay_Reply, Fail_Transport);

   type Fake_Check is new Session.Session_Check with record
      Mode             : Script_Mode := Fail_Transport;
      Scripted_Profile : Session.Auth_Profile;
      Scripted_Status  : Integer range 100 .. 599 := 200;
      Scripted_Body    : Session.Body_Bytes;
      Last_Username    : Session.Username;
      Last_Hash        : Session.Server_Hash;
      Last_Ip          : Session.Optional_Ip;
      Call_Count       : Natural := 0;
      Has_Last         : Boolean := False;
   end record;

   overriding function Has_Joined
     (Self        : in out Fake_Check;
      Username    : Session.Username;
      Server_Hash : Session.Server_Hash;
      Client_Ip   : Session.Optional_Ip) return Session.Auth_Result;

end Adacraft.Auth.Session_Fake;
