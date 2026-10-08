with Ada.Strings.Bounded;

package Differential.Args is

   package Host_Strings is new Ada.Strings.Bounded.Generic_Bounded_Length
     (Max => 255);

   package Msg_Strings is new Ada.Strings.Bounded.Generic_Bounded_Length
     (Max => 256);

   type Mode_Kind is (Run, Selftest);

   subtype Port_Number is Integer range 1 .. 65_535;

   type Endpoint is record
      Host : Host_Strings.Bounded_String;
      Port : Port_Number := 25565;
      Set  : Boolean := False;
   end record;

   type Config is record
      Mode      : Mode_Kind := Run;
      Oracle    : Endpoint;
      Candidate : Endpoint;
      Valid     : Boolean := False;
      Error_Msg : Msg_Strings.Bounded_String;
   end record;

   function Parse return Config;

   procedure Print_Usage;

end Differential.Args;
