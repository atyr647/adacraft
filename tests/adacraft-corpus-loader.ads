package Adacraft.Corpus.Loader is

   --  Per-scenario compression override. Disabled by default (negative)
   --  so existing scenarios keep uncompressed framing.
   Compression_Threshold_Default : constant Integer := -1;

   function Discover (Dir : String) return Name_Vectors.Vector;

   function Parse
     (Text   : String;
      Path   : String;
      S      : out Scenario;
      Errors : in out Error_Vectors.Vector) return Boolean;

   procedure Load
     (Dir       : String;
      Scenarios : out Scenario_Vectors.Vector;
      Errors    : out Error_Vectors.Vector);

   function Format_Error (E : Error) return String;

   --  Threshold registered for the scenario with the given Id.
   --  Returns Compression_Threshold_Default when absent or unknown.
   function Compression_Threshold_For (Id : String) return Integer;

   procedure Clear_Compression_Thresholds;

end Adacraft.Corpus.Loader;
