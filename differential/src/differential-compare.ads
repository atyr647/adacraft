with Differential.Transcript;

package Differential.Compare is

   type Verdict is (Match, Diverge);

   function Compare
     (A : Differential.Transcript.Transcript;
      B : Differential.Transcript.Transcript) return Verdict;
   --  MATCH iff element-wise (State, Dir, Packet_Id) equal AND terminal
   --  outcomes equal; else DIVERGE. Length or outcome difference counts
   --  as DIVERGE. Payload is never compared (not stored).

   function First_Difference
     (A : Differential.Transcript.Transcript;
      B : Differential.Transcript.Transcript) return Natural;
   --  0 means no difference (Compare would be Match).
   --  Otherwise 1-based index of first differing entry; when one
   --  transcript is a strict prefix of the other, returns Min_Length + 1;
   --  when entries are equal but outcomes differ, returns Length + 1
   --  (1 when both are empty).

end Differential.Compare;
