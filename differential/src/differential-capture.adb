with Ada.Exceptions;
with GNAT.Sockets;
with Adacraft.Protocol.State;
with Differential.Capture.Wire;

package body Differential.Capture is
   package T renames Differential.Transcript;
   package State_Machine renames Adacraft.Protocol.State;

   procedure Append
     (Result    : in out T.Transcript;
      State     : State_Machine.Connection_State;
      Direction : T.Direction_T;
      Packet_Id : State_Machine.Packet_Id)
   is
   begin
      Result.Entries.Append
        ((State => State, Direction => Direction, Packet_Id => Packet_Id));
   end Append;

   procedure Apply_Transition
     (Current   : in out State_Machine.Connection_State;
      Direction : State_Machine.Packet_Direction;
      Packet_Id : State_Machine.Packet_Id;
      Intent    : State_Machine.Handshake_Intent := 0)
   is
      Transition : constant State_Machine.Transition_Result :=
        State_Machine.Transition
          (Current,
           (Direction => Direction, Id => Packet_Id, Intent => Intent));
   begin
      if Transition.Kind /= State_Machine.Rejected then
         Current := Transition.Next_State;
      end if;
   end Apply_Transition;

   procedure Run
     (Scenario : Differential.Capture.Scenario;
      Host     : String;
      Port     : Positive;
      Result   : out T.Transcript)
   is
      Target : Differential.Capture.Wire.Connection;
      Current_State : State_Machine.Connection_State :=
        State_Machine.Initial_State;
   begin
      Result := (Entries => T.Entry_Vectors.Empty_Vector,
                 Outcome => T.Completed);

      --  Connect before beginning the transcript: failures are setup errors.
      begin
         Differential.Capture.Wire.Connect (Target, Host, Port);
      exception
         when E : others =>
            raise Setup_Error with Ada.Exceptions.Exception_Message (E);
      end;

      begin
         for Step of Scenario.Steps loop
            if Step.Direction = T.Serverbound then
               Differential.Capture.Wire.Send_Packet
                 (Target, Adacraft.Protocol.Packet_Id (Step.Packet_Id),
                  Step.Payload);
               Append (Result, Current_State, T.Serverbound, Step.Packet_Id);
               Apply_Transition
                 (Current_State, State_Machine.Serverbound, Step.Packet_Id,
                  Step.Intent);
            end if;

            declare
               Reply : Adacraft.Protocol.Packet_Id;
               Reply_State : constant State_Machine.Connection_State :=
                 Current_State;
            begin
               Differential.Capture.Wire.Receive_Packet (Target, Reply);
               Append
                 (Result, Reply_State, T.Clientbound,
                  State_Machine.Packet_Id (Reply));
               Apply_Transition
                 (Current_State, State_Machine.Clientbound,
                  State_Machine.Packet_Id (Reply));
            end;
         end loop;
      exception
         when E : GNAT.Sockets.Socket_Error =>
            declare
               Message : constant String :=
                 Ada.Exceptions.Exception_Message (E);
            begin
               if Message = "invalid frame" then
                  Result.Outcome := T.Decode_Error;
               elsif Message = "timed out" then
                  Result.Outcome := T.Timeout;
               else
                  Result.Outcome := T.Closed_By_Peer;
               end if;
            end;
         when others =>
            Result.Outcome := T.Decode_Error;
      end;

      Differential.Capture.Wire.Close (Target);
   exception
      when others =>
         Differential.Capture.Wire.Close (Target);
         raise;
   end Run;

   procedure Run_Pair
     (Scenario         : Differential.Capture.Scenario;
      Oracle_Host      : String;
      Oracle_Port      : Positive;
      Candidate_Host   : String;
      Candidate_Port   : Positive;
      Oracle_Result    : out T.Transcript;
      Candidate_Result : out T.Transcript)
   is
   begin
      Run (Scenario, Oracle_Host, Oracle_Port, Oracle_Result);
      Run (Scenario, Candidate_Host, Candidate_Port, Candidate_Result);
   end Run_Pair;
end Differential.Capture;
