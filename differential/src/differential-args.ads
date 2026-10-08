package Differential.Args is

   Usage_Error : exception;

   type Endpoint is record
      Host : String (1 .. 256) := (others => ' ');
      Host_Len : Natural := 0;
      Port : Natural := 0;
   end record;

   function Host_Image (E : Endpoint) return String;

   type Options is record
      Selftest : Boolean := False;
      Has_Oracle : Boolean := False;
      Has_Candidate : Boolean := False;
      Oracle : Endpoint;
      Candidate : Endpoint;
   end record;

   procedure Parse_Command_Line (Opts : out Options);
   --  Reads Ada.Command_Line. Raises Usage_Error on missing/unknown
   --  option or malformed host:port.

   procedure Parse_Argv
     (Count : Natural;
      Get   : access function (Index : Positive) return String;
      Opts  : out Options);
   --  Testable core: parses Count arguments via Get (1-based).
   --  Raises Usage_Error on any usage violation.

   procedure Print_Usage;
   --  Writes usage text to Ada.Text_IO.Standard_Error.

end Differential.Args;
