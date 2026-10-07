with Differential.Corpus;
with Differential.Obs;

package Differential.Runner is

   Max_Observations : constant := 4096;

   --  Raised when a corpus step cannot be turned into a packet to send.
   --  Callers map it to ERROR, never DIFF.
   Step_Encoding_Error : exception;

   --  Runs one scenario against one endpoint on a fresh connection.
   --  Sends all serverbound steps, then reads until close, timeout,
   --  malformed frame, or the observation bound. Observations are in
   --  receipt order. A connect failure yields one Connect_Failed.
   procedure Run
     (Host       : String;
      Port       : Natural;
      Timeout_Ms : Natural;
      Sc         : Corpus.Scenario;
      Result     : out Obs.Observation_Vectors.Vector);

end Differential.Runner;
