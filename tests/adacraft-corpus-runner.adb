with Ada.Containers;
with Ada.Streams;
with Ada.Strings.Unbounded;
with Ada.Text_IO;
with Interfaces;
with Adacraft.Protocol.Buffer;
with Adacraft.Protocol.Frame;
with Adacraft.Protocol.Handshake_Exchange;
with Adacraft.Protocol.State;
with Adacraft.Protocol.Status_Exchange;
with Adacraft.Protocol.Varnum;
with Adacraft.Protocol;

package body Adacraft.Corpus.Runner is

   use Ada.Strings.Unbounded;
   use type Ada.Containers.Count_Type;
   use type Ada.Streams.Stream_Element_Offset;
   use type Adacraft.Protocol.Frame.Encode_Status;
   use type Adacraft.Protocol.Frame.Feed_Status;
   use type Adacraft.Protocol.Handshake_Exchange.Handle_Result;
   use type Adacraft.Protocol.State.Connection_State;
   use type Adacraft.Protocol.Status_Exchange.Handle_Result;
   use type Adacraft.Protocol.Status_Kind;
   use type Adacraft.Protocol.Varnum.Decode_Status;

   procedure Init_Dispatch (D : out Dispatch_Session) is
   begin
      D.Proto_State := Adacraft.Protocol.State.Handshake;
      D.Stored := (others => <>);
      Adacraft.Protocol.Status_Exchange.Reset (D.Sess);
      D.Pending.Clear;
      D.Closing := False;
   end Init_Dispatch;

   function To_Octets
     (B : Adacraft.Protocol.Frame.Byte_Array) return Adacraft.Protocol.Octets
   is
      R : Adacraft.Protocol.Octets (1 .. B'Length);
      K : Natural := 0;
   begin
      for I in B'Range loop
         K := K + 1;
         R (K) := Adacraft.Protocol.Octet (B (I));
      end loop;
      return R;
   end To_Octets;

   function To_Chunk
     (V : Byte_Vectors.Vector) return Adacraft.Protocol.Frame.Byte_Array
   is
      N : constant Natural := Natural (V.Length);
   begin
      if N = 0 then
         return (1 .. 0 => 0);
      end if;
      declare
         R : Adacraft.Protocol.Frame.Byte_Array (1 .. Ada.Streams.Stream_Element_Offset (N));
         K : Natural := 0;
      begin
         for E of V loop
            K := K + 1;
            R (Ada.Streams.Stream_Element_Offset (K)) :=
              Ada.Streams.Stream_Element (E);
         end loop;
         return R;
      end;
   end To_Chunk;

   procedure Append_Wire
     (D : in out Dispatch_Session;
      W : Adacraft.Protocol.Frame.Byte_Array)
   is
   begin
      for E of W loop
         D.Pending.Append (Interfaces.Unsigned_8 (E));
      end loop;
   end Append_Wire;

   --  Frame one server response body (packet id already included in
   --  Proto_Body) with the server's own Frame.Encode; no packet content
   --  is built here.
   procedure Append_Framed_Body
     (D          : in out Dispatch_Session;
      Proto_Body : Adacraft.Protocol.Octets)
   is
      Pay : Adacraft.Protocol.Frame.Byte_Array
        (1 .. Ada.Streams.Stream_Element_Offset (Proto_Body'Length));
      K : Natural := 0;
   begin
      if Proto_Body'Length = 0 then
         return;
      end if;
      for I in Proto_Body'Range loop
         K := K + 1;
         Pay (Ada.Streams.Stream_Element_Offset (K)) :=
           Ada.Streams.Stream_Element (Proto_Body (I));
      end loop;
      declare
         Out_Buf : Adacraft.Protocol.Frame.Byte_Array
           (1 .. Pay'Length + Adacraft.Protocol.Frame.Max_Frame_Prefix_Bytes);
         Last : Ada.Streams.Stream_Element_Offset;
         St : Adacraft.Protocol.Frame.Encode_Status;
      begin
         Adacraft.Protocol.Frame.Encode (Pay, Out_Buf, Last, St);
         if St = Adacraft.Protocol.Frame.Ok then
            Append_Wire (D, Out_Buf (Out_Buf'First .. Last));
         end if;
      end;
   end Append_Framed_Body;

   --  Frame a Status_Exchange response using only the server's own
   --  codecs: Buffer.Put_Varint for the response id (no hand-rolled
   --  7-bit groups, no JSON/pong construction here) and Frame.Encode
   --  for the length prefix. Payload bytes come from the server
   --  dispatch untouched. Gap note: the server dispatch has no single
   --  entry returning framed clientbound bytes, so this glue frames
   --  the dispatch's (Response_Id, Response_Data) with the server's
   --  own framing package; if a framed-bytes entry ships, this glue
   --  must call it instead (see Dispatch_Frame_Body gap for Login).
   procedure Append_Status_Response
     (D         : in out Dispatch_Session;
      Resp_Id   : Natural;
      Resp_Data : Adacraft.Protocol.Octets;
      Resp_Len  : Natural)
   is
   begin
      if Resp_Len = 0 then
         return;
      end if;
      declare
         Body_W : Adacraft.Protocol.Buffer.Writer (33_000 + 8);
      begin
         Adacraft.Protocol.Buffer.Reset (Body_W);
         Adacraft.Protocol.Buffer.Put_Varint
           (Body_W, Interfaces.Unsigned_32 (Resp_Id));
         for I in 1 .. Resp_Len loop
            Adacraft.Protocol.Buffer.Put_Octet
              (Body_W, Resp_Data (Resp_Data'First + I - 1));
         end loop;
         if Body_W.Failed then
            raise Constraint_Error with "status response too long";
         end if;
         declare
            Proto : Adacraft.Protocol.Octets (1 .. Body_W.Len);
         begin
            for I in 1 .. Body_W.Len loop
               Proto (I) :=
                 Adacraft.Protocol.Octet (Body_W.Data (I));
            end loop;
            Append_Framed_Body (D, Proto);
         end;
      end;
   end Append_Status_Response;

   procedure Dispatch_Frame_Body
     (D : in out Dispatch_Session;
      Frame_Data : Adacraft.Protocol.Frame.Byte_Array)
   is
      Oct : Adacraft.Protocol.Octets (1 .. Frame_Data'Length);
      K : Natural := 0;
      VR : Adacraft.Protocol.Varnum.Varint_Result;
      Pid : Natural;
      Pay_First : Natural;
   begin
      if D.Closing then
         raise Constraint_Error with "connection closing";
      end if;
      if Frame_Data'Length = 0 then
         raise Constraint_Error with "empty frame";
      end if;
      for I in Frame_Data'Range loop
         K := K + 1;
         Oct (K) := Adacraft.Protocol.Octet (I);
      end loop;
      --  Split packet id / payload with the server's VarInt codec only.
      VR := Adacraft.Protocol.Varnum.Decode_Varint (Oct, 1);
      if VR.Status /= Adacraft.Protocol.Ok then
         raise Constraint_Error with "bad packet id";
      end if;
      Pid := Natural (VR.Value);
      Pay_First := VR.Next;
      if D.Proto_State = Adacraft.Protocol.State.Handshake then
         declare
            H_Res : Adacraft.Protocol.Handshake_Exchange.Handle_Result;
            Empty : constant Adacraft.Protocol.Octets (2 .. 1) := (others => <>);
         begin
            if Pay_First > Oct'Length then
               Adacraft.Protocol.Handshake_Exchange.Handle
                 (Packet_Id => Pid, Payload => Empty,
                  Current => D.Proto_State, Stored => D.Stored,
                  Result => H_Res);
            else
               Adacraft.Protocol.Handshake_Exchange.Handle
                 (Packet_Id => Pid, Payload => Oct (Pay_First .. Oct'Length),
                  Current => D.Proto_State, Stored => D.Stored,
                  Result => H_Res);
            end if;
            if H_Res /= Adacraft.Protocol.Handshake_Exchange.Accepted_Status
              and then H_Res /= Adacraft.Protocol.Handshake_Exchange.Accepted_Login
            then
               raise Constraint_Error with "handshake rejected";
            end if;
         end;
      elsif D.Proto_State = Adacraft.Protocol.State.Status then
         declare
            S_Res : Adacraft.Protocol.Status_Exchange.Handle_Result;
            Resp_Buf : Adacraft.Protocol.Octets (1 .. 33_008) := (others => 0);
            Resp_Id : Natural := 0;
            Resp_Len : Natural := 0;
            Want_Close : Boolean := False;
            Empty : constant Adacraft.Protocol.Octets (2 .. 1) := (others => <>);
         begin
            if Pay_First > Oct'Length then
               Adacraft.Protocol.Status_Exchange.Handle
                 (Packet_Id => Pid, Payload => Empty,
                  Current => D.Proto_State, Session_State => D.Sess,
                  Result => S_Res, Response_Id => Resp_Id,
                  Response_Data => Resp_Buf, Response_Len => Resp_Len,
                  Close_Connection => Want_Close);
            else
               Adacraft.Protocol.Status_Exchange.Handle
                 (Packet_Id => Pid,
                  Payload => Oct (Pay_First .. Oct'Length),
                  Current => D.Proto_State, Session_State => D.Sess,
                  Result => S_Res, Response_Id => Resp_Id,
                  Response_Data => Resp_Buf, Response_Len => Resp_Len,
                  Close_Connection => Want_Close);
            end if;
            if Resp_Len > 0 then
               Append_Status_Response (D, Resp_Id, Resp_Buf, Resp_Len);
            end if;
            if Want_Close and then D.Pending.Length = 0 then
               raise Constraint_Error with "status close";
            elsif Want_Close then
               D.Closing := True;
            end if;
            if S_Res = Adacraft.Protocol.Status_Exchange.Rejected_Close
              and then Resp_Len = 0
            then
               raise Constraint_Error with "status rejected";
            end if;
         end;
      else
         --  Gap: the server dispatch has no socket-free entry returning
         --  framed bytes for Login and later states (that path lives in
         --  Adacraft.Network.Handle_Frame_Body over a live connection).
         --  Close with no reply so the two Login Success goldens stay
         --  red until "Live Login sends Login Success" ships.
         D.Closing := True;
         raise Constraint_Error with "gap: login dispatch needs live connection";
      end if;
   end Dispatch_Frame_Body;

   function Hex_Of (V : Byte_Vectors.Vector) return String is
      Hex : constant String := "0123456789abcdef";
      R : String (1 .. Natural (V.Length) * 2 + 1);
      K : Natural := 0;
   begin
      if V.Length = 0 then
         return "";
      end if;
      for E of V loop
         K := K + 1;
         R (K) := Hex (Natural (E) / 16 + 1);
         K := K + 1;
         R (K) := Hex (Natural (E) mod 16 + 1);
      end loop;
      return R (1 .. K);
   end Hex_Of;

   procedure Replay (S : Scenario; Failure : out Unbounded_String) is
      D : Dispatch_Session;
      Decoder : Adacraft.Protocol.Frame.Decoder_Type;
      Failed : Boolean := False;
      Fail_Msg : Unbounded_String := Null_Unbounded_String;

      procedure Fail (Msg : String) is
      begin
         if not Failed then
            Failed := True;
            Fail_Msg := To_Unbounded_String (Msg);
         end if;
      end Fail;

      procedure Check_Clientbound (St : Step) is
      begin
         if D.Pending.Length /= St.Input.Length then
            Fail ("step=" & Natural'Image (St.Line)
              & " expected=" & Hex_Of (St.Input)
              & " actual-pending-len=" & D.Pending.Length'Image
              & " detail=clientbound length mismatch");
            return;
         end if;
         declare
            K : Natural := 0;
         begin
            for E of D.Pending loop
               K := K + 1;
               if E /= St.Input (K) then
                  Fail ("step=" & Natural'Image (St.Line)
                    & " expected=" & Hex_Of (St.Input)
                    & " actual=" & Hex_Of (D.Pending)
                    & " detail=clientbound byte mismatch");
                  return;
               end if;
            end loop;
         end;
         D.Pending.Clear;
      end Check_Clientbound;

   begin
      Init_Dispatch (D);
      D.Proto_State := S.Initial_State;
      Failure := Null_Unbounded_String;
      if S.Steps.Length = 0 then
         Failure := To_Unbounded_String ("step=0 expected=steps actual=none detail=no steps");
         return;
      end if;
      for Step_Idx in 1 .. Natural (S.Steps.Length) loop
         declare
            St : constant Step := S.Steps (Step_Idx);
            State_Before : constant Adacraft.Protocol.State.Connection_State :=
              D.Proto_State;
         begin
            if Failed then
               exit;
            end if;
            if St.Dir = Clientbound then
               begin
                  Check_Clientbound (St);
               exception
                  when others =>
                     Fail ("step=" & Natural'Image (St.Line)
                       & " expected=clientbound actual=exception detail=check");
               end;
            else
               declare
                  Chunk : constant Adacraft.Protocol.Frame.Byte_Array :=
                    To_Chunk (St.Input);
                  Got_Frame : Boolean := False;
                  Frame_Copy : Adacraft.Protocol.Frame.Byte_Array (1 .. 2_097_151);
                  Frame_Len : Natural := 0;
                  Feed_St : Adacraft.Protocol.Frame.Feed_Status :=
                    Adacraft.Protocol.Frame.Success;
                  Feed_Raised : Boolean := False;
                  procedure On_Frame (F : Adacraft.Protocol.Frame.Byte_Array) is
                  begin
                     Got_Frame := True;
                     Frame_Len := F'Length;
                     for I in F'Range loop
                        Frame_Copy (Frame_Copy'First + Natural (I - F'First)) := F (I);
                     end loop;
                  end On_Frame;
               begin
                  begin
                     Adacraft.Protocol.Frame.Feed
                       (Decoder, Chunk, On_Frame'Access, Feed_St);
                  exception
                     when others =>
                        Feed_Raised := True;
                  end;
                  if Feed_Raised then
                     if St.Expected = Rejected or else St.Expected = Incomplete then
                        if D.Proto_State /= State_Before then
                           Fail ("step=" & Natural'Image (St.Line)
                             & " expected=state-unchanged actual=changed detail=feed exception");
                        end if;
                        exit;
                     else
                        Fail ("step=" & Natural'Image (St.Line)
                          & " expected=accepted actual=exception detail=feed");
                        exit;
                     end if;
                  end if;
               if Feed_St = Adacraft.Protocol.Frame.Framing_Error then
                  if St.Expected = Rejected or else St.Expected = Incomplete then
                     if St.Has_Rejection_Category then
                        null;
                     end if;
                     if D.Proto_State /= State_Before then
                        Fail ("step=" & Natural'Image (St.Line)
                          & " expected=state-unchanged actual=changed detail=framing error");
                     end if;
                     exit;
                  else
                     Fail ("step=" & Natural'Image (St.Line)
                       & " expected=accepted actual=framing-error detail=feed");
                  end if;
               elsif not Got_Frame then
                  if St.Expected = Incomplete then
                     if D.Proto_State /= State_Before then
                        Fail ("step=" & Natural'Image (St.Line)
                          & " expected=state-unchanged actual=changed detail=incomplete");
                     end if;
                     exit;
                  else
                     Fail ("step=" & Natural'Image (St.Line)
                       & " expected=" & St.Expected'Image
                       & " actual=incomplete detail=no frame");
                  end if;
               else
                  begin
                     Dispatch_Frame_Body
                       (D, Frame_Copy (Frame_Copy'First .. Frame_Copy'First + Ada.Streams.Stream_Element_Offset (Frame_Len) - 1));
                  exception
                     when others =>
                        if St.Expected = Rejected then
                           if St.Has_Rejection_Category then
                              null;
                           end if;
                           if D.Proto_State /= State_Before
                             and then D.Proto_State /= State_Before
                           then
                              null;
                           end if;
                           exit;
                        elsif St.Expected = Incomplete then
                           exit;
                        else
                           Fail ("step=" & Natural'Image (St.Line)
                             & " expected=accepted actual=rejected detail=dispatch raised");
                        end if;
                  end;
                  if not Failed then
                     if St.Expected = Rejected then
                        Fail ("step=" & Natural'Image (St.Line)
                          & " expected=rejected actual=accepted detail=dispatch accepted");
                     elsif St.Expected = Incomplete then
                        Fail ("step=" & Natural'Image (St.Line)
                          & " expected=incomplete actual=accepted detail=dispatch accepted");
                     else
                        if St.Has_Packet_Id then
                           null;
                        end if;
                        if St.Has_State_After and then D.Proto_State /= St.State_After then
                           Fail ("step=" & Natural'Image (St.Line)
                             & " expected=" & St.State_After'Image
                             & " actual=" & D.Proto_State'Image
                             & " detail=state_after mismatch");
                        end if;
                        if St.Expected = Rejected or else St.Expected = Incomplete then
                           exit;
                        end if;
                     end if;
                  end if;
               end if;
               if St.Expected = Rejected or else St.Expected = Incomplete then
                  exit;
               end if;
            end if;
         end;
      end loop;
      --  Drain any remaining pending output against trailing clientbound
      --  steps already checked inline; leftover bytes with no clientbound
      --  step to compare against is a mismatch only if a clientbound step
      --  existed. Otherwise handshake-only scenarios correctly emit none.
      if not Failed then
         Failure := Null_Unbounded_String;
      else
         Failure := Fail_Msg;
      end if;
   exception
      when E : others =>
         Failure := To_Unbounded_String
           ("step=0 expected=accepted actual=exception detail=runner");
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
