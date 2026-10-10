with Ada.Strings.Unbounded;
with Ada.Text_IO;
with Adacraft.Protocol.Frame;
with Adacraft.Protocol.Handshake_Exchange;
with Adacraft.Protocol.State;
with Adacraft.Protocol.Status_Exchange;

package body Adacraft.Corpus.Runner is

   package SE renames Adacraft.Protocol.Status_Exchange;
   package HE renames Adacraft.Protocol.Handshake_Exchange;
   use Ada.Strings.Unbounded;
   use type Adacraft.Protocol.State.Connection_State;
   use type Adacraft.Protocol.Status_Kind;
   use type HE.Handle_Result;

   procedure Init_Dispatch (D : out Dispatch_Session) is
   begin
      D := (others => <>);
      SE.Reset (D.Sess);
   end Init_Dispatch;

   function Image (N : Natural) return String is
      S : constant String := Natural'Image (N);
   begin
      return S (S'First + 1 .. S'Last);
   end Image;

   procedure Replay (S : Scenario; Failure : out Unbounded_String) is
      D : Dispatch_Session;

      procedure Fail (Step_Idx : Natural; Detail : String) is
      begin
         Failure := To_Unbounded_String
           ("step=" & Image (Step_Idx) & " detail=" & Detail);
      end Fail;

   begin
      --  Per-scenario isolation: fresh server session, init to the
      --  scenario's initial state (same state type the server uses).
      Init_Dispatch (D);
      D.Proto_State := S.Initial_State;
      Failure := Null_Unbounded_String;

      declare
         Step_Idx : Natural := 0;
      begin
         for St of S.Steps loop
            Step_Idx := Step_Idx + 1;
            declare
               use type Adacraft.Corpus.Direction;
               use type Adacraft.Corpus.Outcome;
               Len : constant Natural := Natural (St.Input.Length);
            begin
               if St.Dir = Adacraft.Corpus.Clientbound then
                  --  The dispatch packages expose no entry returning
                  --  framed clientbound bytes (Handshake_Exchange.Handle
                  --  returns no bytes; Status_Exchange.Handle returns an
                  --  unframed body; the login Success framing lives in
                  --  Adacraft.Network.Handle_Frame_Body/Queue helpers,
                  --  not callable without a socket). Per the item
                  --  constraint no new entry point is added, so the
                  --  runner stops here and reports the gap: clientbound
                  --  expectations (the two login scenarios awaiting
                  --  Login Success) fail until Live Login ships.
                  Fail (Step_Idx,
                    "gap: no dispatch entry returning framed output");
                  return;
               end if;

               --  Serverbound: split the scenario blob with the existing
               --  frame decoder (only to split for feeding), then call
               --  the server dispatch Handle exactly as the server does.
               if Len = 0 then
                  if St.Expected = Adacraft.Corpus.Incomplete
                    or else St.Expected = Adacraft.Corpus.Rejected
                  then
                     null;
                  else
                     Fail (Step_Idx, "empty input accepted");
                     return;
                  end if;
               else
                  declare
                     Buf : Adacraft.Protocol.Octets (1 .. Len);
                     FD  : Adacraft.Protocol.Frame.Frame_Decode;
                     Before : Adacraft.Protocol.State.Connection_State :=
                       D.Proto_State;
                     Got_Accepted : Boolean := False;
                     Got_Incomplete : Boolean := False;
                  begin
                     for I in 1 .. Len loop
                        Buf (I) := Adacraft.Protocol.Octet
                          (St.Input.Element (I));
                     end loop;
                     FD := Adacraft.Protocol.Frame.Decode_Frame (Buf, 1);
                     if FD.Status = Adacraft.Protocol.Need_More then
                        Got_Incomplete := True;
                     elsif FD.Status /= Adacraft.Protocol.Ok then
                        Got_Accepted := False;
                     else
                        --  Decoded frame: dispatch on live state.
                        if D.Proto_State =
                          Adacraft.Protocol.State.Handshake
                        then
                           declare
                              H_Res : HE.Handle_Result;
                              Empty : constant
                                Adacraft.Protocol.Octets (2 .. 1) :=
                                  (others => <>);
                           begin
                              begin
                                 if FD.Payload_First > FD.Payload_Last then
                                    HE.Handle
                                      (Packet_Id => FD.Packet_Id,
                                       Payload   => Empty,
                                       Current   => D.Proto_State,
                                       Stored    => D.Stored,
                                       Result    => H_Res);
                                 else
                                    declare
                                       Pay : Adacraft.Protocol.Octets :=
                                         Buf (FD.Payload_First ..
                                                FD.Payload_Last);
                                    begin
                                       HE.Handle
                                         (Packet_Id => FD.Packet_Id,
                                          Payload   => Pay,
                                          Current   => D.Proto_State,
                                          Stored    => D.Stored,
                                          Result    => H_Res);
                                    end;
                                 end if;
                              exception
                                 when others =>
                                    H_Res := HE.Rejected_No_Change;
                                    D.Proto_State := Before;
                              end;
                              Got_Accepted :=
                                H_Res = HE.Accepted_Status
                                or else H_Res = HE.Accepted_Login;
                              if not Got_Accepted then
                                 D.Proto_State := Before;
                              end if;
                           end;
                        elsif D.Proto_State =
                          Adacraft.Protocol.State.Status
                        then
                           declare
                              S_Res : SE.Handle_Result;
                              Resp_Id : Natural := 0;
                              Resp_Len : Natural := 0;
                              Want_Close : Boolean := False;
                              Resp_Buf :
                                Adacraft.Protocol.Octets (1 .. 4_096) :=
                                  (others => 0);
                              Empty : constant
                                Adacraft.Protocol.Octets (2 .. 1) :=
                                  (others => <>);
                              use type SE.Handle_Result;
                           begin
                              begin
                                 if FD.Payload_First > FD.Payload_Last then
                                    SE.Handle
                                      (Packet_Id => FD.Packet_Id,
                                       Payload => Empty,
                                       Current => D.Proto_State,
                                       Session_State => D.Sess,
                                       Result => S_Res,
                                       Response_Id => Resp_Id,
                                       Response_Data => Resp_Buf,
                                       Response_Len => Resp_Len,
                                       Close_Connection => Want_Close);
                                 else
                                    declare
                                       Pay : Adacraft.Protocol.Octets :=
                                         Buf (FD.Payload_First ..
                                                FD.Payload_Last);
                                    begin
                                       SE.Handle
                                         (Packet_Id => FD.Packet_Id,
                                          Payload => Pay,
                                          Current => D.Proto_State,
                                          Session_State => D.Sess,
                                          Result => S_Res,
                                          Response_Id => Resp_Id,
                                          Response_Data => Resp_Buf,
                                          Response_Len => Resp_Len,
                                          Close_Connection => Want_Close);
                                    end;
                                 end if;
                              exception
                                 when others =>
                                    S_Res := SE.Rejected_Close;
                                    D.Proto_State := Before;
                              end;
                              if S_Res = SE.Rejected_Close then
                                 Got_Accepted := False;
                                 D.Proto_State := Before;
                              else
                                 Got_Accepted := True;
                              end if;
                              if Want_Close and then Resp_Len = 0
                                and then S_Res = SE.Rejected_Close
                              then
                                 Got_Accepted := False;
                              end if;
                           end;
                        else
                           --  Login and later states: the live Login
                           --  Success/Disconnect framing lives in
                           --  Adacraft.Network (socket-bound) with no
                           --  callable dispatch entry. Do not assemble
                           --  Login output in the runner. Serverbound
                           --  login bytes therefore cannot be accepted
                           --  here; accepted expectations fail until
                           --  Live Login ships, rejected expectations
                           --  pass as rejections with state unchanged.
                           Got_Accepted := False;
                           D.Proto_State := Before;
                        end if;
                     end if;

                     if Got_Incomplete then
                        if St.Expected /= Adacraft.Corpus.Incomplete then
                           Fail (Step_Idx, "expected incomplete");
                           return;
                        end if;
                        D.Proto_State := Before;
                     elsif Got_Accepted then
                        if St.Expected /= Adacraft.Corpus.Accepted then
                           Fail (Step_Idx, "unexpected accept");
                           return;
                        end if;
                     else
                        if St.Expected /= Adacraft.Corpus.Rejected then
                           Fail (Step_Idx, "expected accepted");
                           return;
                        end if;
                        D.Proto_State := Before;
                     end if;

                     if St.Has_State_After
                       and then St.Expected = Adacraft.Corpus.Accepted
                       and then D.Proto_State /= St.State_After
                     then
                        Fail (Step_Idx, "state_after mismatch");
                        return;
                     end if;
                  exception
                     when others =>
                        --  Per-feed isolation: malformed frame marks the
                        --  scenario failed, never aborts the corpus run.
                        D.Proto_State := Before;
                        if St.Expected = Adacraft.Corpus.Rejected
                          or else St.Expected = Adacraft.Corpus.Incomplete
                        then
                           null;
                        else
                           Fail (Step_Idx, "dispatch raised");
                           return;
                        end if;
                  end;
               end if;
            end;
         end loop;
      end;

      if S.Has_Final_State and then D.Proto_State /= S.Final_State then
         Fail (0, "final_state mismatch");
         return;
      end if;
      Failure := Null_Unbounded_String;
   exception
      when others =>
         Failure := To_Unbounded_String ("dispatch raised");
   end Replay;

   procedure Run_All
     (Scenarios : Scenario_Vectors.Vector;
      F : Filter;
      Summary : out Run_Summary)
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
                  & " file=" & To_String (S.Path)
                  & " " & To_String (Failure));
            end if;
         end if;
      end loop;
      Ada.Text_IO.Put_Line
        ("golden corpus: scenarios="
         & Natural'Image (Summary.Total)
         & " passed=" & Natural'Image (Summary.Passed)
         & " failed=" & Natural'Image (Summary.Failed));
   end Run_All;

end Adacraft.Corpus.Runner;
