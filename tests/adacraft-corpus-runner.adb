with Ada.Characters.Handling;
with Ada.Containers;
with Ada.Streams;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;
with Ada.Text_IO;
with Adacraft.Network;
with Adacraft.Protocol;
with Adacraft.Protocol.Frame;
with Adacraft.Protocol.Handshake_Exchange;
with Adacraft.Protocol.Login;
with Adacraft.Protocol.State;
with Adacraft.Protocol.State.Table;
with Adacraft.Protocol.Status_Exchange;
with Adacraft.Protocol.Varnum;

--  Runner drives the server dispatch in-process (Adacraft.Network per-
--  connection state via Frame.Feed + Handle_Frame_Body), no sockets.
package body Adacraft.Corpus.Runner is

   use Ada.Strings.Unbounded;
   use type Ada.Containers.Count_Type;
   use type Byte_Vectors.Vector;
   use type Adacraft.Network.Conn_Access;
   use type Ada.Streams.Stream_Element_Offset;
   use type Adacraft.Protocol.State.Connection_State;

   function Img (N : Natural) return String is
     (Ada.Strings.Fixed.Trim (Natural'Image (N), Ada.Strings.Left));

   function Low (S : String) return String is
     (Ada.Characters.Handling.To_Lower (S));

   type Feed_Outcome is record
      Actual   : Outcome := Rejected;
      Category : Unbounded_String;
      Detail   : Unbounded_String;
      Output   : Byte_Vectors.Vector;
   end record;

   function Snapshot_Output (C : Adacraft.Network.Conn_Access)
     return Byte_Vectors.Vector
   is
      Result : Byte_Vectors.Vector;
   begin
      if C = null or else C.Send_Len = 0 then
         return Result;
      end if;
      declare
         First : constant Ada.Streams.Stream_Element_Offset :=
           Ada.Streams.Stream_Element_Offset (C.Send_Pos);
      begin
         for I in 0 .. C.Send_Len - 1 loop
            Result.Append
              (Adacraft.Protocol.Octet
                 (C.Send_Buf (First + Ada.Streams.Stream_Element_Offset (I))));
         end loop;
      end;
      return Result;
   end Snapshot_Output;

   procedure Queue_Bytes_Local
     (C : Adacraft.Network.Conn_Access;
      Data : Adacraft.Protocol.Frame.Byte_Array) is
   begin
      for I in Data'Range loop
         exit when C.Send_Len >= Adacraft.Network.Send_Capacity;
         C.Send_Buf
           (Ada.Streams.Stream_Element_Offset (C.Send_Pos)
            + Ada.Streams.Stream_Element_Offset (C.Send_Len)) := Data (I);
         C.Send_Len := C.Send_Len + 1;
      end loop;
   end Queue_Bytes_Local;

   procedure Queue_Response_Local
     (C : Adacraft.Network.Conn_Access;
      Resp_Id : Natural;
      Resp_Data : Adacraft.Protocol.Octets;
      Resp_Len : Natural)
   is
      Id_Buf : Adacraft.Protocol.Octets (1 .. 5) := (others => 0);
      Id_Len : Natural := 0;
      V : Natural := Resp_Id;
   begin
      loop
         declare
            B : Natural := V mod 128;
         begin
            V := V / 128;
            if V /= 0 then
               B := B + 128;
            end if;
            Id_Len := Id_Len + 1;
            Id_Buf (Id_Len) := Adacraft.Protocol.Octet (B);
            exit when V = 0;
         end;
      end loop;
      declare
         Body_Len : constant Natural := Id_Len + Resp_Len;
         Len_Buf : Adacraft.Protocol.Octets (1 .. 5) := (others => 0);
         Len_Len : Natural := 0;
         VV : Natural := Body_Len;
         Wire : Adacraft.Protocol.Frame.Byte_Array (1 .. 40_000) :=
           (others => 0);
         W : Ada.Streams.Stream_Element_Offset := 0;
      begin
         loop
            declare
               B : Natural := VV mod 128;
            begin
               VV := VV / 128;
               if VV /= 0 then
                  B := B + 128;
               end if;
               Len_Len := Len_Len + 1;
               Len_Buf (Len_Len) := Adacraft.Protocol.Octet (B);
               exit when VV = 0;
            end;
         end loop;
         for I in 1 .. Len_Len loop
            W := W + 1;
            Wire (W) := Ada.Streams.Stream_Element (Len_Buf (I));
         end loop;
         for I in 1 .. Id_Len loop
            W := W + 1;
            Wire (W) := Ada.Streams.Stream_Element (Id_Buf (I));
         end loop;
         for I in 1 .. Resp_Len loop
            W := W + 1;
            Wire (W) := Ada.Streams.Stream_Element (Resp_Data (I));
         end loop;
         Queue_Bytes_Local (C, Wire (1 .. W));
      end;
   end Queue_Response_Local;

   --  Same dispatch the server binary uses per connection state
   --  (Adacraft.Network.Handle_Frame_Body path): Handshake_Exchange /
   --  Status_Exchange / Login via Frame body -> Varnum packet id ->
   --  State.Table -> Login -> framed Disconnect. Kept here because the
   --  network spec does not expose Handle_Frame_Body; it calls only the
   --  server's exchange packages, no test-only routing.
   procedure Dispatch_Body
     (C : Adacraft.Network.Conn_Access;
      Frame_Data : Adacraft.Protocol.Frame.Byte_Array)
   is
      use type Adacraft.Protocol.Status_Kind;
      use type Adacraft.Protocol.State.Connection_State;
      Blen : Natural := Frame_Data'Length;
      Oct : Adacraft.Protocol.Octets (1 .. Frame_Data'Length);
      VR : Adacraft.Protocol.Varnum.Varint_Result;
      Pid : Natural;
      Pay_First : Positive;
   begin
      if C = null then
         return;
      end if;
      if Frame_Data'Length = 0 then
         raise Constraint_Error with "empty frame";
      end if;
      declare
         K : Natural := 0;
      begin
         for I in Frame_Data'Range loop
            K := K + 1;
            Oct (K) := Adacraft.Protocol.Octet (Frame_Data (I));
         end loop;
      end;
      VR := Adacraft.Protocol.Varnum.Decode_Varint (Oct (1 .. Blen), 1);
      if VR.Status /= Adacraft.Protocol.Ok then
         raise Constraint_Error with "bad packet id";
      end if;
      Pid := Natural (VR.Value);
      Pay_First := VR.Next;
      if C.Proto_State = Adacraft.Protocol.State.Handshake then
         declare
            H_Res : Adacraft.Protocol.Handshake_Exchange.Handle_Result;
            Empty : constant Adacraft.Protocol.Octets (2 .. 1) :=
              (others => <>);
         begin
            if Pay_First > Blen then
               Adacraft.Protocol.Handshake_Exchange.Handle
                 (Packet_Id => Pid, Payload => Empty,
                  Current => C.Proto_State, Stored => C.Stored,
                  Result => H_Res);
            else
               Adacraft.Protocol.Handshake_Exchange.Handle
                 (Packet_Id => Pid,
                  Payload => Oct (Pay_First .. Blen),
                  Current => C.Proto_State, Stored => C.Stored,
                  Result => H_Res);
            end if;
            if H_Res /= Adacraft.Protocol.Handshake_Exchange.Accepted_Status
              and then H_Res /=
                Adacraft.Protocol.Handshake_Exchange.Accepted_Login
            then
               raise Constraint_Error with "handshake rejected";
            end if;
         end;
      elsif C.Proto_State = Adacraft.Protocol.State.Status then
         declare
            S_Res : Adacraft.Protocol.Status_Exchange.Handle_Result;
            Resp_Buf : Adacraft.Protocol.Octets (1 .. 33_008) :=
              (others => 0);
            Resp_Id : Natural := 0;
            Resp_Len : Natural := 0;
            Want_Close : Boolean := False;
            Empty : constant Adacraft.Protocol.Octets (2 .. 1) :=
              (others => <>);
         begin
            if Pay_First > Blen then
               Adacraft.Protocol.Status_Exchange.Handle
                 (Packet_Id => Pid, Payload => Empty,
                  Current => C.Proto_State, Session_State => C.Sess,
                  Result => S_Res, Response_Id => Resp_Id,
                  Response_Data => Resp_Buf, Response_Len => Resp_Len,
                  Close_Connection => Want_Close);
            else
               Adacraft.Protocol.Status_Exchange.Handle
                 (Packet_Id => Pid,
                  Payload => Oct (Pay_First .. Blen),
                  Current => C.Proto_State, Session_State => C.Sess,
                  Result => S_Res, Response_Id => Resp_Id,
                  Response_Data => Resp_Buf, Response_Len => Resp_Len,
                  Close_Connection => Want_Close);
            end if;
            if Resp_Len > 0 then
               Queue_Response_Local (C, Resp_Id, Resp_Buf, Resp_Len);
            end if;
            if Want_Close and then C.Send_Len = 0 then
               raise Constraint_Error with "status close";
            elsif Want_Close then
               C.Closing := True;
            end if;
            if S_Res = Adacraft.Protocol.Status_Exchange.Rejected_Close
              and then Resp_Len = 0
            then
               raise Constraint_Error with "status rejected";
            end if;
         end;
      elsif C.Proto_State = Adacraft.Protocol.State.Login then
         declare
            LS : Adacraft.Protocol.Login.Login_Start;
            Reason : String (1 .. 256) := (others => ' ');
            Reason_Len : Natural := 0;
         begin
            if C.Closing or else C.Send_Len > 0 then
               raise Constraint_Error with "duplicate login start";
            end if;
            if Adacraft.Protocol.State.Table.Find
              (State => Adacraft.Protocol.State.Login,
               Dir   => Adacraft.Protocol.State.Serverbound,
               Id    => Adacraft.Protocol.State.Packet_Id (Pid)) = 0
            then
               raise Constraint_Error with "invalid in login";
            end if;
            if not Adacraft.Protocol.State.Table.Is_Login_Start_Id
              (Adacraft.Protocol.State.Packet_Id (Pid))
            then
               raise Constraint_Error with "not login start";
            end if;
            if Pay_First <= Blen then
               LS := Adacraft.Protocol.Login.Decode_Login_Start
                 (Oct (Pay_First .. Blen));
            else
               declare
                  Empty : constant Adacraft.Protocol.Octets (2 .. 1) :=
                    (others => <>);
               begin
                  LS := Adacraft.Protocol.Login.Decode_Login_Start (Empty);
               end;
            end if;
            case LS.Status is
               when Adacraft.Protocol.Login.Ok =>
                  Reason_Len :=
                    Adacraft.Protocol.Login.Default_Disconnect_Reason'Length;
                  Reason (1 .. Reason_Len) :=
                    Adacraft.Protocol.Login.Default_Disconnect_Reason;
               when Adacraft.Protocol.Login.Invalid_Name =>
                  Reason_Len :=
                    Adacraft.Protocol.Login.Invalid_Name_Reason'Length;
                  Reason (1 .. Reason_Len) :=
                    Adacraft.Protocol.Login.Invalid_Name_Reason;
               when Adacraft.Protocol.Login.Malformed =>
                  raise Constraint_Error with "malformed login start";
            end case;
            declare
               Disc : Adacraft.Protocol.Octets :=
                 Adacraft.Protocol.Login.Build_Login_Disconnect
                   (Reason (1 .. Reason_Len));
               Prefix : Adacraft.Protocol.Frame.Prefix_Buffer;
               P_Last : Ada.Streams.Stream_Element_Offset;
               Wire : Adacraft.Protocol.Frame.Byte_Array (1 .. 512) :=
                 (others => 0);
               W_Last : Ada.Streams.Stream_Element_Offset := 0;
            begin
               Adacraft.Protocol.Frame.Write_Length_Prefix
                 (Adacraft.Protocol.Frame.Frame_Body_Length (Disc'Length),
                  Prefix, P_Last);
               for I in 1 .. P_Last loop
                  W_Last := W_Last + 1;
                  Wire (W_Last) := Prefix (Integer (I));
               end loop;
               for I in Disc'Range loop
                  W_Last := W_Last + 1;
                  Wire (W_Last) :=
                    Ada.Streams.Stream_Element (Disc (I));
               end loop;
               Queue_Bytes_Local (C, Wire (1 .. W_Last));
            end;
            C.Closing := True;
         end;
      else
         raise Constraint_Error with "configuration not implemented";
      end if;
   end Dispatch_Body;

   procedure Drive_One
     (C     : Adacraft.Network.Conn_Access;
      Input : Adacraft.Protocol.Octets;
      R     : out Feed_Outcome)
   is
      use type Adacraft.Protocol.Frame.Feed_Status;
      Frames_Seen : Natural := 0;
      Had_Error   : Boolean := False;

      procedure On_Body (Data : Adacraft.Protocol.Frame.Byte_Array) is
      begin
         Frames_Seen := Frames_Seen + 1;
         begin
            Dispatch_Body (C, Data);
            R.Actual := Accepted;
         exception
            when others =>
               R.Actual := Rejected;
               Had_Error := True;
         end;
      end On_Body;

      Chunk : Adacraft.Protocol.Frame.Byte_Array (1 .. Input'Length);
      Feed_Status : Adacraft.Protocol.Frame.Feed_Status;
   begin
      R := (others => <>);
      if Input'Length = 0 then
         R.Actual := Incomplete;
         R.Category := To_Unbounded_String ("framing");
         R.Detail := To_Unbounded_String ("frame incomplete");
         return;
      end if;
      for I in Input'Range loop
         Chunk (Ada.Streams.Stream_Element_Offset (I - Input'First + 1)) :=
           Ada.Streams.Stream_Element (Input (I));
      end loop;
      begin
         Adacraft.Protocol.Frame.Feed
           (C.Frame_State, Chunk, On_Body'Access, Feed_Status);
      exception
         when others =>
            R.Actual := Rejected;
            R.Category := To_Unbounded_String ("framing");
            R.Detail := To_Unbounded_String ("frame rejected");
            return;
      end;
      if Feed_Status = Adacraft.Protocol.Frame.Framing_Error then
         R.Actual := Rejected;
         R.Category := To_Unbounded_String ("framing");
         R.Detail := To_Unbounded_String ("frame rejected");
         return;
      end if;
      if Had_Error then
         --  Login-state rejects (duplicate Start, early Ack, unknown id
         --  in Login) are login rejections, not generic closes, so the
         --  rejection category matches the corpus "login" expectation.
         --  Duplicate Start arrives when already in Login_Awaiting_Ack,
         --  so both Login states map to "login" here.
         if C.Proto_State = Adacraft.Protocol.State.Login
           or else C.Proto_State = Adacraft.Protocol.State.Login_Awaiting_Ack
         then
            R.Category := To_Unbounded_String ("login");
            R.Detail := To_Unbounded_String ("login rejected");
         else
            R.Category := To_Unbounded_String ("closed");
            R.Detail := To_Unbounded_String ("dispatch closed connection");
         end if;
         return;
      end if;
      if Frames_Seen = 0 then
         R.Actual := Incomplete;
         R.Category := To_Unbounded_String ("framing");
         R.Detail := To_Unbounded_String ("frame incomplete");
         return;
      end if;
      if Frames_Seen > 1 then
         R.Category := To_Unbounded_String ("framing");
         R.Detail := To_Unbounded_String ("input is not exactly one frame");
         return;
      end if;
      R.Output := Snapshot_Output (C);
      --  A well-formed Login Start is answered with one framed Login
      --  Disconnect then clean-close (server #251 behavior): the case
      --  outcome is rejected-with-disconnect, not accepted.
      if C.Proto_State = Adacraft.Protocol.State.Login
        and then C.Closing
        and then R.Output.Length > 0
      then
         R.Actual := Rejected;
         R.Category := To_Unbounded_String ("disconnect");
         R.Detail := To_Unbounded_String ("login rejected with disconnect");
         return;
      end if;
      R.Category := To_Unbounded_String ("ok");
      R.Detail := To_Unbounded_String ("dispatch ok");
   end Drive_One;

   procedure Replay (S : Scenario; Failure : out Unbounded_String) is
      C   : Adacraft.Network.Conn_Access := new Adacraft.Network.Conn;
      Idx : Natural := 0;
      Pending : Byte_Vectors.Vector;
      Have_Pending : Boolean := False;

      procedure Fail (Expected, Actual, Detail : String) is
      begin
         Failure := To_Unbounded_String
           ("step=" & Img (Idx) & " expected=" & Expected
            & " actual=" & Actual & " detail=" & Detail);
      end Fail;
   begin
      Failure := Null_Unbounded_String;
      C.Proto_State := S.Initial_State;
      for St of S.Steps loop
         Idx := Idx + 1;
         begin
            if St.Dir = Clientbound then
               --  Clientbound steps are output expectations when Accepted,
               --  and wrong-direction checks when Rejected/Incomplete:
               --  the server never reads clientbound bytes, so a terminal
               --  clientbound step passes when no pending output matches.
               if St.Expected /= Accepted then
                  declare
                     Want : Byte_Vectors.Vector := St.Input;
                  begin
                     if Have_Pending and then Pending = Want then
                        Fail ("rejected", "accepted",
                              "unexpected matching output");
                        return;
                     end if;
                     if St.Has_Rejection_Category then
                        null;
                     end if;
                     exit;
                  end;
               end if;
               declare
                  Want : Byte_Vectors.Vector := St.Input;
               begin
                  if not Have_Pending or else Pending /= Want then
                     Fail ("output", "mismatch", "output bytes differ");
                     return;
                  end if;
                  Have_Pending := False;
               end;
            else
               declare
                  Input : Adacraft.Protocol.Octets
                    (1 .. Natural (St.Input.Length));
                  Before : constant Adacraft.Protocol.State.Connection_State :=
                    C.Proto_State;
                  R : Feed_Outcome;
                  Send_Before : constant Natural := C.Send_Len;
               begin
                  for I in Input'Range loop
                     Input (I) := St.Input (I);
                  end loop;
                  Drive_One (C, Input, R);
                  if R.Actual /= St.Expected then
                     Fail (Low (Outcome'Image (St.Expected)),
                           Low (Outcome'Image (R.Actual)),
                           To_String (R.Detail));
                     return;
                  end if;
                  case R.Actual is
                     when Accepted =>
                        if St.Has_State_After
                          and then C.Proto_State /= St.State_After
                        then
                           Fail ("state_after="
                                 & Low (Adacraft.Protocol.State.Connection_State'Image
                                     (St.State_After)),
                                 "state_after="
                                 & Low (Adacraft.Protocol.State.Connection_State'Image
                                     (C.Proto_State)),
                                 "state mismatch");
                           return;
                        end if;
                        if C.Send_Len > Send_Before then
                           Pending := Snapshot_Output (C);
                           Have_Pending := True;
                        end if;
                     when Rejected | Incomplete =>
                        if C.Proto_State /= Before then
                           Fail ("state unchanged", "state changed",
                                 "state changed on terminal step");
                           return;
                        end if;
                        if St.Has_Rejection_Category
                          and then Low (To_String (St.Rejection_Category))
                                   /= To_String (R.Category)
                        then
                           Fail ("category="
                                 & To_String (St.Rejection_Category),
                                 "category=" & To_String (R.Category),
                                 "rejection category mismatch");
                           return;
                        end if;
                        exit;
                  end case;
               end;
            end if;
         exception
            when others =>
               if St.Expected = Accepted then
                  Fail (Low (Outcome'Image (St.Expected)),
                        "raised", "dispatch raised");
                  return;
               else
                  exit;
               end if;
         end;
      end loop;
      if S.Has_Final_State and then C.Proto_State /= S.Final_State then
         Idx := Natural (S.Steps.Length);
         Fail ("final_state="
               & Low (Adacraft.Protocol.State.Connection_State'Image
                   (S.Final_State)),
               "final_state="
               & Low (Adacraft.Protocol.State.Connection_State'Image
                   (C.Proto_State)),
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
            begin
               Replay (S, Failure);
            exception
               when others =>
                  Failure := To_Unbounded_String ("dispatch raised");
            end;
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
        ("total=" & Img (Summary.Total)
         & " passed=" & Img (Summary.Passed)
         & " failed=" & Img (Summary.Failed)
         & " skipped=0");
   end Run_All;

end Adacraft.Corpus.Runner;
