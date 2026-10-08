with Ada.Command_Line;
with Ada.Text_IO;
with Adacraft.Auth.Session_Fake;
with Interfaces;

package body Test_Auth_Session is
   package S renames Adacraft.Auth.Session_Fake;
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

   function Mk_Reply (Status : Integer; Text : String) return S.Http_Reply is
   begin
      return (Transport_Failed => False,
              Status           => Status,
              Body_Text        => BS (Text));
   end Mk_Reply;

   function Is_Accept (R : S.Auth_Result) return Boolean is (R.Kind = S.Accepted);
   function Is_Failed (R : S.Auth_Result) return Boolean is
     (R.Kind = S.Rejected and then R.Reason = S.Auth_Failed);
   function Is_Unavail (R : S.Auth_Result) return Boolean is
     (R.Kind = S.Rejected and then R.Reason = S.Auth_Service_Unavailable);

   Valid_Body : constant String :=
     "{""id"":""069a79f444e94726a5befca90e38aaf5"",""name"":""Notch""}";

   Expected_Uuid : constant S.Uuid :=
     (16#06#, 16#9A#, 16#79#, 16#F4#, 16#44#, 16#E9#, 16#47#, 16#26#,
      16#A5#, 16#BE#, 16#FC#, 16#A9#, 16#0E#, 16#38#, 16#AA#, 16#F5#);

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
           or else S.Prop_Bounded.To_String (A.Profile.Properties (I).Signature) /=
             S.Prop_Bounded.To_String (B.Profile.Properties (I).Signature)
         then
            return False;
         end if;
      end loop;
      return True;
   end Same_Result;

   procedure Call_Fake
     (F      : in out S.Fake_Check;
      U      : String := "Notch";
      H      : String := "hash1";
      Result : out S.Auth_Result)
   is
      Uu : constant S.Username :=
        S.Username_Bounded.To_Bounded_String (U);
      Hh : constant S.Server_Hash :=
        S.Hash_Bounded.To_Bounded_String (H);
      Ip : constant S.Optional_Ip := (Present => False);
   begin
      Result := F.Has_Joined (Uu, Hh, Ip);
   end Call_Fake;

   function Props_Body_17 return String is
      Head : constant String :=
        "{""id"":""069a79f444e94726a5befca90e38aaf5"",""name"":""Notch"","
        & """properties"":[";
      Tail : constant String := "]}";
      One  : constant String := "{""name"":""n"",""value"":""v""}";
   begin
      declare
         Res : String (1 .. Head'Length + 17 * 32 + Tail'Length) :=
           (others => ' ');
         Pos : Natural := 1;
      begin
         Res (Pos .. Pos + Head'Length - 1) := Head;
         Pos := Pos + Head'Length;
         for I in 1 .. 17 loop
            Res (Pos .. Pos + One'Length - 1) := One;
            Pos := Pos + One'Length;
            if I < 17 then
               Res (Pos) := ',';
               Pos := Pos + 1;
            end if;
         end loop;
         Res (Pos .. Pos + Tail'Length - 1) := Tail;
         Pos := Pos + Tail'Length;
         return Res (1 .. Pos - 1);
      end;
   end Props_Body_17;

   procedure Run is
      F : S.Fake_Check;
      R, R2 : S.Auth_Result;
   begin
      Failures := 0;

      --  T1 valid 200 accept (fake only, replay through pure interpreter).
      F := (Mode => S.Replay_Reply,
            Scripted_Status => 200,
            Scripted_Body => BS (Valid_Body),
            others => <>);
      Call_Fake (F, Result => R);
      Check (Is_Accept (R), "T1 accept kind");
      if R.Kind = S.Accepted then
         Check (R.Profile.Id = Expected_Uuid, "T1 uuid");
         Check (S.Profile_Name_Bounded.To_String (R.Profile.Name) = "Notch",
                "T1 name");
      end if;

      --  T2 204 => Auth_Failed.
      F := (Mode => S.Replay_Reply,
            Scripted_Status => 204,
            Scripted_Body => BS (""),
            others => <>);
      Call_Fake (F, Result => R);
      Check (Is_Failed (R), "T2 204 auth-failed");

      --  T3 200-empty => Auth_Failed.
      F := (Mode => S.Replay_Reply,
            Scripted_Status => 200,
            Scripted_Body => BS (""),
            others => <>);
      Call_Fake (F, Result => R);
      Check (Is_Failed (R), "T3 200-empty auth-failed");

      --  T4 transport-fail => Unavailable.
      F := (Mode => S.Fail_Transport, others => <>);
      Call_Fake (F, Result => R);
      Check (Is_Unavail (R), "T4 transport unavailable");
      R2 := S.Interpret_Reply (S.Http_Reply'(Transport_Failed => True));
      Check (Is_Unavail (R2), "T4 pure transport unavailable");

      --  T5 500 + one other non-200/204 => Unavailable.
      F := (Mode => S.Replay_Reply,
            Scripted_Status => 500,
            Scripted_Body => BS (Valid_Body),
            others => <>);
      Call_Fake (F, Result => R);
      Check (Is_Unavail (R), "T5 500 unavailable");
      F := (Mode => S.Replay_Reply,
            Scripted_Status => 404,
            Scripted_Body => BS (Valid_Body),
            others => <>);
      Call_Fake (F, Result => R2);
      Check (Is_Unavail (R2), "T5 404 unavailable");

      --  T6 malformed / missing id / missing name / bad id.
      F := (Mode => S.Replay_Reply,
            Scripted_Status => 200,
            Scripted_Body => BS ("not json{{{"),
            others => <>);
      Call_Fake (F, Result => R);
      Check (Is_Unavail (R), "T6 malformed unavailable");
      F := (Mode => S.Replay_Reply,
            Scripted_Status => 200,
            Scripted_Body => BS ("{""name"":""Notch""}"),
            others => <>);
      Call_Fake (F, Result => R);
      Check (Is_Unavail (R), "T6 missing id unavailable");
      F := (Mode => S.Replay_Reply,
            Scripted_Status => 200,
            Scripted_Body =>
              BS ("{""id"":""069a79f444e94726a5befca90e38aaf5""}"),
            others => <>);
      Call_Fake (F, Result => R);
      Check (Is_Unavail (R), "T6 missing name unavailable");
      F := (Mode => S.Replay_Reply,
            Scripted_Status => 200,
            Scripted_Body =>
              BS ("{""id"":""ZZZZ"",""name"":""Notch""}"),
            others => <>);
      Call_Fake (F, Result => R);
      Check (Is_Unavail (R), "T6 bad id unavailable");

      --  T7 oversize body and 17-properties: must not crash.
      declare
         Big : S.Body_Bytes := S.Body_Bounded.Null_Bounded_String;
         Chunk : constant String (1 .. 4096) := (others => 'x');
      begin
         for I in 1 .. 16 loop
            S.Body_Bounded.Append (Big, Chunk);
         end loop;
         R := S.Interpret_Reply
           (S.Http_Reply'(Transport_Failed => False,
                          Status => 200, Body_Text => Big));
         Check (Is_Unavail (R), "T7 max-body malformed unavailable");
      exception
         when others => Check (False, "T7 max-body no crash");
      end;
      declare
         Pb : constant String := Props_Body_17;
      begin
         R := S.Interpret_Reply (Mk_Reply (200, Pb));
         Check ((R.Kind = S.Accepted or else Is_Unavail (R)),
                "T7 17-props no crash");
      exception
         when others => Check (False, "T7 17-props no crash");
      end;

      --  T8 input recording.
      declare
         F8 : S.Fake_Check :=
           (Mode => S.Return_Accepted, others => <>);
         Uu : constant S.Username :=
           S.Username_Bounded.To_Bounded_String ("Steve");
         Hh : constant S.Server_Hash :=
           S.Hash_Bounded.To_Bounded_String ("h2");
         Ip : constant S.Optional_Ip :=
           (Present => True,
            Value => S.Ip_Bounded.To_Bounded_String ("1.2.3.4"));
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
      end;

      --  T9 with/without signature preserved (scripted accepted profile).
      declare
         F9 : S.Fake_Check :=
           (Mode => S.Return_Accepted, others => <>);
         P : S.Auth_Profile;
      begin
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
         Call_Fake (F9, Result => R);
         Check (Is_Accept (R), "T9 scripted accept");
         if R.Kind = S.Accepted then
            Check (R.Profile.Prop_Count = 2, "T9 prop count");
            Check (R.Profile.Properties (1).Has_Sig
                   and then S.Prop_Bounded.To_String
                     (R.Profile.Properties (1).Signature) = "sss",
                   "T9 sig preserved");
            Check (not R.Profile.Properties (2).Has_Sig,
                   "T9 no-sig preserved");
         end if;
      end;

      --  T10 double-run equality.
      F := (Mode => S.Replay_Reply,
            Scripted_Status => 200,
            Scripted_Body => BS (Valid_Body),
            others => <>);
      Call_Fake (F, Result => R);
      Call_Fake (F, Result => R2);
      Check (Same_Result (R, R2), "T10 determinism accept");
      F := (Mode => S.Replay_Reply,
            Scripted_Status => 500,
            Scripted_Body => BS ("oops"),
            others => <>);
      Call_Fake (F, Result => R);
      Call_Fake (F, Result => R2);
      Check (Same_Result (R, R2), "T10 determinism reject");

      if Failures = 0 then
         Ada.Text_IO.Put_Line ("auth-session tests passed");
      else
         Ada.Text_IO.Put_Line
           ("auth-session tests failed:" & Failures'Image);
         Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
      end if;
   end Run;

end Test_Auth_Session;
