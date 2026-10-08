--  Lab-only CLI parsing for the differential driver.
--  Parses --oracle/--candidate HOST:PORT and --selftest.
--  Usage goes to stderr; nothing is written to stdout on error.
with Ada.Strings.Unbounded;

package Differential.Args is

   use Ada.Strings.Unbounded;

   type Endpoint is record
      Host : Unbounded_String := Null_Unbounded_String;
      Port : Natural := 0;
   end record;

   --  Parse the process command line.
   --  Valid is False on any usage error:
   --    missing/malformed endpoint, bad port, unknown option,
   --    --selftest combined with an endpoint.
   procedure Parse_Command_Line
     (Is_Selftest : out Boolean;
      Oracle      : out Endpoint;
      Candidate   : out Endpoint;
      Valid       : out Boolean);

   --  Parse one HOST:PORT value. Returns True on success.
   --  Port must be numeric in 1 .. 65535 with a non-empty host.
   function Try_Parse_Endpoint
     (Text   : in String;
      Result : out Endpoint) return Boolean;

   --  Print usage text to stderr.
   procedure Print_Usage;

end Differential.Args;
