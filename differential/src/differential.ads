--  Lab-only root package of the differential driver.
package Differential is

   Comparison_Schema_Version : constant Positive := 1;
   Normalization_Version     : constant Positive := 1;
   Ignore_List_Version       : constant Positive := 1;
   --  The ignore list itself is Differential.Normalize.Ignore_List,
   --  versioned by Ignore_List_Version.

end Differential;
