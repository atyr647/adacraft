package body Adacraft.Auth.Session_Fake is

   overriding function Has_Joined
     (Self        : in out Fake_Check;
      Username    : Session.Username;
      Server_Hash : Session.Server_Hash;
      Client_Ip   : Session.Optional_Ip) return Session.Auth_Result
   is
   begin
      Self.Last_Username := Username;
      Self.Last_Hash := Server_Hash;
      Self.Last_Ip := Client_Ip;
      Self.Has_Last := True;
      if Self.Call_Count < Natural'Last then
         Self.Call_Count := Self.Call_Count + 1;
      end if;

      case Self.Mode is
         when Return_Accepted =>
            return (Kind => Session.Accepted,
                    Profile => Self.Scripted_Profile);
         when Fail_Transport =>
            return Session.Interpret_Reply
              (Session.Http_Reply'(Transport_Failed => True));
         when Replay_Reply =>
            return Session.Interpret_Reply
              (Session.Http_Reply'(Transport_Failed => False,
                                   Status           => Self.Scripted_Status,
                                   Body_Text        => Self.Scripted_Body));
      end case;
   end Has_Joined;

end Adacraft.Auth.Session_Fake;
