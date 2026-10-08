with Ada.Strings.Unbounded;

package Differential.Args is
   type Endpoint is record
      Host : Ada.Strings.Unbounded.Unbounded_String;
      Port : Positive range 1 .. 65_535 := 1;
   end record;

   type Options is record
      Selftest  : Boolean := False;
      Oracle    : Endpoint;
      Candidate : Endpoint;
   end record;

   procedure Parse (Result : out Options);
end Differential.Args;
