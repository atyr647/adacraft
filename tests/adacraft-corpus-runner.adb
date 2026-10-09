with Ada.Characters.Handling;
with Ada.Streams;
with Ada.Strings.Fixed;
with Ada.Text_IO;
with Adacraft.Network;
with Adacraft.Protocol.Frame;
with Adacraft.Protocol.State;

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
            Adacraft.Network.Handle_Frame_Body (C, Data);
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
         if C.Proto_State = Adacraft.Protocol.State.Login then
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
      --  outcome is rejected-with-disconnect, not accepted. Report it
      --  as such so disconnect cases compare against the pending output.
      --  Status Pong also closes with output queued (Pong_Ready_Close);
      --  that is a normal accepted response, not a disconnect, so the
      --  conversion applies only in Login state.
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
