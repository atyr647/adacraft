with Ada.Text_IO;

package Differential.Args is

   type Mode_Kind is (Run_Compare, Run_Selftest, Usage_Error);

   type Endpoint is record
      Host : String (1 .. 256) := (others => ' ');
      Host_Len : Natural := 0;
      Port : Natural := 0;
   end record;

   function Host_Image (E : Endpoint) return String;

   type Config is record
      Mode : Mode_Kind := Usage_Error;
      Oracle : Endpoint;
      Candidate : Endpoint;
   end record;

   function Parse return Config;
   --  Reads Ada.Command_Line. Run_Compare requires exactly
   --  --oracle <host:port> --candidate <host:port> (any order).
   --  Run_Selftest requires exactly --selftest alone.
   --  Anything else (missing, malformed, unknown, combined)
   --  yields Usage_Error.

   procedure Put_Usage (File : in out Ada.Text_IO.File_Type);
   --  Writes usage text to File (caller passes Standard_Error).

end Differential.Args;
