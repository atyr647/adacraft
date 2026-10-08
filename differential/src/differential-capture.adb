with Ada.Exceptions;
with Adacraft.Protocol.State;
with Differential.Capture.Wire;

package body Differential.Capture is
   package T renames Differential.Transcript;
   package S renames Adacraft.Protocol.State;

   procedure Append
     (Result    : in out T.Transcript;
      State     : S.Connection_State;
      Direction : T.Direction_T;
      Packet_Id : S.Packet_Id)
   is
   begin
      Result.Entries.Append
        ((State => State, Direction => Direction, Packet_Id => Packet_Id));
   end Append;

   procedure Run
     (S          : Scenario;
      Host       : String;
      Port       : Positive;
      Result     : out T.Transcript)
   is
      Target : Differential.Capture.Wire.Connection;
      State  : S.Connection_State := S.Initial_State;
   begin
      Result := (Entries => T.Entry_Vectors.Empty_Vector,
                 Outcome => T.Completed);

      --  A failed connection is a setup error: no transcript has begun.
      begin
         Differential.Capture.Wire.Connect (Target, Host, Port);
      exception
         when E : others =>
            raise Setup_Error with Ada.Exceptions.Exception_Message (E);
      end;

      begin
         for Step of S.Steps loop
            if Step.Direction = T.Serverbound then
               Append (Result, State, T.Serverbound, Step.Packet_Id);
               Differential.Capture.Wire.Send_Packet
                 (Target, Step.Packet_Id, Step.Payload);
               declare
                  Reply : S.Packet_Id;
                  Before : constant S.Connection_State := State;
               begin
                  Differential.Capture.Wire.Receive_Packet
                    (Target, Reply);
                  Append (Result, State, T.Clientbound, Reply);
                  declare
                     Transition : constant S.Transition_Result :=
                       S.Transition
                         (State,
                          (Direction => S.Clientbound,
                           Id => Reply,
                           Intent => 0));
                  begin
                     if Transition.Kind /= S.Rejected then
                        State := Transition.Next_State;
                     end if;
                  end;
                  pragma Unreferenced (Before);
               end;
            else
               declare
                  Reply : S.Packet_Id;
               begin
                  Differential.Capture.Wire.Receive_Packet (Target, Reply);
                  Append (Result, State, T.Clientbound, Reply);
                  declare
                     Transition : constant S.Transition_Result :=
                       S.Transition
                         (State,
                          (Direction => S.Clientbound,
                           Id => Reply,
                           Intent => 0));
                  begin
                     if Transition.Kind /= S.Rejected then
                        State := Transition.Next_State;
                     end if;
                  end;
               end;
            end if;

            if Step.Direction = T.Serverbound then
               declare
                  Transition : constant S.Transition_Result :=
                    S.Transition
                      (State,
                       (Direction => S.Serverbound,
                        Id => Step.Packet_Id,
                        Intent => Step.Intent));
               begin
                  if Transition.Kind /= S.Rejected then
                     State := Transition.Next_State;
                  end if;
               end;
            end if;
         end loop;
      exception
         when others =>
            --  Wire currently reports peer-close, timeout and decode failure
            --  through Socket_Error; retain the failure as a terminal outcome.
            Result.Outcome := T.Decode_Error;
      end;

      Differential.Capture.Wire.Close (Target);
   exception
      when others =>
         Differential.Capture.Wire.Close (Target);
         raise;
   end Run;
end Differential.Capture;
