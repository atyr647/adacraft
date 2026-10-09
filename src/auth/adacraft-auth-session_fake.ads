--  Deterministic fake for the online-auth Session_Check contract.
--  Depends on Adacraft.Auth.Session; no network, file, or clock I/O.
--  No GNAT.Sockets, Ada.Text_IO, Ada.Calendar, file or clock calls.

with Adacraft.Auth.Session;

package Adacraft.Auth.Session_Fake is

   package Session renames Adacraft.Auth.Session;

   subtype Username is Session.Username;
   subtype Server_Hash is Session.Server_Hash;
   subtype Profile_Name is Session.Profile_Name;
   subtype Property_Text is Session.Property_Text;
   subtype Body_Bytes is Session.Body_Bytes;
   subtype Ip_Text is Session.Ip_Text;
   subtype Uuid is Session.Uuid;
   subtype Optional_Ip is Session.Optional_Ip;
   subtype Auth_Property is Session.Auth_Property;
   subtype Property_Vector is Session.Property_Vector;
   subtype Auth_Profile is Session.Auth_Profile;
   subtype Disconnect_Reason is Session.Disconnect_Reason;
   subtype Result_Kind is Session.Result_Kind;
   subtype Auth_Result is Session.Auth_Result;
   subtype Http_Reply is Session.Http_Reply;

   package Username_Bounded renames Session.Username_Bounded;
   package Hash_Bounded renames Session.Hash_Bounded;
   package Profile_Name_Bounded renames Session.Profile_Name_Bounded;
   package Prop_Bounded renames Session.Prop_Bounded;
   package Body_Bounded renames Session.Body_Bounded;
   package Ip_Bounded renames Session.Ip_Bounded;

   Accepted : Session.Result_Kind renames Session.Accepted;
   Rejected : Session.Result_Kind renames Session.Rejected;
   Auth_Failed : Session.Disconnect_Reason renames Session.Auth_Failed;
   Auth_Service_Unavailable : Session.Disconnect_Reason
     renames Session.Auth_Service_Unavailable;

   function Interpret_Reply (Reply : Session.Http_Reply)
     return Session.Auth_Result renames Session.Interpret_Reply;

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
