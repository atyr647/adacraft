with Ada.Strings.Unbounded;

package Differential.Args is
   Usage_Error : exception;

   type Options is record
      Selftest       : Boolean := False;
      Oracle_Host    : Ada.Strings.Unbounded.Unbounded_String;
      Oracle_Port    : Natural := 0;
      Candidate_Host : Ada.Strings.Unbounded.Unbounded_String;
      Candidate_Port : Natural := 0;
   end record;

   function Parse return Options;
   procedure Print_Usage;
end Differential.Args;
