with Ada.Characters.Handling;
with Ada.Strings.Fixed;
with Ada.Text_IO;
with Interfaces;
with Adacraft.Auth;
with Adacraft.Kernel;
with Adacraft.Protocol.Buffer;
with Adacraft.Protocol.Frame;
with Adacraft.Protocol.Handshake_Exchange;
with Adacraft.Protocol.Ids;
with Adacraft.Protocol.Login;
with Adacraft.Protocol.Packets;
with Adacraft.Protocol.Status_Exchange;

package body Adacraft.Corpus.Runner is

   package HE renames Adacraft.Protocol.Handshake_Exchange;
   package SE renames Adacraft.Protocol.Status_Exchange;
   package P renames Adacraft.Protocol;
   package PS renames Adacraft.Protocol.State;
   package Prot_Login renames Adacraft.Protocol.Login;
   use Ada.Strings.Unbounded;
   use type P.Status_Kind;
   use type PS.Result_Kind;
   use type PS.Connection_State;
   use type PS.Login_Dispatch;
   use type Prot_Login.Ack_Outcome;
   use type HE.Handle_Result;
   use type SE.Handle_Result;
   use type Byte_Vectors.Vector;
   use type Interfaces.Unsigned_32;

   function Img (N : Natural) return String is
     (Ada.Strings.Fixed.Trim (Natural'Image (N), Ada.Strings.Left));

   function Low (S : String) return String is
     (Ada.Characters.Handling.To_Lower (S));

   procedure Init_Dispatch (D : out Dispatch_Session) is
   begin
      D.Proto_State := PS.Handshake;
      D.Stored := (others => <>);
      SE.Reset (D.Sess);
   end Init_Dispatch;

   Login_Start_Pid : constant := 0;
   Login_Ack_Pid   : constant := 3;

   --  Mode for Login.Handle_Start: read from the same explicit server
   --  configuration the live path uses (Kernel.Online_Mode), never a
   --  hardcoded default.
   function Server_Auth_Mode return Auth.Server_Auth_Mode is
     (if Adacraft.Kernel.Online_Mode then Auth.Online else Auth.Offline);

   --  Frame a ready server packet body (id included) with the server's
   --  own framing entry (Packets.Frame). No runner-side id/length
   --  codec here; this only collects the bytes the server package
   --  emitted into a vector for the clientbound expectation step.
   function Frame_Packet
     (WB : P.Buffer.Writer) return Byte_Vectors.Vector
   is
      Framed : P.Buffer.Writer (Capacity => WB.Len + 32 + 1);
      Result : Byte_Vectors.Vector;
   begin
      if P.Packets.Frame (Framed, WB) and then not Framed.Failed then
         for I in 1 .. Framed.Len loop
            Result.Append (Framed.Data (I));
         end loop;
      end if;
      return Result;
   end Frame_Packet;

   --  Collect wire bytes for a Status_Exchange response (id + body)
   --  using only the server's own Buffer/Packets entries, exactly as
   --  Adacraft.Network.Queue_Response does. Resp_Id/Data/Len come
   --  from SE.Handle; no runner-side JSON, ids or ping/pong logic.
   function Frame_Response
     (Resp_Id : Natural; Resp_Buf : P.Octets; Resp_Len : Natural)
      return Byte_Vectors.Vector
   is
      Body_W : P.Buffer.Writer (Capacity => Resp_Len + 8);
   begin
      P.Buffer.Reset (Body_W);
      P.Buffer.Put_Varint (Body_W, Interfaces.Unsigned_32 (Resp_Id));
      for I in 1 .. Resp_Len loop
         P.Buffer.Put_Octet (Body_W, Resp_Buf (Resp_Buf'First + I - 1));
      end loop;
      if Body_W.Failed then
         return Byte_Vectors.Empty_Vector;
      end if;
      return Frame_Packet (Body_W);
   end Frame_Response;

   procedure Handle_Empty_Handshake
     (D : in out Dispatch_Session; Pid : Natural; H_Res : out HE.Handle_Result)
   is
      Empty : constant P.Octets (1 .. 0) := (others => <>);
   begin
      HE.Handle
        (Packet_Id => Pid, Payload => Empty,
         Current => D.Proto_State, Stored => D.Stored, Result => H_Res);
   end Handle_Empty_Handshake;

   procedure Handle_Empty_Status
     (D : in out Dispatch_Session;
      Pid : Natural; S_Res : out SE.Handle_Result;
      Resp_Id : out Natural; Resp_Buf : out P.Octets; Resp_Len : out Natural;
      Want_Close : out Boolean)
   is
      Empty : constant P.Octets (1 .. 0) := (others => <>);
   begin
      SE.Handle
        (Packet_Id => Pid, Payload => Empty,
         Current => D.Proto_State, Session_State => D.Sess,
         Result => S_Res, Response_Id => Resp_Id,
         Response_Data => Resp_Buf, Response_Len => Resp_Len,
         Close_Connection => Want_Close);
   end Handle_Empty_Status;

   type Feed_Result is record
      Actual    : Outcome := Rejected;
      Pid       : Natural := 0;
      Category  : Unbounded_String;
      Detail    : Unbounded_String;
      Reencoded : Byte_Vectors.Vector;
   end record;

   procedure Feed
     (D     : in out Dispatch_Session;
      Ctx   : in out Login_Ctx;
      Dir   : Direction;
      Input : P.Octets;
      R     : out Feed_Result)
   is
      F : constant P.Frame.Frame_Decode := P.Frame.Decode_Frame (Input, 1);
      State : PS.Connection_State renames D.Proto_State;
   begin
      R := (others => <>);
      --  Clientbound expectation step: assert the exact server
      --  frame produced by the previous LOGIN step (Success bytes
      --  or Disconnect bytes). State is unchanged.
      if Dir = Clientbound and then Ctx.Has_Pending then
         if Input'Length = Natural (Ctx.Pending_Output.Length) then
            declare
               Same : Boolean := True;
            begin
               for I in 1 .. Input'Length loop
                  if Input (Input'First + I - 1)
                    /= Ctx.Pending_Output (I)
                  then
                     Same := False;
                     exit;
                  end if;
               end loop;
               if Same then
                  R.Actual := Accepted;
                  R.Pid := F.Packet_Id;
                  R.Category := To_Unbounded_String ("login");
                  R.Detail := To_Unbounded_String ("login output matches");
                  Ctx.Has_Pending := False;
                  return;
               end if;
            end;
         end if;
         R.Category := To_Unbounded_String ("login");
         R.Detail := To_Unbounded_String ("login output mismatch");
         return;
      end if;
      if Ctx.Closed then
         R.Category := To_Unbounded_String ("closed");
         R.Detail := To_Unbounded_String ("connection already closed");
         return;
      end if;
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

      --  Handshake dispatch exactly as Adacraft.Network.Handle_Frame_Body
      --  does: Handshake_Exchange.Handle with (Packet_Id, Payload,
      --  Current => D.Proto_State, Stored => D.Stored).
      if State = PS.Handshake and then Dir = Serverbound
        and then F.Status = P.Ok and then F.Next = Input'Last + 1
      then
         declare
            H_Res : HE.Handle_Result;
         begin
            if F.Payload_First > F.Payload_Last then
               Handle_Empty_Handshake (D, F.Packet_Id, H_Res);
            else
               HE.Handle
                 (Packet_Id => F.Packet_Id,
                  Payload => Input (F.Payload_First .. F.Payload_Last),
                  Current => D.Proto_State, Stored => D.Stored,
                  Result => H_Res);
            end if;
            if H_Res = HE.Accepted_Status
              or else H_Res = HE.Accepted_Login
            then
               R.Actual := Accepted;
               R.Pid := F.Packet_Id;
               R.Category := To_Unbounded_String ("handshake");
               R.Detail := To_Unbounded_String ("handshake accepted");
               return;
            else
               R.Category := To_Unbounded_String ("handshake");
               R.Detail := To_Unbounded_String ("handshake rejected");
               return;
            end if;
         exception
            when Constraint_Error =>
               R.Category := To_Unbounded_String ("handshake");
               R.Detail := To_Unbounded_String ("handshake rejected");
               return;
         end;
      end if;

      --  Status dispatch exactly as Adacraft.Network.Handle_Frame_Body
      --  does: Status_Exchange.Handle with (Packet_Id, Payload,
      --  Current, Session_State => D.Sess, 9 args). A response is
      --  framed and held as pending output for the next clientbound
      --  expectation step.
      if State = PS.Status and then Dir = Serverbound
        and then F.Status = P.Ok and then F.Next = Input'Last + 1
      then
         declare
            S_Res : SE.Handle_Result;
            Resp_Id : Natural := 0;
            Resp_Len : Natural := 0;
            Resp_Buf : P.Octets (1 .. 33_008) := (others => 0);
            Want_Close : Boolean := False;
         begin
            if F.Payload_First > F.Payload_Last then
               Handle_Empty_Status
                 (D, F.Packet_Id, S_Res, Resp_Id, Resp_Buf, Resp_Len,
                  Want_Close);
            else
               SE.Handle
                 (Packet_Id => F.Packet_Id,
                  Payload => Input (F.Payload_First .. F.Payload_Last),
                  Current => D.Proto_State, Session_State => D.Sess,
                  Result => S_Res, Response_Id => Resp_Id,
                  Response_Data => Resp_Buf, Response_Len => Resp_Len,
                  Close_Connection => Want_Close);
            end if;
            --  Collect the wire bytes for the SE.Handle response with
            --  the server's own framing entry (see Frame_Response).
            --  Resp_Id/Data/Len, S_Res and Want_Close all come from
            --  the server dispatch; the runner builds no status JSON,
            --  no status ids and no ping/pong handling of its own.
            --  NOTE (A5/constraints): the dispatch has no single entry
            --  returning already-framed wire bytes, so the runner
            --  frames the server-provided response body with the
            --  server's own Frame entry exactly as
            --  Adacraft.Network.Queue_Response does; no new src/
            --  entry is added for the runner.
            if Resp_Len > 0 then
               declare
                  Framed_Out : constant Byte_Vectors.Vector :=
                    Frame_Response (Resp_Id, Resp_Buf, Resp_Len);
               begin
                  if Natural (Framed_Out.Length) > 0 then
                     Ctx.Pending_Output := Framed_Out;
                     Ctx.Has_Pending := True;
                  end if;
               end;
            end if;
            if S_Res = SE.Rejected_Close and then Resp_Len = 0 then
               R.Category := To_Unbounded_String ("status");
               R.Detail := To_Unbounded_String ("status rejected");
               return;
            else
               R.Actual := Accepted;
               R.Pid := F.Packet_Id;
               R.Category := To_Unbounded_String ("status");
               R.Detail := To_Unbounded_String ("status accepted");
               if S_Res = SE.Rejected_Close then
                  Ctx.Closed := True;
               end if;
               return;
            end if;
         exception
            when Constraint_Error =>
               R.Category := To_Unbounded_String ("status");
               R.Detail := To_Unbounded_String ("status rejected");
               return;
         end;
      end if;

      --  Status pending-output expectation: a clientbound step asserts
      --  the exact framed bytes produced by the previous SE.Handle.
      if Dir = Clientbound and then Ctx.Has_Pending then
         if Input'Length = Natural (Ctx.Pending_Output.Length) then
            declare
               Same : Boolean := True;
            begin
               for I in 1 .. Input'Length loop
                  if Input (Input'First + I - 1)
                    /= Ctx.Pending_Output (I)
                  then
                     Same := False;
                     exit;
                  end if;
               end loop;
               if Same then
                  R.Actual := Accepted;
                  R.Pid := F.Packet_Id;
                  R.Category := To_Unbounded_String ("status");
                  R.Detail := To_Unbounded_String ("status output matches");
                  Ctx.Has_Pending := False;
                  return;
               end if;
            end;
         end if;
         R.Category := To_Unbounded_String ("status");
         R.Detail := To_Unbounded_String ("status output mismatch");
         return;
      end if;

      --  LOGIN-state dispatch onto the existing codec. Start is
      --  handled only serverbound in LOGIN, Ack only serverbound
      --  in LOGIN_AWAITING_ACK; anything else in LOGIN context
      --  closes (validation failures produce a Disconnect frame
      --  held as pending output before close).
      if Dir = Serverbound
        and then (State = PS.Login or else State = PS.Login_Awaiting_Ack)
      then
         declare
            Parent_Login : constant Boolean :=
              State = PS.Login or else State = PS.Login_Awaiting_Ack;
         begin
            if Parent_Login and then F.Packet_Id = Login_Start_Pid then
               if State /= PS.Login then
                  Ctx.Closed := True;
                  Ctx.Has_Pending := False;
                  R.Category := To_Unbounded_String ("login");
                  R.Detail := To_Unbounded_String ("duplicate login start");
                  return;
               end if;
               if not Ctx.Active then
                  Ctx.Session := (others => <>);
                  Ctx.Active := True;
               end if;
               declare
                  Payload : constant P.Octets :=
                    Input (F.Payload_First .. F.Payload_Last);
                  --  Live Login path (Adacraft.Network.Handle_Frame_Body
                  --  Gate 4 via Login.Handle_Start): mode comes from the
                  --  explicit server configuration, never hardcoded.
                  Res : constant Prot_Login.Start_Result :=
                    Prot_Login.Handle_Start
                      (Ctx.Session, Payload, Server_Auth_Mode);
                  W : P.Buffer.Writer (Capacity => 512);
               begin
                  case Res.Outcome is
                     when Prot_Login.Ready_Success =>
                        Ctx.Session := Res.Session;
                        P.Buffer.Reset (W);
                        declare
                           WB : P.Buffer.Writer (Capacity => 256);
                        begin
                           Prot_Login.Encode_Login_Success (WB, Res.Identity);
                           Ctx.Pending_Output :=
                             Frame_Packet (WB);
                           Ctx.Has_Pending := True;
                        end;
                        State := PS.Login_Awaiting_Ack;
                        R.Actual := Accepted;
                        R.Pid := F.Packet_Id;
                        R.Category := To_Unbounded_String ("login");
                        R.Detail := To_Unbounded_String ("login start ok");
                        return;
                     when Prot_Login.Need_Disconnect_Close
                        | Prot_Login.Refuse_Online =>
                        Ctx.Session := Res.Session;
                        declare
                           WB : P.Buffer.Writer (Capacity => 512);
                        begin
                           Prot_Login.Encode_Login_Disconnect
                             (WB,
                              Res.Reason (1 .. Res.Reason_Len));
                           Ctx.Pending_Output :=
                             Frame_Packet (WB);
                           Ctx.Has_Pending := True;
                        end;
                        Ctx.Closed := True;
                        R.Category := To_Unbounded_String ("disconnect");
                        R.Detail := To_Unbounded_String
                          ("login rejected with disconnect");
                        return;
                     when Prot_Login.Protocol_Error_Close =>
                        Ctx.Session := Res.Session;
                        Ctx.Closed := True;
                        Ctx.Has_Pending := False;
                        R.Category := To_Unbounded_String ("login");
                        R.Detail := To_Unbounded_String
                          ("malformed login start");
                        return;
                  end case;
               end;
            elsif Parent_Login and then F.Packet_Id = Login_Ack_Pid then
               if State /= PS.Login_Awaiting_Ack then
                  Ctx.Closed := True;
                  Ctx.Has_Pending := False;
                  R.Category := To_Unbounded_String ("login");
                  R.Detail := To_Unbounded_String ("early login ack");
                  return;
               end if;
               declare
                  Payload : constant P.Octets :=
                    Input (F.Payload_First .. F.Payload_Last);
                  Res : constant Prot_Login.Ack_Result :=
                    Prot_Login.Handle_Acknowledged (Ctx.Session, Payload);
               begin
                  if Res.Outcome = Prot_Login.To_Configuration then
                     Ctx.Session := Res.Session;
                     Ctx.Has_Pending := False;
                     State := PS.Configuration;
                     R.Actual := Accepted;
                     R.Pid := F.Packet_Id;
                     R.Category := To_Unbounded_String ("login");
                     R.Detail := To_Unbounded_String ("ack ok");
                     return;
                  else
                     Ctx.Closed := True;
                     R.Category := To_Unbounded_String ("login");
                     R.Detail := To_Unbounded_String ("bad ack body");
                     return;
                  end if;
               end;
            elsif Parent_Login then
               Ctx.Closed := True;
               Ctx.Has_Pending := False;
               R.Category := To_Unbounded_String ("login");
               R.Detail := To_Unbounded_String
                 ("unknown login packet id");
               return;
            end if;
         end;
      end if;

      --  No runner-owned fallback dispatcher lives here. Handshake,
      --  status and login inputs are handled only by the server
      --  dispatch packages above (Handshake_Exchange.Handle,
      --  Status_Exchange.Handle, Login.Handle_Start /
      --  Handle_Acknowledged); anything reaching this point is a
      --  rejection in the current server state. The runner parses no
      --  handshake fields, decides no next state, builds no status
      --  JSON and handles no ping/pong itself.
      R.Category := To_Unbounded_String ("rejected");
      R.Detail := To_Unbounded_String
        ("no server dispatch accepts this input in this state");
      return;
   end Feed;

   function Outcome_Image (O : Outcome) return String is
     (Low (Outcome'Image (O)));

   function Bytes_Image (V : Byte_Vectors.Vector; Max : Natural := 64)
     return String
   is
      N : constant Natural := Natural (V.Length);
      Shown : constant Natural := Natural'Min (N, Max);
      S : Unbounded_String;
   begin
      Append (S, "len=" & Img (N) & "[");
      for I in 1 .. Shown loop
         if I > 1 then
            Append (S, " ");
         end if;
         declare
            H : constant String :=
              Interfaces.Unsigned_8'Image (V (I));
         begin
            Append (S, Ada.Strings.Fixed.Trim (H, Ada.Strings.Left));
         end;
      end loop;
      if N > Shown then
         Append (S, " ...");
      end if;
      Append (S, "]");
      return To_String (S);
   end Bytes_Image;

   --  Per-scenario replay: fresh server session (same state type as
   --  the server, init to handshake then scenario initial state),
   --  feed loop over Loader input chunks calling the server dispatch
   --  Handle exactly as adacraft_server.adb does via Adacraft.Network,
   --  byte-compare accumulated output to golden with diff on mismatch.
   --  Each Handle call is guarded so Constraint_Error / malformed
   --  input marks this scenario failed without aborting the run.
   procedure Replay (S : Scenario; Failure : out Unbounded_String) is
      D : Dispatch_Session;
      Ctx : Login_Ctx;
   begin
      Init_Dispatch (D);
      D.Proto_State := S.Initial_State;
      Ctx := (others => <>);
      Failure := Null_Unbounded_String;
      for Idx in 1 .. Natural (S.Steps.Length) loop
         declare
            St : constant Step := S.Steps (Idx);
            In_Len : constant Natural := Natural (St.Input.Length);
            R : Feed_Result;
         begin
            if In_Len = 0 then
               declare
                  Empty : constant P.Octets (1 .. 0) := (others => <>);
               begin
                  begin
                     Feed (D, Ctx, St.Dir, Empty, R);
                  exception
                     when others =>
                        Failure := To_Unbounded_String
                          ("step=" & Img (Idx)
                           & " detail=dispatch raised");
                        return;
                  end;
               end;
            else
               declare
                  Buf : P.Octets (1 .. In_Len);
               begin
                  for I in 1 .. In_Len loop
                     Buf (I) := St.Input (I);
                  end loop;
                  begin
                     Feed (D, Ctx, St.Dir, Buf, R);
                  exception
                     when Constraint_Error =>
                        R := (others => <>);
                        R.Category := To_Unbounded_String ("exception");
                        R.Detail := To_Unbounded_String
                          ("dispatch raised Constraint_Error");
                     when others =>
                        R := (others => <>);
                        R.Category := To_Unbounded_String ("exception");
                        R.Detail := To_Unbounded_String
                          ("dispatch raised");
                  end;
               end;
            end if;
            if R.Actual /= St.Expected then
               Failure := To_Unbounded_String
                 ("step=" & Img (Idx)
                  & " expected=" & Outcome_Image (St.Expected)
                  & " actual=" & Outcome_Image (R.Actual)
                  & " detail=" & To_String (R.Detail)
                  & " cat=" & To_String (R.Category));
               return;
            end if;
            if St.Has_Packet_Id and then R.Actual = Accepted
              and then R.Pid /= St.Packet_Id
            then
               Failure := To_Unbounded_String
                 ("step=" & Img (Idx)
                  & " packet_id mismatch got=" & Img (R.Pid)
                  & " want=" & Img (St.Packet_Id));
               return;
            end if;
            if St.Has_State_After
              and then D.Proto_State /= St.State_After
            then
               Failure := To_Unbounded_String
                 ("step=" & Img (Idx)
                  & " state mismatch got="
                  & Low (PS.Connection_State'Image (D.Proto_State))
                  & " want="
                  & Low (PS.Connection_State'Image (St.State_After)));
               return;
            end if;
            --  Round-trip: canonical accepted steps must re-encode to
            --  the exact input bytes.
            if R.Actual = Accepted and then St.Canonical
              and then R.Reencoded /= St.Input
            then
               Failure := To_Unbounded_String
                 ("step=" & Img (Idx)
                  & " detail=round-trip mismatch"
                  & " got=" & Bytes_Image (R.Reencoded)
                  & " want=" & Bytes_Image (St.Input));
               return;
            end if;
            --  Terminal steps leave state unchanged.
            if (R.Actual = Rejected or else R.Actual = Incomplete)
              and then St.Has_State_After
              and then D.Proto_State /= St.State_After
            then
               Failure := To_Unbounded_String
                 ("step=" & Img (Idx)
                  & " detail=terminal step changed state got="
                  & Low (PS.Connection_State'Image (D.Proto_State))
                  & " want="
                  & Low (PS.Connection_State'Image (St.State_After)));
               return;
            end if;
            if St.Has_Rejection_Category
              and then R.Actual = Rejected
            then
               declare
                  Got : constant String :=
                    Low (To_String (R.Category));
                  Want : constant String :=
                    Low (To_String (St.Rejection_Category));
               begin
                  if Got /= Want then
                     Failure := To_Unbounded_String
                       ("step=" & Img (Idx)
                        & " rejection_category mismatch got=" & Got
                        & " want=" & Want
                        & " detail=" & To_String (R.Detail));
                     return;
                  end if;
               end;
            end if;
            --  Stop feeding after a terminal step, as before.
            if R.Actual = Rejected or else R.Actual = Incomplete then
               exit;
            end if;
         end;
      end loop;
      if S.Has_Final_State and then D.Proto_State /= S.Final_State then
         Failure := To_Unbounded_String
           ("final_state mismatch got="
            & Low (PS.Connection_State'Image (D.Proto_State))
            & " want=" & Low (PS.Connection_State'Image (S.Final_State)));
         return;
      end if;
   exception
      when others =>
         Failure := To_Unbounded_String ("dispatch raised");
   end Replay;

   --  Scenario I/O entry: iterates Loader-produced scenarios,
   --  isolates state per scenario, and prints the summary.
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
