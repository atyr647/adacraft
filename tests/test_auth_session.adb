with Ada.Command_Line;
with Ada.Text_IO;
with Adacraft.Auth.Session;
with Adacraft.Auth.Session_Fake;
with Interfaces;

package body Test_Auth_Session is
   package S renames Adacraft.Auth.Session;
   package Fk renames Adacraft.Auth.Session_Fake;
   use type S.Result_Kind;
   use type S.Disconnect_Reason;
   use type S.Uuid;
   use type Interfaces.Unsigned_8;

   Failures : Natural := 0;

   procedure Check (Cond : Boolean; Name : String) is
   begin
      if not Cond then
         Ada.Text_IO.Put_Line ("FAIL auth-session " & Name);
         Failures := Failures + 1;
      end if;
   end Check;

   function BS (Text : String) return S.Body_Bytes is
   begin
      return S.Body_Bounded.To_Bounded_String (Text);
   end BS;

   procedure T1 is
      procedure Call_Fake
        (F : in out Fk.Fake_Check; Result : out S.Auth_Result) is
         Uu : constant S.Username :=
           S.Username_Bounded.To_Bounded_String ("Notch");
         Hh : constant S.Server_Hash :=
           S.Hash_Bounded.To_Bounded_String ("hash1");
         Ip : constant S.Optional_Ip := (Present => False);
      begin
         Result := F.Has_Joined (Uu, Hh, Ip);
      end Call_Fake;
      Valid_Body : constant String :=
        "{""id"":""069a79f444e94726a5befca90e38aaf5"",""name"":""Notch"","
        & """extra"":""hello""}";
      Expected_Uuid : constant S.Uuid :=
        (16#06#, 16#9A#, 16#79#, 16#F4#, 16#44#, 16#E9#, 16#47#, 16#26#,
         16#A5#, 16#BE#, 16#FC#, 16#A9#, 16#0E#, 16#38#, 16#AA#, 16#F5#);
      F : Fk.Fake_Check;
      R : S.Auth_Result;
   begin
      F := (Mode => Fk.Replay_Reply, Scripted_Status => 200,
            Scripted_Body => BS (Valid_Body), others => <>);
      Call_Fake (F, R);
      Check (R.Kind = S.Accepted, "T1 accept kind");
      if R.Kind = S.Accepted then
         Check (R.Profile.Id = Expected_Uuid, "T1 uuid");
         Check (S.Profile_Name_Bounded.To_String (R.Profile.Name) = "Notch",
                "T1 name");
         Check (R.Profile.Prop_Count = 0, "T1 no props");
      end if;
      declare
         F2 : Fk.Fake_Check :=
           (Mode => Fk.Replay_Reply, Scripted_Status => 200,
            Scripted_Body => BS (Valid_Body), others => <>);
         R2 : S.Auth_Result;
         Uu2 : constant S.Username :=
           S.Username_Bounded.To_Bounded_String ("Notch");
         Hh2 : constant S.Server_Hash :=
           S.Hash_Bounded.To_Bounded_String ("hash1");
      begin
         R2 := F2.Has_Joined (Uu2, Hh2, (Present => False));
         Check (R2.Kind = S.Accepted, "T1 extra string key accept");
         if R2.Kind = S.Accepted then
            Check (R2.Profile.Id = Expected_Uuid, "T1 extra uuid");
            Check (S.Profile_Name_Bounded.To_String (R2.Profile.Name)
                   = "Notch", "T1 extra name");
         end if;
         R2 := S.Interpret_Reply
           (S.Http_Reply'(Transport_Failed => False, Status => 200,
                          Body_Text => BS (Valid_Body)));
         Check (R2.Kind = S.Accepted, "T1 real interpreter extra key");
      end;
   end T1;

   procedure T2 is
      F : Fk.Fake_Check;
      R : S.Auth_Result;
      Uu : constant S.Username := S.Username_Bounded.To_Bounded_String ("Notch");
      Hh : constant S.Server_Hash := S.Hash_Bounded.To_Bounded_String ("h");
      Ip : constant S.Optional_Ip := (Present => False);
   begin
      F := (Mode => Fk.Replay_Reply, Scripted_Status => 204,
            Scripted_Body => S.Body_Bounded.Null_Bounded_String, others => <>);
      R := F.Has_Joined (Uu, Hh, Ip);
      Check (R.Kind = S.Rejected and then R.Reason = S.Auth_Failed,
             "T2 204 auth-failed");
   end T2;

   procedure T3 is
      F : Fk.Fake_Check;
      R : S.Auth_Result;
      Uu : constant S.Username := S.Username_Bounded.To_Bounded_String ("Notch");
      Hh : constant S.Server_Hash := S.Hash_Bounded.To_Bounded_String ("h");
      Ip : constant S.Optional_Ip := (Present => False);
   begin
      F := (Mode => Fk.Replay_Reply, Scripted_Status => 200,
            Scripted_Body => S.Body_Bounded.Null_Bounded_String, others => <>);
      R := F.Has_Joined (Uu, Hh, Ip);
      Check (R.Kind = S.Rejected and then R.Reason = S.Auth_Failed,
             "T3 200-empty auth-failed");
   end T3;

   procedure T4 is
      F : Fk.Fake_Check;
      R, R2 : S.Auth_Result;
      Uu : constant S.Username := S.Username_Bounded.To_Bounded_String ("Notch");
      Hh : constant S.Server_Hash := S.Hash_Bounded.To_Bounded_String ("h");
      Ip : constant S.Optional_Ip := (Present => False);
   begin
      F := (Mode => Fk.Fail_Transport, others => <>);
      R := F.Has_Joined (Uu, Hh, Ip);
      Check (R.Kind = S.Rejected and then R.Reason = S.Auth_Service_Unavailable,
             "T4 transport unavailable");
      R2 := S.Interpret_Reply (S.Http_Reply'(Transport_Failed => True));
      Check (R2.Kind = S.Rejected
             and then R2.Reason = S.Auth_Service_Unavailable,
             "T4 pure transport unavailable");
   end T4;

   procedure T5 is
      Valid_Body : constant String :=
        "{""id"":""069a79f444e94726a5befca90e38aaf5"",""name"":""Notch""}";
      F : Fk.Fake_Check;
      R, R2 : S.Auth_Result;
      Uu : constant S.Username := S.Username_Bounded.To_Bounded_String ("Notch");
      Hh : constant S.Server_Hash := S.Hash_Bounded.To_Bounded_String ("h");
      Ip : constant S.Optional_Ip := (Present => False);
   begin
      F := (Mode => Fk.Replay_Reply, Scripted_Status => 500,
            Scripted_Body => BS (Valid_Body), others => <>);
      R := F.Has_Joined (Uu, Hh, Ip);
      Check (R.Kind = S.Rejected
             and then R.Reason = S.Auth_Service_Unavailable,
             "T5 500 unavailable");
      F := (Mode => Fk.Replay_Reply, Scripted_Status => 404,
            Scripted_Body => BS (Valid_Body), others => <>);
      R2 := F.Has_Joined (Uu, Hh, Ip);
      Check (R2.Kind = S.Rejected
             and then R2.Reason = S.Auth_Service_Unavailable,
             "T5 404 unavailable");
   end T5;

   procedure T6 is
      function Via (Text : String) return S.Auth_Result is
         F : Fk.Fake_Check :=
           (Mode => Fk.Replay_Reply, Scripted_Status => 200,
            Scripted_Body => BS (Text), others => <>);
         Uu : constant S.Username :=
           S.Username_Bounded.To_Bounded_String ("Notch");
         Hh : constant S.Server_Hash :=
           S.Hash_Bounded.To_Bounded_String ("h");
         Ip : constant S.Optional_Ip := (Present => False);
      begin
         return F.Has_Joined (Uu, Hh, Ip);
      end Via;
      R : S.Auth_Result;
   begin
      R := Via ("not json{{{");
      Check (R.Kind = S.Rejected
             and then R.Reason = S.Auth_Service_Unavailable,
             "T6 malformed unavailable");
      R := Via ("{""id"":""069a79f444e94726a5befca90e38aaf5"","
                & """name"":""x""");
      Check (R.Kind = S.Rejected
             and then R.Reason = S.Auth_Service_Unavailable,
             "T6 truncated unavailable");
      R := Via ("{""id"":""069a79f444e94726a5befca90e38aaf5"","
                & """name"":""x""} trailing");
      Check (R.Kind = S.Rejected
             and then R.Reason = S.Auth_Service_Unavailable,
             "T6 trailing-garbage unavailable");
      R := Via ("{""name"":""Notch""}");
      Check (R.Kind = S.Rejected
             and then R.Reason = S.Auth_Service_Unavailable,
             "T6 missing id unavailable");
      R := Via ("{""id"":""069a79f444e94726a5befca90e38aaf5""}");
      Check (R.Kind = S.Rejected
             and then R.Reason = S.Auth_Service_Unavailable,
             "T6 missing name unavailable");
      R := Via ("{""id"":""ZZZZ"",""name"":""Notch""}");
      Check (R.Kind = S.Rejected
             and then R.Reason = S.Auth_Service_Unavailable,
             "T6 bad id unavailable");
   end T6;

   function Props_Body (N : Natural) return String is
      Head : constant String :=
        "{""id"":""069a79f444e94726a5befca90e38aaf5"",""name"":""Notch"","
        & """properties"":[";
      Tail : constant String := "]}";
      One  : constant String := "{""name"":""n"",""value"":""v""}";
   begin
      declare
         Res : String (1 .. Head'Length + N * 32 + Tail'Length) :=
           (others => ' ');
         Pos : Natural := 1;
      begin
         Res (Pos .. Pos + Head'Length - 1) := Head;
         Pos := Pos + Head'Length;
         for I in 1 .. N loop
            Res (Pos .. Pos + One'Length - 1) := One;
            Pos := Pos + One'Length;
            if I < N then
               Res (Pos) := ',';
               Pos := Pos + 1;
            end if;
         end loop;
         Res (Pos .. Pos + Tail'Length - 1) := Tail;
         Pos := Pos + Tail'Length;
         return Res (1 .. Pos - 1);
      end;
   end Props_Body;

   procedure T7 is
      Big : S.Body_Bytes := S.Body_Bounded.Null_Bounded_String;
      Chunk : constant String (1 .. 4096) := (others => 'x');
      R : S.Auth_Result;
   begin
      for I in 1 .. 16 loop
         S.Body_Bounded.Append (Big, Chunk);
      end loop;
      begin
         R := S.Interpret_Reply
           (S.Http_Reply'(Transport_Failed => False, Status => 200,
                          Body_Text => Big));
         Check (R.Kind = S.Rejected
                and then R.Reason = S.Auth_Service_Unavailable,
                "T7 max-body unavailable");
      exception
         when others => Check (False, "T7 max-body no crash");
      end;
      begin
         R := S.Interpret_Reply
           (S.Http_Reply'(Transport_Failed => False, Status => 200,
                          Body_Text => BS (Props_Body (17))));
         Check (R.Kind = S.Rejected
                and then R.Reason = S.Auth_Service_Unavailable,
                "T7 17-props unavailable");
      exception
         when others => Check (False, "T7 17-props no crash");
      end;
      begin
         R := S.Interpret_Reply
           (S.Http_Reply'(Transport_Failed => False, Status => 200,
                          Body_Text => BS (Props_Body (16))));
         Check (R.Kind = S.Accepted and then R.Profile.Prop_Count = 16,
                "T7 16-props accepted");
      exception
         when others => Check (False, "T7 16-props no crash");
      end;
   end T7;

   procedure T8 is
      F8 : Fk.Fake_Check := (Mode => Fk.Return_Accepted, others => <>);
      Uu : constant S.Username :=
        S.Username_Bounded.To_Bounded_String ("Steve");
      Hh : constant S.Server_Hash :=
        S.Hash_Bounded.To_Bounded_String ("h2");
      Ip : constant S.Optional_Ip :=
        (Present => True,
         Value => S.Ip_Bounded.To_Bounded_String ("1.2.3.4"));
      R : S.Auth_Result;
   begin
      R := F8.Has_Joined (Uu, Hh, Ip);
      Check (F8.Call_Count = 1, "T8 call count");
      Check (F8.Has_Last, "T8 has last");
      Check (S.Username_Bounded.To_String (F8.Last_Username) = "Steve",
                "T8 username recorded");
         Check (S.Hash_Bounded.To_String (F8.Last_Hash) = "h2",
                "T8 hash recorded");
         Check (F8.Last_Ip.Present
                and then S.Ip_Bounded.To_String (F8.Last_Ip.Value) = "1.2.3.4",
                "T8 ip recorded");
         R := F8.Has_Joined (Uu, Hh, (Present => False));
         Check (F8.Call_Count = 2, "T8 second call count");
         Check (not F8.Last_Ip.Present, "T8 absent ip recorded");
   end T8;

   procedure T9 is
      Expected_Uuid : constant S.Uuid :=
        (16#06#, 16#9A#, 16#79#, 16#F4#, 16#44#, 16#E9#, 16#47#, 16#26#,
         16#A5#, 16#BE#, 16#FC#, 16#A9#, 16#0E#, 16#38#, 16#AA#, 16#F5#);
      F9 : Fk.Fake_Check;
      P : S.Auth_Profile;
      R : S.Auth_Result;
      Uu : constant S.Username :=
        S.Username_Bounded.To_Bounded_String ("Notch");
      Hh : constant S.Server_Hash :=
        S.Hash_Bounded.To_Bounded_String ("h");
      Ip : constant S.Optional_Ip := (Present => False);
      Sig_Body : constant String :=
        "{""id"":""069a79f444e94726a5befca90e38aaf5"",""name"":""Notch"","
        & """properties"":[{""name"":""textures"",""value"":""vvv"","
        & """signature"":""sss""}]}";
      No_Sig_Body : constant String :=
        "{""id"":""069a79f444e94726a5befca90e38aaf5"",""name"":""Notch"","
        & """properties"":[{""name"":""n2"",""value"":""v2""}]}";
   begin
      F9 := (Mode => Fk.Return_Accepted, others => <>);
      P.Id := Expected_Uuid;
      P.Name := S.Profile_Name_Bounded.To_Bounded_String ("Notch");
      P.Prop_Count := 2;
      P.Properties (1) :=
        (Name => S.Prop_Bounded.To_Bounded_String ("textures"),
         Value => S.Prop_Bounded.To_Bounded_String ("vvv"),
         Has_Sig => True,
         Signature => S.Prop_Bounded.To_Bounded_String ("sss"));
      P.Properties (2) :=
        (Name => S.Prop_Bounded.To_Bounded_String ("n2"),
         Value => S.Prop_Bounded.To_Bounded_String ("v2"),
         Has_Sig => False,
         Signature => S.Prop_Bounded.Null_Bounded_String);
      F9.Scripted_Profile := P;
      R := F9.Has_Joined (Uu, Hh, Ip);
      Check (R.Kind = S.Accepted, "T9 scripted accept");
      if R.Kind = S.Accepted then
         Check (R.Profile.Prop_Count = 2, "T9 prop count");
         Check (R.Profile.Properties (1).Has_Sig
                and then S.Prop_Bounded.To_String
                  (R.Profile.Properties (1).Signature) = "sss",
                "T9 sig preserved");
         Check (not R.Profile.Properties (2).Has_Sig,
                "T9 no-sig preserved");
      end if;
      F9 := (Mode => Fk.Replay_Reply, Scripted_Status => 200,
             Scripted_Body => BS (Sig_Body), others => <>);
      R := F9.Has_Joined (Uu, Hh, Ip);
      Check (R.Kind = S.Accepted
             and then R.Profile.Prop_Count = 1
             and then R.Profile.Properties (1).Has_Sig
             and then S.Prop_Bounded.To_String
               (R.Profile.Properties (1).Signature) = "sss",
             "T9 parsed sig preserved");
      F9 := (Mode => Fk.Replay_Reply, Scripted_Status => 200,
             Scripted_Body => BS (No_Sig_Body), others => <>);
      R := F9.Has_Joined (Uu, Hh, Ip);
      Check (R.Kind = S.Accepted
             and then R.Profile.Prop_Count = 1
             and then not R.Profile.Properties (1).Has_Sig,
             "T9 parsed no-sig preserved");
   end T9;

   function Same_Result (A, B : S.Auth_Result) return Boolean is
   begin
      if A.Kind /= B.Kind then
         return False;
      end if;
      if A.Kind = S.Rejected then
         return A.Reason = B.Reason;
      end if;
      if A.Profile.Id /= B.Profile.Id then
         return False;
      end if;
      if S.Profile_Name_Bounded.To_String (A.Profile.Name) /=
        S.Profile_Name_Bounded.To_String (B.Profile.Name)
      then
         return False;
      end if;
      if A.Profile.Prop_Count /= B.Profile.Prop_Count then
         return False;
      end if;
      for I in 1 .. A.Profile.Prop_Count loop
         if S.Prop_Bounded.To_String (A.Profile.Properties (I).Name) /=
           S.Prop_Bounded.To_String (B.Profile.Properties (I).Name)
           or else S.Prop_Bounded.To_String (A.Profile.Properties (I).Value) /=
             S.Prop_Bounded.To_String (B.Profile.Properties (I).Value)
           or else A.Profile.Properties (I).Has_Sig /=
             B.Profile.Properties (I).Has_Sig
           or else S.Prop_Bounded.To_String
             (A.Profile.Properties (I).Signature) /=
             S.Prop_Bounded.To_String (B.Profile.Properties (I).Signature)
         then
            return False;
         end if;
      end loop;
      return True;
   end Same_Result;

   procedure T10 is
      Valid_Body : constant String :=
        "{""id"":""069a79f444e94726a5befca90e38aaf5"",""name"":""Notch""}";
      F : Fk.Fake_Check;
      R, R2 : S.Auth_Result;
      Uu : constant S.Username :=
        S.Username_Bounded.To_Bounded_String ("Notch");
      Hh : constant S.Server_Hash :=
        S.Hash_Bounded.To_Bounded_String ("h");
      Ip : constant S.Optional_Ip := (Present => False);
   begin
      F := (Mode => Fk.Replay_Reply, Scripted_Status => 200,
            Scripted_Body => BS (Valid_Body), others => <>);
      R := F.Has_Joined (Uu, Hh, Ip);
      R2 := F.Has_Joined (Uu, Hh, Ip);
      Check (Same_Result (R, R2), "T10 determinism accept");
      F := (Mode => Fk.Replay_Reply, Scripted_Status => 500,
            Scripted_Body => BS ("oops"), others => <>);
      R := F.Has_Joined (Uu, Hh, Ip);
      R2 := F.Has_Joined (Uu, Hh, Ip);
      Check (Same_Result (R, R2), "T10 determinism reject");
   end T10;

   procedure Run is
   begin
      Failures := 0;
      T1;
      T2;
      T3;
      T4;
      T5;
      T6;
      T7;
      T8;
      T9;
      T10;
      if Failures = 0 then
         Ada.Text_IO.Put_Line ("auth-session tests passed");
      else
         Ada.Text_IO.Put_Line
           ("auth-session tests failed:" & Failures'Image);
         Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
      end if;
   end Run;

end Test_Auth_Session;
