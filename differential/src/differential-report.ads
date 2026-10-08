with Differential.Transcript;

package Differential.Report is

   function Entry_Image
     (E : Differential.Transcript.Transcript_Entry) return String;
   --  Deterministic "(State,Dir,Packet_Id)" using enum/integer images only.

   function Outcome_Image
     (O : Differential.Transcript.Terminal_Outcome) return String;
   --  Deterministic outcome image (enum image only).

   function Side_Image
     (T : Differential.Transcript.Transcript;
      Index : Natural) return String;
   --  Image of entry at 1-based Index, or outcome image when Index is
   --  past the end (length/outcome divergence).

   procedure Put_Scenario
     (Name : String;
      Oracle : Differential.Transcript.Transcript;
      Candidate : Differential.Transcript.Transcript);
   --  Prints one deterministic line in corpus order:
   --    "<Name> MATCH" or
   --    "<Name> DIVERGE first=<i> oracle=<> candidate=<>".

   procedure Put_Summary
     (Total : Natural; Matched : Natural; Diverged : Natural);
   --  Prints final "summary total=<> match=<> diverge=<>" line.

end Differential.Report;
