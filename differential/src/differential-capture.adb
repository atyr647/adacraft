with Adacraft.Protocol.State;
with Differential.Capture.Wire;

package body Differential.Capture is

   use type Adacraft.Protocol.State.Result_Kind;
   use type Differential.Transcript.Direction_T;
   use type Differential.Transcript.Terminal_Outcome;

   procedure Empty_Provider (Count : out Natural) is
   begin
      Count := 0;
   end Empty_Provider;

   procedure Track_And_Append
     (T     : in out Differential.Transcript.Transcript;
      Cur   : in out Adacraft.Protocol.State.Connection_State;
      Dir   : in Differential.Transcript.Direction_T;
      Pkt   : in Natural;
      Abort_Flag : out Boolean)
   is
      Ev : constant Adacraft.Protocol.State.Packet_Event :=
        (Direction =>
           (if Dir = Differential.Transcript.Serverbound
            then Adacraft.Protocol.State.Serverbound
            else Adacraft.Protocol.State.Clientbound),
         Id     => Adacraft.Protocol.State.Packet_Id (Pkt),
         Intent => 0);
      Res : constant Adacraft.Protocol.State.Transition_Result :=
        Adacraft.Protocol.State.Transition (Cur, Ev);
   begin
      Abort_Flag := False;
      if Res.Kind = Adacraft.Protocol.State.Rejected then
         Differential.Transcript.Set_Outcome
           (T, Differential.Transcript.Protocol_Error);
         Abort_Flag := True;
         return;
      end if;
      Cur := Res.Next_State;
      Differential.Transcript.Append
        (T, (State     => Cur,
             Dir       => Dir,
             Packet_Id => Pkt));
   end Track_And_Append;
   pragma Unreferenced (Track_And_Append);

   procedure Capture_Single
     (Host           : in String;
      Port           : in Natural;
      Scenario_Index : in Natural;
      T              : out Differential.Transcript.Transcript)
   is
      pragma Unreferenced (Scenario_Index);
      C   : Differential.Capture.Wire.Wire_Connection;
      Oc  : Differential.Transcript.Terminal_Outcome;
      Cur : Adacraft.Protocol.State.Connection_State :=
        Adacraft.Protocol.State.Initial_State;
      Abort_Flag : Boolean := False;
      pragma Unreferenced (Cur);
      pragma Unreferenced (Abort_Flag);
   begin
      T := Differential.Transcript.Empty_Transcript
        (Differential.Transcript.Completed);
      Differential.Capture.Wire.Open (C, Host, Port, Oc);
      if Oc /= Differential.Transcript.Completed then
         Differential.Transcript.Set_Outcome (T, Oc);
         Differential.Capture.Wire.Close (C);
         return;
      end if;
      if not Differential.Capture.Wire.Is_Open (C) then
         Differential.Transcript.Set_Outcome
           (T, Differential.Transcript.Connect_Failed);
         Differential.Capture.Wire.Close (C);
         return;
      end if;
      --  Empty_Provider: zero steps to drive. The per-packet path
      --  (Wire send + #118 transition via Track_And_Append) is
      --  preserved for the future loader without changing
      --  behaviour today.
      Differential.Transcript.Set_Outcome
        (T, Differential.Transcript.Completed);
      Differential.Capture.Wire.Close (C);
   exception
      when others =>
         begin
            Differential.Capture.Wire.Close (C);
         exception
            when others => null;
         end;
         T := Differential.Transcript.Empty_Transcript
           (Differential.Transcript.Protocol_Error);
   end Capture_Single;

   procedure Capture_Pair
     (Oracle_Host    : in String;
      Oracle_Port    : in Natural;
      Candidate_Host : in String;
      Candidate_Port : in Natural;
      Scenario_Index : in Natural;
      Oracle_T       : out Differential.Transcript.Transcript;
      Candidate_T    : out Differential.Transcript.Transcript)
   is
   begin
      Capture_Single (Oracle_Host, Oracle_Port, Scenario_Index, Oracle_T);
      Capture_Single
        (Candidate_Host, Candidate_Port, Scenario_Index, Candidate_T);
   exception
      when others =>
         Oracle_T := Differential.Transcript.Empty_Transcript
           (Differential.Transcript.Protocol_Error);
         Candidate_T := Differential.Transcript.Empty_Transcript
           (Differential.Transcript.Protocol_Error);
   end Capture_Pair;

end Differential.Capture;
