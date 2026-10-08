--  Lab-only command-line parsing for the differential harness.
--  No state/compare logic here; argument validation only.

with Ada.Strings.Unbounded;

package Differential.Args is
   pragma Elaborate_Body;

   Usage_Error : exception;

   type Mode_Kind is (Selftest, Run);

   type Endpoint is record
      Host : Ada.Strings.Unbounded.Unbounded_String;
      Port : Natural := 0;
   end record;

   type Options is record
      Mode          : Mode_Kind := Run;
      Has_Oracle    : Boolean := False;
      Has_Candidate : Boolean := False;
      Oracle        : Endpoint;
      Candidate     : Endpoint;
   end record;

   Max_Args : constant := 64;

   subtype Arg_Index is Positive range 1 .. Max_Args;

   type Arg_Array is
     array (Arg_Index range <>) of Ada.Strings.Unbounded.Unbounded_String;

   --  Core parser over an explicit argument list (offline, testable).
   procedure Parse_Args (Args : in Arg_Array; Opts : out Options);

   --  Parser over Ada.Command_Line. Raises Usage_Error on any misuse.
   function Parse return Options;

   --  Prints usage text to Standard_Error.
   procedure Usage;

end Differential.Args;
