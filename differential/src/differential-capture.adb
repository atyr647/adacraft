--  Lab-only capture orchestration body. No GNAT.Sockets, no framing,
--  no VarInt calls: only Differential.Capture.Wire performs those.
with Adacraft.Protocol.State;
with Differential.Capture.Wire;

package body Differential.Capture is

   use Differential.Transcript;

   function Scenario_Name (S : Scenario_Kind) return String is
   begin
      case S is
         when Empty_Provider =>
            return "Empty_Provider";
      end case;
   end Scenario_Name;

   function Scenario_Count return Natural is
   begin
      return 0;
   end Scenario_Count;

   function Scenario_At (Index : Positive) return Scenario_Kind is
      pragma Unreferenced (Index);
   begin
      return Empty_Provider;
   end Scenario_At;

   procedure Run_Scenario
     (Target        : in Differential.Args.Endpoint;
      Scenario      : in Scenario_Kind;
      T             : out Differential.Transcript.Transcript;
      Pre_Run_Failed : out Boolean)
   is
      Current : Adacraft.Protocol.State.Connection_State :=
        Adacraft.Protocol.State.Initial_State;
      pragma Unreferenced (Current);
      W : Differential.Capture.Wire.Session;
      Ok : Boolean;
   begin
      Clear (T);
      Pre_Run_Failed := False;
      case Scenario is
         when Empty_Provider =>
            Differential.Capture.Wire.Open (Target, W, Ok);
            if not Ok then
               Set_Outcome (T, Connection_Failure);
               Pre_Run_Failed := True;
               return;
            end if;
            Differential.Capture.Wire.Close (W);
            Set_Outcome (T, Completed);
      end case;
   end Run_Scenario;

end Differential.Capture;
