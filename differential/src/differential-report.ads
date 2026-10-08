package Differential.Report is

   --  Deterministic formatting only for the differential driver.
   --  No timestamps, elapsed times, ports, or run-varying data.
   --  Byte-identical output for identical inputs.
   --
   --  Line contract:
   --    "<name> MATCH"
   --    "<name> DIVERGE <detail>"
   --    "total=<T> matched=<M> diverged=<D>"
   --
   --  Pure formatting functions plus thin Put_* wrappers that write
   --  the exact same bytes to Standard_Output.  Exit mapping lives
   --  here so the main only wires children.

   function Match_Line (Name : String) return String;

   function Diverge_Line (Name : String; Detail : String) return String;

   function Summary_Line
     (Total    : Natural;
      Matched  : Natural;
      Diverged : Natural) return String;

   function Length_Detail
     (Expected_Length : Natural;
      Got_Length      : Natural;
      Index           : Natural) return String;

   function Entry_Detail
     (Index           : Positive;
      Expected_Entry  : Differential.Transcript.Entry;
      Got_Entry       : Differential.Transcript.Entry) return String;

   function Outcome_Detail
     (Expected : Differential.Outcome;
      Got      : Differential.Outcome) return String;

   function Entry_Image
     (Item : Differential.Transcript.Entry) return String;

   function Outcome_Image (Value : Differential.Outcome) return String;

   procedure Put_Match (Name : String);

   procedure Put_Diverge (Name : String; Detail : String);

   procedure Put_Summary
     (Total    : Natural;
      Matched  : Natural;
      Diverged : Natural);

   function Exit_For
     (Diverged  : Natural;
      Env_Error : Boolean) return Differential.Exit_Code;

   procedure Apply_Exit
     (Diverged  : Natural;
      Env_Error : Boolean);

end Differential.Report;
