with Ada.Characters.Handling;
with Ada.Strings.Fixed;
with Ada.Text_IO;
with Interfaces;
with Adacraft.Auth;
with Adacraft.Kernel;
with Adacraft.Protocol.Buffer;
with Adacraft.Protocol.Frame;
with Adacraft.Protocol.Ids;
with Adacraft.Protocol.Handshake_Exchange;
with Adacraft.Protocol.Login;
with Adacraft.Protocol.Packets;
with Adacraft.Protocol.State;
with Adacraft.Protocol.Status_Exchange;

package body Adacraft.Corpus.Runner is

   --  Single-state / single-status dispatch: handshake and status steps
   --  reach the server only through Handshake_Exchange.Handle and
   --  Status_Exchange.Handle (single status JSON builder); no local
   --  status builder and no duplicate state type or conversion here.
   --  Version fields come from the single version package
   --  Adacraft.Protocol.State (Protocol_Number / Minecraft_Version).
   package P renames Adacraft.Protocol;
   package PS renames Adacraft.Protocol.State;
   package HE renames Adacraft.Protocol.Handshake_Exchange;
   package SE renames Adacraft.Protocol.Status_Exchange;
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

   Login_Start_Pid      : constant := 0;
   Login_Ack_Pid        : constant := 3;
   Login_Success_Pid    : constant := 2;
   Login_Disconnect_Pid : constant := 0;

   --  Single-dispatch server state: handshake stored data and status
   --  session live across Feed calls within one scenario; reset in
   --  Replay. Feed reaches handshake/status only through
   --  Handshake_Exchange.Handle / Status_Exchange.Handle (single
   --  status JSON builder in the server binary).
   HS_Stored : HE.Connection_Data;
   SE_Sess   : SE.Session;

   function Frame_Packet
     (WB : P.Buffer.Writer) return Byte_Vectors.Vector
   is
      Framed : P.Buffer.Writer (Capacity => WB.Len + 32 + 1);
      Result : Byte_Vectors.Vector;
   begin
      --  WB already holds the full packet body including its id,
      --  so frame it directly without prepending another id.
      if P.Packets.Frame (Framed, WB) and then not Framed.Failed then
         for I in 1 .. Framed.Len loop
            Result.Append (Framed.Data (I));
         end loop;
      end if;
      return Result;
   end Frame_Packet;

   type Feed_Result is record
      Actual    : Outcome := Rejected;
      Pid       : Natural := 0;
      Category  : Unbounded_String;
      Detail    : Unbounded_String;
      Reencoded : Byte_Vectors.Vector;
   end record;

   procedure Feed
     (State : in out PS.Connection_State;
      Ctx   : in out Login_Ctx;
      Dir   : Direction;
      Input : P.Octets;
      R     : out Feed_Result)
   is
      F : constant P.Frame.Frame_Decode := P.Frame.Decode_Frame (Input, 1);
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
                  Res : constant Prot_Login.Start_Result :=
                    Prot_Login.Handle_Start
                      (Ctx.Session, Payload,
                       (if Adacraft.Kernel.Online_Mode
                        then Auth.Online else Auth.Offline));
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

      --  Handshake steps go through the server handshake dispatch.
      if State = PS.Handshake and then Dir = Serverbound then
         declare
            Payload : constant P.Octets :=
              Input (F.Payload_First .. F.Payload_Last);
            H_Res : HE.Handle_Result;
         begin
            HE.Handle
              (Packet_Id => F.Packet_Id,
               Payload   => Payload,
               Current   => State,
               Stored    => HS_Stored,
               Result    => H_Res);
            if H_Res = HE.Accepted_Status
              or else H_Res = HE.Accepted_Login
            then
               State := State;
               R.Actual := Accepted;
               R.Pid := F.Packet_Id;
               R.Category := To_Unbounded_String ("handshake");
               R.Detail := To_Unbounded_String ("handshake ok");
               return;
            else
               R.Category := To_Unbounded_String ("handshake");
               R.Detail := To_Unbounded_String ("handshake rejected");
               return;
            end if;
         end;
      end if;

      --  Status steps go through the single server status dispatch
      --  (single JSON builder; version fields from
      --  Adacraft.Protocol.State.Protocol_Number / Minecraft_Version).
      if State = PS.Status then
         if Dir /= Serverbound then
            R.Category := To_Unbounded_String ("status");
            R.Detail := To_Unbounded_String ("status wrong direction");
            return;
         end if;
         declare
            Payload : constant P.Octets :=
              Input (F.Payload_First .. F.Payload_Last);
            S_Res : SE.Handle_Result;
            Resp_Id : Natural := 0;
            Resp_Len : Natural := 0;
            Resp_Buf : P.Octets (1 .. 33_008) := (others => 0);
            Want_Close : Boolean := False;
         begin
            SE.Handle
              (Packet_Id        => F.Packet_Id,
               Payload          => Payload,
               Current          => State,
               Session_State    => SE_Sess,
               Result           => S_Res,
               Response_Id      => Resp_Id,
               Response_Data    => Resp_Buf,
               Response_Len     => Resp_Len,
               Close_Connection => Want_Close);
            if S_Res = SE.Responded
              or else S_Res = SE.Pong_Ready_Close
            then
               R.Actual := Accepted;
               R.Pid := F.Packet_Id;
               R.Category := To_Unbounded_String ("status");
               R.Detail := To_Unbounded_String ("status ok");
               if Want_Close then
                  Ctx.Closed := True;
               end if;
               return;
            else
               Ctx.Closed := True;
               R.Category := To_Unbounded_String ("status");
               R.Detail := To_Unbounded_String ("status rejected");
               return;
            end if;
         end;
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

   procedure Replay (S : Scenario; Failure : out Unbounded_String) is
      State : PS.Connection_State := S.Initial_State;
      Ctx   : Login_Ctx;
      --  Per-scenario server dispatch state uses the single
      --  Adacraft.Protocol.State.Connection_State type directly;
      --  no duplicate state type and no To_State/From_State/Convert.
      Idx   : Natural := 0;

      procedure Fail (Expected, Actual, Detail : String) is
      begin
         Failure := To_Unbounded_String
           ("step=" & Img (Idx) & " expected=" & Expected
            & " actual=" & Actual & " detail=" & Detail);
      end Fail;
   begin
      Failure := Null_Unbounded_String;
      HS_Stored := (others => <>);
      SE.Reset (SE_Sess);
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
            Feed (State, Ctx, St.Dir, Input, R);
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
      Saved_Online_Mode : constant Boolean := Adacraft.Kernel.Online_Mode;
   begin
      --  Corpus login scenarios exercise the offline flow explicitly.
      --  The runner's LOGIN dispatch still reads the configured mode.
      Adacraft.Kernel.Online_Mode := False;
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
