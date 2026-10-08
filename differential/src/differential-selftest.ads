with Differential.Transcript;

package Differential.Selftest is

   function Base_Result return Differential.Transcript.Transcript;
   --  Canonical two-entry transcript used by all selftest cases.

   function Check return Natural;
   --  Offline selftest: calls Transcript + Compare directly for 7 cases
   --  (identical MATCH; diff ID/state/direction/length/outcome DIVERGE;
   --  tuple-equal MATCH). Prints pass line. Returns 0 on success, 1 on
   --  any failed check. No network.

end Differential.Selftest;
