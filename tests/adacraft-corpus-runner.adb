with Ada.Characters.Handling;
with Ada.Streams;
with Ada.Strings.Fixed;
with Ada.Text_IO;
with Interfaces;
with Adacraft.Auth;
with Adacraft.Kernel;
with Adacraft.Protocol.Buffer;
with Adacraft.Protocol.Frame;
with Adacraft.Protocol.Ids;
with Adacraft.Protocol.Login;
with Adacraft.Protocol.Packets;
with Adacraft.Network;

package body Adacraft.Corpus.Runner is

   package P renames Adacraft.Protocol;
   package PS renames Adacraft.Protocol.State;
   package Prot_Login renames Adacraft.Protocol.Login;
   use Ada.Strings.Unbounded;
   use type P.Status_Kind;
   use type PS.Result_Kind;
   use type PS.Connection_State;
   use type PS.Login_Dispatch;
   use type Prot_Login.Ack_Outcome;
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

      --  LOGIN and later states dispatch through the real server
      --  handler using the runner's own Conn. Handshake and Status
      --  dispatch below stay as they are.
      if Dir = Serverbound
        and then (State = PS.Login or else State = PS.Login_Awaiting_Ack
                  or else State = PS.Configuration or else State = PS.Play)
      then
         declare
            Runner_Conn : aliased Adacraft.Network.Conn;
            Id_W : P.Buffer.Writer (Capacity => 8);
            FB_Len : Natural := 0;
            Before : constant PS.Connection_State := State;
         begin
            Runner_Conn.Proto_State := State;
            Runner_Conn.In_Use := True;
            P.Buffer.Put_Varint
              (Id_W, Interfaces.Unsigned_32 (F.Packet_Id));
            if not Id_W.Failed then
               FB_Len := Id_W.Len
                 + (if F.Payload_Last >= F.Payload_First
                    then F.Payload_Last - F.Payload_First + 1 else 0);
               declare
                  FB : P.Frame.Byte_Array (1 .. Natural'Max (FB_Len, 1));
                  K  : Natural := 0;
                  Send_Before : constant Natural := Runner_Conn.Send_Len;
               begin
                  for I in 1 .. Id_W.Len loop
                     K := K + 1;
                     FB (K) := Id_W.Data (I);
                  end loop;
                  if F.Payload_Last >= F.Payload_First then
                     for I in F.Payload_First .. F.Payload_Last loop
                        K := K + 1;
                        FB (K) := Input (I);
                     end loop;
                  end if;
                  if FB_Len > 0 then
                     Adacraft.Network.Handle_Frame_Body
                       (Runner_Conn'Access, FB (1 .. FB_Len));
                  end if;
                  State := Runner_Conn.Proto_State;
                  if Runner_Conn.Send_Len > Send_Before then
                     Ctx.Pending_Output.Clear;
                     for I in Send_Before + 1 .. Runner_Conn.Send_Len loop
                        Ctx.Pending_Output.Append
                          (P.Octet (Runner_Conn.Send_Buf
                             (Ada.Streams.Stream_Element_Offset (I))));
                     end loop;
                     Ctx.Has_Pending := True;
                  end if;
                  if Runner_Conn.Closing then
                     Ctx.Closed := True;
                     if State = Before then
                        R.Category := To_Unbounded_String ("disconnect");
                        R.Detail := To_Unbounded_String
                          ("login rejected with disconnect");
                        return;
                     end if;
                  end if;
                  if State /= Before or else not Runner_Conn.Closing then
                     R.Actual := Accepted;
                     R.Pid := F.Packet_Id;
                     R.Category := To_Unbounded_String ("login");
                     R.Detail := To_Unbounded_String ("login via server");
                     return;
                  end if;
                  Ctx.Closed := True;
                  Ctx.Has_Pending := False;
                  R.Category := To_Unbounded_String ("login");
                  R.Detail := To_Unbounded_String ("login rejected");
                  return;
               end;
            end;
         exception
            when others =>
               Ctx.Closed := True;
               Ctx.Has_Pending := False;
               R.Category := To_Unbounded_String ("login");
               R.Detail := To_Unbounded_String ("login handler raised");
               return;
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

         --  #254: Reencoded is filled only via real encoders below
         --  (Put_Varint / Put_String / Put_U16 / Put_U64 then
         --  Packets.Frame); no Put_Bytes, no raw Payload/Input copy.
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
            elsif Payload'Length = 0 then
               --  Status Request: id only, already written above.
               null;
            else
               --  Ping: packet id then the decoded long with the
               --  real 64-bit writer.
               declare
                  Ping_Res : constant P.Packets.Ping :=
                    P.Packets.Decode_Ping (Payload);
               begin
                  if Ping_Res.Status = P.Ok then
                     P.Buffer.Put_U64 (Body_W, Ping_Res.Value);
                  end if;
               end;
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
      Idx   : Natural := 0;

      procedure Fail (Expected, Actual, Detail : String) is
      begin
         Failure := To_Unbounded_String
           ("step=" & Img (Idx) & " expected=" & Expected
            & " actual=" & Actual & " detail=" & Detail);
      end Fail;
   begin
      Failure := Null_Unbounded_String;
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
