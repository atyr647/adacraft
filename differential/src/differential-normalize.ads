with Differential.Obs;

--  The single normalization path (A10). Pure; applied identically to the
--  oracle and AdaCraft observations; no target-specific branches.
package Differential.Normalize is

   --  Versioned by Differential.Ignore_List_Version. Paths excluded from
   --  comparison; they are still inventoried in the unlisted map.
   Ignore_List : constant String :=
     "status.favicon status.players.sample status.enforcesSecureChat "
     & "status.previewsChat status.preventsChatReports status.timestamp";

   function Is_Ignored (Path : String) return Boolean;

   --  Compact JSON with object keys sorted; returns Text unchanged if it
   --  is not valid JSON.
   function Canonical_Json (Text : String) return String;

   --  Bare string -> {"text":...}; other values unchanged.
   function Lift_Text (Value : String) return String;

   function Normalize
     (Observation : Differential.Obs.Observation)
      return Differential.Obs.Observation;

end Differential.Normalize;
