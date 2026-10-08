with Ada.Characters.Handling;
with Ada.Strings.Fixed;
with Ada.Text_IO;
with Adacraft.Auth;
with Adacraft.Protocol.Buffer;
with Adacraft.Protocol.Frame;
with Adacraft.Protocol.Ids;
with Adacraft.Protocol.Packets;

package body Adacraft.Corpus.Runner is

   package P renames Adacraft.Protocol;
   package PS renames Adacraft.Protocol.State;
   use Ada.Strings.Unbounded;
   use type P.Status_Kind;
   use type PS.Result_Kind;
   use type PS.Connection_State;
   use type Byte_Vectors.Vector;
   use type Interfaces.Unsigned_32;

   function Img (N : Natural) return String is
     (Ada.Strings.Fixed.Trim (Natural'Image (N), Ada.Strings.Left));

   function Low (S : String) return String is
     (Ada.Characters.Handling.To_Lower (S));

   type Feed_Result is record
      Actual    : Outcome := Rejected;
      Pid       : Natural := 0;
      Category  : Unbounded_String;
      Detail    : Unbounded_String;
      Reencoded : Byte_Vectors.Vector;
   end record;

   procedure Feed
     (State : in out PS.Connection_State;
      Dir   : Direction;
      Input : P.Octets;
      R     : out Feed_Result)
   is
      F : constant P.Frame.Frame_Decode := P.Frame.Decode_Frame (Input, 1);
   begin
      R := (others => <>);
      if F.Status = P.Need_More then
         if F.Declared_Length > P.Max_Packet_Length then
            R.Actual := Rejected;
            R.Category := To_Unbounded_String ("framing");
            R.Detail := To_Unbounded_String
              ("frame declared length " & Img (F.Declared_Length)
               & " exceeds maximum");
         else
            R.Actual := Incomplete;
            R.Category := To_Unbounded_String ("framing");
            R.Detail := To_Unbounded_String ("frame incomplete");
         end if;
         return;
      elsif F.Status = P.Rejected then
         R.Category := To_Unbounded_String ("framing");
         R.Detail := To_Unbounded_String ("frame rejected");
         return;
      elsif F.Next /= Input'Last + 1 then
         R.Category := To_Unbounded_String ("framing");
         R.Detail := To_Unbounded_String ("input is not exactly one frame");
         return;
      end if;

      declare
         Payload : constant P.Octets := Input (F.Payload_First .. F.Payload_Last);
         Intent  : PS.Handshake_Intent := 0;
         Hello   : P.Packets.Handshake;
         Is_Hs   : constant Boolean :=
           State = PS.Handshake and then Dir = Serverbound
           and then F.Packet_Id =
             P.Ids.Protocol_Id (P.Ids.Sb_Handshake_Intention);
      begin
         if Is_Hs then
            Hello := P.Packets.Decode_Handshake (Payload);
            if Hello.Status /= P.Ok then
               R.Category := To_Unbounded_String ("malformed_packet");
               R.Detail := To_Unbounded_String ("handshake payload rejected");
               return;
            end if;
            Intent := PS.Handshake_Intent (Hello.Intent);
         end if;

         declare
            Ev : constant PS.Packet_Event :=
              (Direction => (if Dir = Serverbound then PS.Serverbound
                             else PS.Clientbound),
               Id        => PS.Packet_Id (F.Packet_Id),
               Intent    => Intent);
            T  : constant PS.Transition_Result := PS.Transition (State, Ev);
         begin
            if T.Kind = PS.Rejected then
               R.Category := To_Unbounded_String
                 (Low (PS.Rejection_Reason'Image (T.Reason)));
               R.Detail := To_Unbounded_String
                 ("state machine rejected: " & Low (PS.Rejection_Reason'Image (T.Reason)));
               return;
            end if;
            State := T.Next_State;
            R.Actual := Accepted;
            R.Pid := F.Packet_Id;
         end;

         declare
            Body_W : P.Buffer.Writer (Payload'Length + 16);
            Framed : P.Buffer.Writer (Payload'Length + 32);
         begin
            P.Buffer.Put_Varint (Body_W, Interfaces.Unsigned_32 (F.Packet_Id));
            if Is_Hs then
               P.Buffer.Put_Varint (Body_W, Hello.Version);
               P.Buffer.Put_String (Body_W, Hello.Address (1 .. Hello.Addr_Len));
               P.Buffer.Put_U16 (Body_W, Hello.Port);
               P.Buffer.Put_Varint (Body_W, Hello.Intent);
            else
               P.Buffer.Put_Bytes (Body_W, Payload);
            end if;
            if P.Packets.Frame (Framed, Body_W) and then not Framed.Failed then
               for I in 1 .. Framed.Len loop
                  R.Reencoded.Append (Framed.Data (I));
               end loop;
            end if;
         end;
      end;
   end Feed;

   --  Login session-local ordering for one replay. Mirrors the ingress
   --  Start -> Success (once) -> wait Ack -> CONFIGURATION path without
   --  touching framing/transport. Client UUID is decoded but never used;
   --  Success bytes are derived from the vanilla offline UUID.
   type Login_Track is record
      Start_Seen       : Boolean := False;
      Success_Emitted  : Boolean := False;
      Success_Verified : Boolean := False;
      Name_Len         : Natural := 0;
      Name             : String (1 .. 16) := (others => ' ');
      UUID             : Auth.Digest := (others => 0);
      Frame_Bytes      : Byte_Vectors.Vector;
   end record;

   function Valid_Login_Name (N : String) return Boolean is
   begin
      if N'Length < 1 or else N'Length > 16 then
         return False;
      end if;
      for C of N loop
         if Character'Pos (C) < 16#21#
           or else Character'Pos (C) > 16#7E#
         then
            return False;
         end if;
      end loop;
      return True;
   end Valid_Login_Name;

   function Input_Equals (Input : P.Octets; V : Byte_Vectors.Vector)
     return Boolean is
   begin
      if Natural (V.Length) /= Input'Length then
         return False;
      end if;
      for I in Input'Range loop
         if V (Natural (I - Input'First)) /= Input (I) then
            return False;
         end if;
      end loop;
      return True;
   end Input_Equals;

   procedure Replay (S : Scenario; Failure : out Unbounded_String) is
      State : PS.Connection_State := S.Initial_State;
      Idx   : Natural := 0;
      Login : Login_Track;

      procedure Fail (Expected, Actual, Detail : String) is
      begin
         Failure := To_Unbounded_String
           ("step=" & Img (Idx) & " expected=" & Expected
            & " actual=" & Actual & " detail=" & Detail);
      end Fail;
   begin
      Failure := Null_Unbounded_String;
      --  Offline derivation runs only when configuration selects offline.
      --  Corpus login scenarios are offline cases, so replay offline
      --  unless the scenario id explicitly names an online case.
      Auth.Online_Mode := False;
      declare
         Id_Low : constant String := Low (To_String (S.Id));
      begin
         if Ada.Strings.Fixed.Index (Id_Low, "online") > 0 then
            Auth.Online_Mode := True;
         end if;
      end;
      for St of S.Steps loop
         Idx := Idx + 1;
         declare
            Input  : P.Octets (1 .. Natural (St.Input.Length));
            Before : constant PS.Connection_State := State;
            R      : Feed_Result;
         begin
            for I in Input'Range loop
               Input (I) := St.Input (I);
            end loop;
            Feed (State, St.Dir, Input, R);
            --  Login ordering / Success exact-bytes layer. Runs on top of
            --  the state-machine result in R without changing framing.
            if Length (Failure) = 0 and then R.Category = Null_Unbounded_String
              and then R.Actual = Accepted
            then
               declare
                  Is_Start : constant Boolean :=
                    St.Dir = Serverbound
                    and then R.Pid =
                      P.Ids.Protocol_Id (P.Ids.Sb_Login_Hello);
                  Is_Ack : constant Boolean :=
                    St.Dir = Serverbound
                    and then R.Pid =
                      P.Ids.Protocol_Id (P.Ids.Sb_Login_Login_Acknowledged);
                  Is_Success : constant Boolean :=
                    St.Dir = Clientbound
                    and then R.Pid =
                      P.Ids.Protocol_Id (P.Ids.Cb_Login_Login_Finished);
                  Parent_Before : constant PS.Connection_State :=
                    (if Before = PS.Login_Awaiting_Ack then PS.Login
                     else Before);
               begin
                  if Is_Start and then Parent_Before = PS.Login then
                     --  Re-decode payload strictly: truncation, bad length
                     --  or trailing bytes must close with no Success.
                     declare
                        F0 : constant P.Frame.Frame_Decode :=
                          P.Frame.Decode_Frame (Input, 1);
                        Payload : constant P.Octets :=
                          Input (F0.Payload_First .. F0.Payload_Last);
                        Start : constant P.Packets.Login_Start :=
                          P.Packets.Decode_Login_Start (Payload);
                     begin
                        if Start.Status /= P.Ok then
                           R.Actual := Rejected;
                           R.Category := To_Unbounded_String ("malformed_packet");
                           R.Detail := To_Unbounded_String
                             ("login start malformed but accepted");
                        elsif not Valid_Login_Name
                          (Start.Name (1 .. Start.Name_Len))
                        then
                           R.Actual := Rejected;
                           R.Category := To_Unbounded_String ("malformed_packet");
                           R.Detail := To_Unbounded_String
                             ("invalid name but accepted");
                        elsif Auth.Online_Mode then
                           R.Actual := Rejected;
                           R.Category := To_Unbounded_String ("malformed_packet");
                           R.Detail := To_Unbounded_String
                             ("online mode must not send success");
                        elsif Login.Start_Seen then
                           R.Actual := Rejected;
                           R.Category := To_Unbounded_String ("malformed_packet");
                           R.Detail := To_Unbounded_String
                             ("duplicate login start but accepted");
                        else
                           Login.Start_Seen := True;
                           Login.Name_Len := Start.Name_Len;
                           Login.Name (1 .. Start.Name_Len) :=
                             Start.Name (1 .. Start.Name_Len);
                           Login.UUID :=
                             Auth.Offline_UUID_For_Name
                               (Start.Name (1 .. Start.Name_Len));
                           if R.Actual = Accepted then
                           --  Derive exact outbound Success frame bytes.
                           declare
                              Body_W : P.Buffer.Writer (64);
                              Framed : P.Buffer.Writer (96);
                           begin
                              P.Packets.Encode_Login_Success
                                (Body_W, P.Octets (Login.UUID),
                                 Login.Name (1 .. Login.Name_Len));
                              if Body_W.Failed
                                or else not P.Packets.Frame (Framed, Body_W)
                                or else Framed.Failed
                              then
                                 R.Actual := Rejected;
                                 R.Category := To_Unbounded_String ("malformed_packet");
                                 R.Detail := To_Unbounded_String
                                   ("success encode failed");
                              else
                                 Login.Frame_Bytes.Clear;
                                 for I in 1 .. Framed.Len loop
                                    Login.Frame_Bytes.Append
                                      (Framed.Data (I));
                                 end loop;
                                 Login.Success_Emitted := True;
                              end if;
                           end;
                           end if;
                        end if;
                     end;
                  elsif Is_Success then
                     if not Login.Success_Emitted
                       or else Login.Success_Verified
                     then
                        Fail ("rejected", "accepted",
                              "success without start or duplicate success");
                        return;
                     elsif not Input_Equals (Input, Login.Frame_Bytes) then
                        Fail ("success exact bytes", "success bytes differ",
                              "outbound login success mismatch");
                        return;
                     else
                        Login.Success_Verified := True;
                     end if;
                  elsif Is_Ack
                    and then (Before = PS.Login
                              or else Before = PS.Login_Awaiting_Ack)
                  then
                     if not Login.Success_Verified then
                        R.Actual := Rejected;
                        R.Category := To_Unbounded_String ("malformed_packet");
                        R.Detail := To_Unbounded_String
                          ("acknowledged before success but accepted");
                     end if;
                  end if;
               end;
            end if;
            --  A rejected step must never have emitted a Success for that
            --  step; Feed already stopped the replay on terminal steps.
            if R.Actual /= St.Expected then
               Fail (Low (Outcome'Image (St.Expected)),
                     Low (Outcome'Image (R.Actual)), To_String (R.Detail));
               return;
            end if;
            case R.Actual is
               when Accepted =>
                  if St.Has_Packet_Id and then R.Pid /= St.Packet_Id then
                     Fail ("packet_id=" & Img (St.Packet_Id),
                           "packet_id=" & Img (R.Pid), "packet id mismatch");
                     return;
                  end if;
                  if St.Has_State_After and then State /= St.State_After then
                     Fail ("state_after=" & Low (PS.Connection_State'Image (St.State_After)),
                           "state_after=" & Low (PS.Connection_State'Image (State)),
                           "state mismatch");
                     return;
                  end if;
                  if St.Canonical and then R.Reencoded /= St.Input then
                     Fail ("canonical", "reencoded differs",
                           "round-trip bytes differ from input");
                     return;
                  end if;
               when Rejected | Incomplete =>
                  if State /= Before then
                     Fail ("state unchanged", "state changed",
                           "state changed on terminal step");
                     return;
                  end if;
                  if St.Has_Rejection_Category
                    and then Low (To_String (St.Rejection_Category))
                             /= To_String (R.Category)
                  then
                     Fail ("category=" & To_String (St.Rejection_Category),
                           "category=" & To_String (R.Category),
                           "rejection category mismatch");
                     return;
                  end if;
                  exit;
            end case;
         end;
      end loop;
      if S.Has_Final_State and then State /= S.Final_State then
         Idx := Natural (S.Steps.Length);
         Fail ("final_state=" & Low (PS.Connection_State'Image (S.Final_State)),
               "final_state=" & Low (PS.Connection_State'Image (State)),
               "final state mismatch");
      end if;
   end Replay;

   procedure Run_All
     (Scenarios : Scenario_Vectors.Vector;
      F         : Filter;
      Summary   : out Run_Summary)
   is
      Failure : Unbounded_String;
   begin
      Summary := (others => <>);
      for S of Scenarios loop
         if (not F.Has_Id or else S.Id = F.Id)
           and then (not F.Has_Category or else S.Cat = F.Cat)
         then
            Summary.Total := Summary.Total + 1;
            Summary.Per (S.Cat) := Summary.Per (S.Cat) + 1;
            Replay (S, Failure);
            if Length (Failure) = 0 then
               Summary.Passed := Summary.Passed + 1;
            else
               Summary.Failed := Summary.Failed + 1;
               Ada.Text_IO.Put_Line
                 ("FAIL scenario=" & To_String (S.Id)
                  & " file=" & To_String (S.Path) & " " & To_String (Failure));
            end if;
         end if;
      end loop;
      Ada.Text_IO.Put_Line
        ("golden corpus: scenarios=" & Img (Summary.Total)
         & " passed=" & Img (Summary.Passed)
         & " failed=" & Img (Summary.Failed));
      declare
         Line : Unbounded_String := To_Unbounded_String ("category");
      begin
         for C in Category loop
            Append (Line, " " & Low (Category'Image (C)) & "=" & Img (Summary.Per (C)));
         end loop;
         Ada.Text_IO.Put_Line (To_String (Line));
      end;
   end Run_All;

end Adacraft.Corpus.Runner;
