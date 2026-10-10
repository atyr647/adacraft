with Ada.Strings.Unbounded;
with Ada.Text_IO;
with Ada.Unchecked_Deallocation;
with Adacraft.Auth;
with Interfaces;
with Adacraft.Protocol.Buffer;
with Adacraft.Protocol.Frame;
with Adacraft.Protocol.Handshake_Exchange;
with Adacraft.Protocol.Login;
with Adacraft.Protocol.State;
with Adacraft.Protocol.State.Table;
with Adacraft.Protocol.Status_Exchange;
with Adacraft.Protocol.Varnum;

package body Adacraft.Corpus.Runner is

   package SE renames Adacraft.Protocol.Status_Exchange;
   package HE renames Adacraft.Protocol.Handshake_Exchange;
   package Tbl renames Adacraft.Protocol.State.Table;
   use Ada.Strings.Unbounded;
   use type Adacraft.Protocol.State.Connection_State;
   use type Adacraft.Protocol.Status_Kind;
   use type HE.Handle_Result;
   use type SE.Handle_Result;
   use type Adacraft.Protocol.Login.Login_Start_Status;

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

   --  Frame a ready protocol body (packet id included) exactly as
   --  Adacraft.Network.Queue_Framed does: length prefix + body,
   --  appended to the per-scenario pending queue.
   procedure Queue_Framed
     (D : in out Dispatch_Session; Body_Data : Adacraft.Protocol.Octets)
   is
   begin
      if Body_Data'Length = 0 then
         return;
      end if;
      --  Reuse the server's own length-prefix writer via Varnum:
      --  encode body length as VarInt bytes, then body bytes.
      declare
         W : Adacraft.Protocol.Buffer.Writer (8);
      begin
         Adacraft.Protocol.Buffer.Reset (W);
         Adacraft.Protocol.Buffer.Put_Varint
           (W, Interfaces.Unsigned_32 (Body_Data'Length));
         if W.Failed then
            return;
         end if;
         for I in 1 .. W.Len loop
            D.Pending.Append (Interfaces.Unsigned_8 (W.Data (I)));
         end loop;
      end;
      for I in Body_Data'Range loop
         D.Pending.Append (Interfaces.Unsigned_8 (Body_Data (I)));
      end loop;
   end Queue_Framed;

   procedure Queue_Status_Response
     (D : in out Dispatch_Session;
      Response_Id : Natural;
      Resp : Adacraft.Protocol.Octets;
      Resp_Len : Natural)
   is
      --  Small stack-only temporaries: VarInt encodings are at most
      --  5 bytes each, so no large Writer lives on the stack here
      --  (a 33 KB Writer overflowed the task stack with STORAGE_ERROR).
      WI : Adacraft.Protocol.Buffer.Writer (8);
      WL : Adacraft.Protocol.Buffer.Writer (8);
      Id_Len : Natural := 0;
      Id_Bytes : Adacraft.Protocol.Octets (1 .. 5) := (others => 0);
      Len_Len : Natural := 0;
      Len_Bytes : Adacraft.Protocol.Octets (1 .. 5) := (others => 0);
      Total : Natural;
   begin
      if Resp_Len = 0 then
         return;
      end if;
      Adacraft.Protocol.Buffer.Reset (WI);
      Adacraft.Protocol.Buffer.Put_Varint
        (WI, Interfaces.Unsigned_32 (Response_Id));
      if WI.Failed or else WI.Len = 0 or else WI.Len > 5 then
         return;
      end if;
      Id_Len := WI.Len;
      for I in 1 .. Id_Len loop
         Id_Bytes (I) := WI.Data (I);
      end loop;
      Total := Id_Len + Resp_Len;
      Adacraft.Protocol.Buffer.Reset (WL);
      Adacraft.Protocol.Buffer.Put_Varint
        (WL, Interfaces.Unsigned_32 (Total));
      if WL.Failed or else WL.Len = 0 or else WL.Len > 5 then
         return;
      end if;
      Len_Len := WL.Len;
      for I in 1 .. Len_Len loop
         Len_Bytes (I) := WL.Data (I);
      end loop;
      for I in 1 .. Len_Len loop
         D.Pending.Append (Interfaces.Unsigned_8 (Len_Bytes (I)));
      end loop;
      for I in 1 .. Id_Len loop
         D.Pending.Append (Interfaces.Unsigned_8 (Id_Bytes (I)));
      end loop;
      for I in 1 .. Resp_Len loop
         D.Pending.Append
           (Interfaces.Unsigned_8 (Resp (Resp'First + I - 1)));
      end loop;
   end Queue_Status_Response;

   function Pending_Matches
     (D : Dispatch_Session; St : Step) return Boolean
   is
   begin
      if Natural (D.Pending.Length) /= Natural (St.Input.Length) then
         return False;
      end if;
      for I in 1 .. Natural (St.Input.Length) loop
         if D.Pending (I) /= St.Input (I) then
            return False;
         end if;
      end loop;
      return True;
   end Pending_Matches;

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
                  --  Clientbound expectation: the live path must have
                  --  queued exactly these framed bytes on the previous
                  --  serverbound step. Accepted means byte-equal;
                  --  rejected (wrong-direction probe) means no pending
                  --  output corresponds to that input.
                  if St.Expected = Adacraft.Corpus.Accepted then
                     if not Pending_Matches (D, St) then
                        Fail (Step_Idx, "clientbound output mismatch");
                        return;
                     end if;
                     D.Pending.Clear;
                  else
                     --  Rejected clientbound: only passes when the
                     --  queued output does not match (wrong-direction
                     --  bytes are never emitted by the server).
                     if Pending_Matches (D, St)
                       and then not D.Pending.Is_Empty
                     then
                        Fail (Step_Idx, "unexpected clientbound bytes");
                        return;
                     end if;
                  end if;
                  if St.Has_State_After
                    and then D.Proto_State /= St.State_After
                  then
                     Fail (Step_Idx, "state_after mismatch");
                     return;
                  end if;
                  goto Next_Step;
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
                     type Octet_Acc is access Adacraft.Protocol.Octets;
                     procedure Free_Oct is new Ada.Unchecked_Deallocation
                       (Adacraft.Protocol.Octets, Octet_Acc);
                     Buf : Octet_Acc :=
                       new Adacraft.Protocol.Octets (1 .. Len);
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
                     FD := Adacraft.Protocol.Frame.Decode_Frame (Buf.all, 1);
                     if FD.Status = Adacraft.Protocol.Need_More then
                        Got_Incomplete := True;
                     elsif FD.Status /= Adacraft.Protocol.Ok then
                        Got_Accepted := False;
                     elsif FD.Next /= Len + 1 then
                        --  Trailing bytes: not exactly one frame.
                        Got_Accepted := False;
                     elsif D.Closing then
                        Got_Accepted := False;
                        D.Proto_State := Before;
                     else
                        --  Decoded frame: dispatch on live state,
                        --  mirroring Adacraft.Network.Handle_Frame_Body.
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
                                 elsif FD.Payload_First >= Buf'First
                                   and then FD.Payload_Last <= Buf'Last
                                 then
                                    HE.Handle
                                      (Packet_Id => FD.Packet_Id,
                                       Payload   => Buf
                                         (FD.Payload_First ..
                                            FD.Payload_Last),
                                       Current   => D.Proto_State,
                                       Stored    => D.Stored,
                                       Result    => H_Res);
                                 else
                                    H_Res := HE.Rejected_No_Change;
                                    D.Proto_State := Before;
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
                              type Resp_Acc is access
                                Adacraft.Protocol.Octets;
                              procedure Free_Resp is new
                                Ada.Unchecked_Deallocation
                                  (Adacraft.Protocol.Octets, Resp_Acc);
                              Resp_Buf : Resp_Acc := new
                                Adacraft.Protocol.Octets (1 .. 33_008);
                              Empty : constant
                                Adacraft.Protocol.Octets (2 .. 1) :=
                                  (others => <>);
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
                                       Response_Data => Resp_Buf.all,
                                       Response_Len => Resp_Len,
                                       Close_Connection => Want_Close);
                                 else
                                    SE.Handle
                                      (Packet_Id => FD.Packet_Id,
                                       Payload => Buf
                                         (FD.Payload_First ..
                                            FD.Payload_Last),
                                       Current => D.Proto_State,
                                       Session_State => D.Sess,
                                       Result => S_Res,
                                       Response_Id => Resp_Id,
                                       Response_Data => Resp_Buf.all,
                                       Response_Len => Resp_Len,
                                       Close_Connection => Want_Close);
                                 end if;
                              exception
                                 when others =>
                                    S_Res := SE.Rejected_Close;
                                    Resp_Len := 0;
                                    Want_Close := True;
                                    D.Proto_State := Before;
                              end;
                              if S_Res = SE.Rejected_Close
                                and then Resp_Len = 0
                              then
                                 Got_Accepted := False;
                                 D.Proto_State := Before;
                                 D.Closing := True;
                              else
                                 Got_Accepted := True;
                                 if Resp_Len > 0 then
                                    Queue_Status_Response
                                      (D, Resp_Id, Resp_Buf.all, Resp_Len);
                                 end if;
                                 if Want_Close then
                                    D.Closing := True;
                                 end if;
                              end if;
                              Free_Resp (Resp_Buf);
                           end;
                        elsif D.Proto_State =
                          Adacraft.Protocol.State.Login
                        then
                           --  LOGIN dispatch, same gates as the live
                           --  Handle_Frame_Body: duplicate Start when a
                           --  reply is already queued closes; table
                           --  validity; single Login decoder; malformed
                           --  closes silently; invalid name queues one
                           --  Disconnect; well-formed queues one framed
                           --  Success via Encode_Login_Success and
                           --  moves to Login_Awaiting_Ack.
                           if not D.Pending.Is_Empty or else D.Closing then
                              Got_Accepted := False;
                              D.Proto_State := Before;
                              D.Closing := True;
                           elsif Tbl.Find
                             (State => Adacraft.Protocol.State.Login,
                              Dir => Adacraft.Protocol.State.Serverbound,
                              Id => Adacraft.Protocol.State.Packet_Id
                                (FD.Packet_Id)) = 0
                             or else not Tbl.Is_Login_Start_Id
                               (Adacraft.Protocol.State.Packet_Id
                                  (FD.Packet_Id))
                           then
                              Got_Accepted := False;
                              D.Proto_State := Before;
                              D.Closing := True;
                           else
                              declare
                                 LS : Adacraft.Protocol.Login.Login_Start;
                                 Empty : constant
                                   Adacraft.Protocol.Octets (2 .. 1) :=
                                     (others => <>);
                              begin
                                 if FD.Payload_First > FD.Payload_Last then
                                    LS := Adacraft.Protocol.Login
                                      .Decode_Login_Start (Empty);
                                 else
                                    LS := Adacraft.Protocol.Login
                                      .Decode_Login_Start
                                        (Buf (FD.Payload_First ..
                                           FD.Payload_Last));
                                 end if;
                                 if LS.Status =
                                   Adacraft.Protocol.Login.Malformed
                                 then
                                    Got_Accepted := False;
                                    D.Proto_State := Before;
                                    D.Closing := True;
                                 elsif LS.Status =
                                   Adacraft.Protocol.Login.Invalid_Name
                                 then
                                    Queue_Framed
                                      (D, Adacraft.Protocol.Login
                                         .Build_Login_Disconnect
                                           (Adacraft.Protocol.Login
                                              .Invalid_Name_Reason));
                                    Got_Accepted := False;
                                    D.Proto_State := Before;
                                    D.Closing := True;
                                 else
                                    declare
                                       Name_Str : constant String :=
                                         LS.Name (1 .. LS.Name_Len);
                                       Ident : constant Adacraft
                                         .Auth.Player_Identity :=
                                         Adacraft.Protocol.Login
                                           .Offline_Identity (Name_Str);
                                       W : Adacraft.Protocol.Buffer
                                         .Writer (64);
                                    begin
                                       Adacraft.Protocol.Buffer.Reset (W);
                                       Adacraft.Protocol.Login
                                         .Encode_Login_Success (W, Ident);
                                       if not W.Failed and then W.Len > 0
                                       then
                                          declare
                                             Succ : Adacraft.Protocol
                                               .Octets (1 .. W.Len);
                                          begin
                                             for I in 1 .. W.Len loop
                                                Succ (I) := W.Data (I);
                                             end loop;
                                             Queue_Framed (D, Succ);
                                          end;
                                       end if;
                                    end;
                                    D.Proto_State :=
                                      Adacraft.Protocol.State
                                        .Login_Awaiting_Ack;
                                    Got_Accepted := True;
                                 end if;
                              end;
                           end if;
                        elsif D.Proto_State =
                          Adacraft.Protocol.State.Login_Awaiting_Ack
                        then
                           declare
                              Got_Id : constant Adacraft.Protocol.State
                                .Packet_Id :=
                                Adacraft.Protocol.State.Packet_Id
                                  (FD.Packet_Id);
                              Is_Start : constant Boolean :=
                                Tbl.Is_Login_Start_Id (Got_Id);
                              Is_Ack : constant Boolean :=
                                Tbl.Is_Login_Ack_Id (Got_Id);
                              Has_Body : constant Boolean :=
                                FD.Payload_First <= FD.Payload_Last;
                           begin
                              if Is_Start then
                                 Queue_Framed
                                   (D, Adacraft.Protocol.Login
                                      .Build_Login_Disconnect
                                        (Adacraft.Protocol.Login
                                           .Default_Disconnect_Reason));
                                 Got_Accepted := False;
                                 D.Proto_State := Before;
                                 D.Closing := True;
                              elsif Is_Ack then
                                 if not Has_Body then
                                    D.Proto_State :=
                                      Adacraft.Protocol.State.Configuration;
                                    Got_Accepted := True;
                                 else
                                    Queue_Framed
                                      (D, Adacraft.Protocol.Login
                                         .Build_Login_Disconnect
                                           (Adacraft.Protocol.Login
                                              .Default_Disconnect_Reason));
                                    Got_Accepted := False;
                                    D.Proto_State := Before;
                                    D.Closing := True;
                                 end if;
                              else
                                 Got_Accepted := False;
                                 D.Proto_State := Before;
                                 D.Closing := True;
                              end if;
                           end;
                        else
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

                     if St.Has_Packet_Id
                       and then St.Expected = Adacraft.Corpus.Accepted
                       and then FD.Packet_Id /= St.Packet_Id
                     then
                        Free_Oct (Buf);
                        Fail (Step_Idx, "packet id mismatch");
                        return;
                     end if;

                     if St.Has_State_After
                       and then St.Expected = Adacraft.Corpus.Accepted
                       and then D.Proto_State /= St.State_After
                     then
                        Free_Oct (Buf);
                        Fail (Step_Idx, "state_after mismatch");
                        return;
                     end if;
                     Free_Oct (Buf);
                  exception
                     when others =>
                        --  Per-feed isolation: malformed frame marks the
                        --  scenario failed, never aborts the corpus run.
                        if Buf /= null then
                           Free_Oct (Buf);
                        end if;
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
               <<Next_Step>>
               null;
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
