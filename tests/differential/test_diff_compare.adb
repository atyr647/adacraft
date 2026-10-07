with Ada.Strings.Unbounded;
with Ada.Text_IO;
with Ada.Command_Line;
with Adacraft.Protocol.State;
with Differential.Compare;
with Differential.Obs;

--  Offline comparison tests (DR-9).
procedure Test_Diff_Compare is
   package C renames Differential.Compare;
   package O renames Differential.Obs;
   package PS renames Adacraft.Protocol.State;
   use type C.Diff_Kind;
   use type Ada.Containers.Count_Type;

   Failures : Natural := 0;

   procedure Check (Cond : Boolean; Name : String) is
   begin
      if not Cond then
         Ada.Text_IO.Put_Line ("FAIL " & Name);
         Failures := Failures + 1;
      end if;
   end Check;

   function Status_Step (Max : String) return O.Step_Observation is
      S : O.Step_Observation;
      Added : Boolean;
   begin
      S.State := PS.Status;
      O.Set_Field (S, O.F_Status_Version_Protocol, "777", Added);
      O.Set_Field (S, O.F_Status_Players_Max, Max, Added);
      return S;
   end Status_Step;

   function Obs_Of (S : O.Step_Observation) return O.Observation is
      R : O.Observation;
   begin
      R.Steps.Append (S);
      return R;
   end Obs_Of;

   function First_Kind (R : C.Result) return C.Diff_Kind is
     (R.Diffs.First_Element.Kind);

   A, B : O.Observation;
   S    : O.Step_Observation;
   R    : C.Result;
begin
   --  Equal -> pass.
   A := Obs_Of (Status_Step ("20"));
   B := Obs_Of (Status_Step ("20"));
   R := C.Compare (A, B);
   Check (R.Pass and then R.Diffs.Is_Empty, "equal passes");

   --  Protocol field change -> fail with path and both values.
   B := Obs_Of (Status_Step ("21"));
   R := C.Compare (A, B);
   Check (not R.Pass and then R.Diffs.Length = 1, "field change fails");
   if R.Diffs.Length = 1 then
      Check (First_Kind (R) = C.Value_Differs, "value kind");
      Check (Ada.Strings.Unbounded.To_String (R.Diffs.First_Element.Path)
             = O.F_Status_Players_Max, "path");
      Check (Ada.Strings.Unbounded.To_String
               (R.Diffs.First_Element.Oracle_Value) = "20"
             and then Ada.Strings.Unbounded.To_String
               (R.Diffs.First_Element.Adacraft_Value) = "21", "values");
      Check (R.Diffs.First_Element.Step = 1, "step index");
   end if;

   --  Ignored/unlisted field change -> pass.
   S := Status_Step ("20");
   O.Add_Unlisted (S, "status.favicon", "size=100");
   B := Obs_Of (S);
   R := C.Compare (A, B);
   Check (R.Pass, "unlisted change passes");

   --  Missing / extra field.
   S := Status_Step ("20");
   S.Fields.Delete (O.F_Status_Players_Max);
   B := Obs_Of (S);
   R := C.Compare (A, B);
   Check (not R.Pass and then First_Kind (R) = C.Field_Missing,
          "field missing");
   R := C.Compare (B, A);
   Check (not R.Pass and then First_Kind (R) = C.Field_Extra, "field extra");

   --  Disconnected outcome.
   S := Status_Step ("20");
   S.Result := O.Disconnected;
   B := Obs_Of (S);
   R := C.Compare (A, B);
   Check (not R.Pass and then First_Kind (R) = C.Outcome_Differs,
          "disconnected outcome");

   --  Missing / extra step.
   B := A;
   B.Steps.Append (Status_Step ("20"));
   R := C.Compare (A, B);
   Check (not R.Pass and then First_Kind (R) = C.Step_Extra, "step extra");
   R := C.Compare (B, A);
   Check (not R.Pass and then First_Kind (R) = C.Step_Missing,
          "step missing");
   if R.Diffs.Length = 1 then
      Check (R.Diffs.First_Element.Step = 2, "missing step index");
   end if;

   --  State progression divergence reported first.
   S := Status_Step ("21");
   S.State := PS.Login;
   B := Obs_Of (S);
   R := C.Compare (A, B);
   Check (not R.Pass and then R.Diffs.Length = 2
          and then First_Kind (R) = C.State_Differs,
          "state divergence first");

   if Failures = 0 then
      Ada.Text_IO.Put_Line ("test_diff_compare ok");
   else
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
   end if;
end Test_Diff_Compare;
