with Differential.Capture.Wire;

package body Differential.Capture is

   procedure Empty_Provider
     (List  : out Scenario_Array;
      Count : out Natural)
   is
   begin
      List := (others =>
        (Name => Name_Strings.Null_Bounded_String));
      Count := 0;
   end Empty_Provider;

   function Capture_Scenario
     (S      : Scenario;
      Target : Args.Endpoint) return Transcript.Transcript
   is
      pragma Unreferenced (S);
      T    : Transcript.Transcript;
      Sess : Wire.Session;
   begin
      Transcript.Clear (T);
      Wire.Connect (Sess, Target);
      begin
         while Wire.Recv_Packet (Sess, T) loop
            null;
         end loop;
         Wire.Close (Sess);
      exception
         when others =>
            Wire.Close (Sess);
            raise;
      end;
      return T;
   end Capture_Scenario;

   procedure Run_All
     (Cfg     : Args.Config;
      Results : out Result_Array;
      Count   : out Natural)
   is
      List  : Scenario_Array;
      Total : Natural;
   begin
      Results := (others =>
        (Name      => Name_Strings.Null_Bounded_String,
         Oracle    => Transcript.Transcript'(others => <>),
         Candidate => Transcript.Transcript'(others => <>)));
      Empty_Provider (List, Total);
      Count := Total;
      for I in 1 .. Total loop
         Results (I).Name := List (I).Name;
         Results (I).Oracle :=
           Capture_Scenario (List (I), Cfg.Oracle);
         Results (I).Candidate :=
           Capture_Scenario (List (I), Cfg.Candidate);
      end loop;
   end Run_All;

end Differential.Capture;
