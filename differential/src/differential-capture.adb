--  Lab-only capture orchestration body. Delegates all socket and
--  framing work to Differential.Capture.Wire.

with Ada.Strings.Unbounded;
with Adacraft.Protocol;
with Adacraft.Protocol.State;
with Differential.Args;
with Differential.Transcript;
with Differential.Capture.Wire;

package body Differential.Capture is

   function Empty_Script return Script is
   begin
      return Script_Vectors.Empty_Vector;
   end Empty_Script;

   function Count (P : Empty_Provider) return Natural is
      pragma Unreferenced (P);
   begin
      return 0;
   end Count;

   function Scenario_Count return Natural is
   begin
      return 0;
   end Scenario_Count;

   function To_Octets (Data : Octet_Vectors.Vector)
     return Adacraft.Protocol.Octets
   is
      use Adacraft.Protocol;
      Len : constant Natural := Natural (Octet_Vectors.Length (Data));
   begin
      if Len = 0 then
         return (1 .. 0 => 0);
      end if;
      declare
         Out_Arr : Octets (1 .. Len);
      begin
         for I in 1 .. Len loop
            Out_Arr (I) := Octet_Vectors.Element (Data, I);
         end loop;
         return Out_Arr;
      end;
   end To_Octets;

   function Run_Scenario
     (Endpoint : Args.Endpoint;
      Steps    : Script) return Transcript.Target_Result
   is
      use type Adacraft.Protocol.State.Packet_Direction;
      Entries : Transcript.Transcript;
      Outcome : Transcript.Terminal_Outcome := Transcript.Completed;
      Done    : Boolean := False;
      C       : Wire.Connection;
      Host    : constant String :=
        Ada.Strings.Unbounded.To_String (Endpoint.Host);
      Port    : constant Natural := Endpoint.Port;
   begin
      if Host'Length = 0 or else Port < 1 or else Port > 65_535 then
         return (Entries => Entries, Outcome => Transcript.Driver_Error);
      end if;

      begin
         Wire.Connect (C, Host, Port);
      exception
         when others =>
            return (Entries => Entries, Outcome => Transcript.Driver_Error);
      end;

      begin
         declare
            N : constant Natural := Natural (Script_Vectors.Length (Steps));
         begin
            for I in 1 .. N loop
               exit when Done;
               declare
                  Step : constant Script_Step :=
                    Script_Vectors.Element (Steps, I);
               begin
                  if Step.Dir = Adacraft.Protocol.State.Serverbound then
                     declare
                        St : constant Adacraft.Protocol.State
                          .Connection_State := Wire.Current_State (C);
                     begin
                        Wire.Send_Packet (C, Step.Id, To_Octets (Step.Data));
                        Transcript.Transcript_Vectors.Append
                          (Entries,
                           (State     => St,
                            Direction => Step.Dir,
                            Packet_Id => Step.Id));
                     end;
                  else
                     declare
                        Id     : Adacraft.Protocol.State.Packet_Id;
                        Status : Wire.Receive_Status;
                     begin
                        Wire.Receive_Packet (C, Id, Status);
                        case Status is
                           when Wire.Ok =>
                              declare
                                 St : constant Adacraft.Protocol.State
                                   .Connection_State :=
                                     Wire.Current_State (C);
                              begin
                                 Transcript.Transcript_Vectors.Append
                                   (Entries,
                                    (State     => St,
                                     Direction =>
                                       Adacraft.Protocol.State.Clientbound,
                                     Packet_Id => Id));
                              end;
                           when Wire.Peer_Closed =>
                              Outcome := Transcript.Peer_Closed;
                              Done := True;
                           when Wire.Framing_Error =>
                              Outcome := Transcript.Protocol_Error;
                              Done := True;
                           when Wire.No_Data =>
                              Outcome := Transcript.Timed_Out;
                              Done := True;
                        end case;
                     end;
                  end if;
               end;
            end loop;
         end;
      exception
         when Constraint_Error =>
            Outcome := Transcript.Protocol_Error;
         when others =>
            Outcome := Transcript.Driver_Error;
      end;

      begin
         Wire.Close (C);
      exception
         when others =>
            null;
      end;

      return (Entries => Entries, Outcome => Outcome);
   end Run_Scenario;

end Differential.Capture;
