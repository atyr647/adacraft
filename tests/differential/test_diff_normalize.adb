with Ada.Command_Line;
with Ada.Text_IO;
with Differential.Normalize;
with Differential.Obs;

--  Offline normalization tests (DR-8).
procedure Test_Diff_Normalize is
   package N renames Differential.Normalize;
   package O renames Differential.Obs;
   use type O.Field_Maps.Map;
   use type O.Outcome;
   use type Ada.Containers.Count_Type;

   Failures : Natural := 0;

   procedure Check (Cond : Boolean; Name : String) is
   begin
      if not Cond then
         Ada.Text_IO.Put_Line ("FAIL " & Name);
         Failures := Failures + 1;
      end if;
   end Check;

   function Same (A, B : O.Observation) return Boolean is
   begin
      if A.Steps.Length /= B.Steps.Length then
         return False;
      end if;
      for I in A.Steps.First_Index .. A.Steps.Last_Index loop
         if A.Steps (I).Fields /= B.Steps (I).Fields
           or else A.Steps (I).Unlisted /= B.Steps (I).Unlisted
           or else A.Steps (I).Result /= B.Steps (I).Result
           or else A.Steps (I).State /= B.Steps (I).State
         then
            return False;
         end if;
      end loop;
      return True;
   end Same;

   procedure Put
     (S : in out O.Step_Observation; Name, Value : String)
   is
      Added : Boolean;
   begin
      O.Set_Field (S, Name, Value, Added);
   end Put;

   A, B, X, Y, R : O.Observation;
   S1, S2, S3 : O.Step_Observation;
begin
   --  Reordering of object keys and field insertion order.
   Put (S1, O.F_Status_Description, "{""b"":1,""a"":2}");
   Put (S1, O.F_Status_Players_Max, "20");
   Put (S2, O.F_Status_Players_Max, "20");
   Put (S2, O.F_Status_Description, "{ ""a"" : 2, ""b"":1 }");
   A.Steps.Append (S1);
   B.Steps.Append (S2);
   Check (Same (N.Normalize (A), N.Normalize (B)), "reordering");
   Check (N.Normalize (A).Steps (1).Fields.Element
            (O.F_Status_Description) = "{""a"":2,""b"":1}", "sorted keys");

   --  String vs component.
   S1 := (others => <>);
   S2 := (others => <>);
   Put (S1, O.F_Status_Description, """Hello""");
   Put (S2, O.F_Status_Description, "{""text"":""Hello""}");
   A.Steps.Clear;
   B.Steps.Clear;
   A.Steps.Append (S1);
   B.Steps.Append (S2);
   Check (Same (N.Normalize (A), N.Normalize (B)), "string vs component");
   Check (N.Normalize (A).Steps (1).Fields.Element
            (O.F_Status_Description) = "{""text"":""Hello""}", "lifted");

   --  ID renumbering: first-seen order.
   S1 := (others => <>);
   S2 := (others => <>);
   S3 := (others => <>);
   Put (S1, O.F_Login_Reason, "{""text"":""x"",""id"":""abc-1""}");
   Put (S2, O.F_Login_Reason, "{""text"":""x"",""id"":""zzz""}");
   Put (S3, O.F_Login_Reason, "{""text"":""x"",""id"":""abc-1""}");
   X.Steps.Append (S1);
   X.Steps.Append (S2);
   X.Steps.Append (S3);
   S1 := (others => <>);
   S2 := (others => <>);
   S3 := (others => <>);
   Put (S1, O.F_Login_Reason, "{""id"":""q"",""text"":""x""}");
   Put (S2, O.F_Login_Reason, "{""id"":""r"",""text"":""x""}");
   Put (S3, O.F_Login_Reason, "{""id"":""q"",""text"":""x""}");
   Y.Steps.Append (S1);
   Y.Steps.Append (S2);
   Y.Steps.Append (S3);
   R := N.Normalize (X);
   Check (Same (R, N.Normalize (Y)), "id renumbering equal");
   Check (R.Steps (1).Fields.Element (O.F_Login_Reason)
          = "{""id"":1,""text"":""x""}", "first id is 1");
   Check (R.Steps (2).Fields.Element (O.F_Login_Reason)
          = "{""id"":2,""text"":""x""}", "second id is 2");
   Check (R.Steps (3).Fields.Element (O.F_Login_Reason)
          = "{""id"":1,""text"":""x""}", "repeat id reused");

   --  Grouping: same fields delivered in a different order give one result.
   S1 := (others => <>);
   S2 := (others => <>);
   Put (S1, O.F_Status_Version_Name, """26.3""");
   Put (S1, O.F_Status_Version_Protocol, "777");
   Put (S2, O.F_Status_Version_Protocol, "777");
   Put (S2, O.F_Status_Version_Name, """26.3""");
   A.Steps.Clear;
   B.Steps.Clear;
   A.Steps.Append (S1);
   B.Steps.Append (S2);
   Check (Same (N.Normalize (A), N.Normalize (B)), "grouping/order");

   --  Non-ignored fields are never dropped; ignored ones are inventoried.
   S1 := (others => <>);
   Put (S1, O.F_Status_Players_Max, "20");
   S1.Fields.Include ("status.mystery", "42");
   O.Add_Unlisted (S1, "status.favicon", "string:100");
   O.Add_Unlisted (S1, "status.other", "object:3");
   A.Steps.Clear;
   A.Steps.Append (S1);
   R := N.Normalize (A);
   Check (not R.Steps (1).Fields.Contains ("status.mystery"),
          "unlisted not compared");
   Check (R.Steps (1).Unlisted.Contains ("status.mystery"),
          "unlisted kept");
   Check (R.Steps (1).Unlisted.Element ("status.mystery") (1 .. 9)
          = "unlisted:", "unlisted tag");
   Check (R.Steps (1).Unlisted.Element ("status.favicon") (1 .. 8)
          = "ignored:", "ignored tag");
   Check (R.Steps (1).Unlisted.Element ("status.other") (1 .. 9)
          = "unlisted:", "other unlisted tag");
   Check (R.Steps (1).Fields.Contains (O.F_Status_Players_Max),
          "compared kept");

   --  Idempotent.
   Check (Same (R, N.Normalize (R)), "idempotent");

   if Failures = 0 then
      Ada.Text_IO.Put_Line ("test_diff_normalize: ok");
   else
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
   end if;
end Test_Diff_Normalize;
