package Adacraft.Corpus.Loader is

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

end Adacraft.Corpus.Loader;
