with Ada.Environment_Variables;
with Ada.Strings.Unbounded;
with Ada.Text_IO;
with GNAT.OS_Lib;
with Differential.Compare;
with Differential.Normalize;
with Differential.Obs;
with Differential.Report;
with Differential.Scenario;
with Differential.Target.Adacraft;
with Differential.Target.Oracle;

--  Opt-in real-jar run. Skips (exit 0, reason printed) when
--  ADACRAFT_SERVER_JAR or Java is absent; otherwise runs the full pipeline
--  once on one scenario.
procedure Test_Diff_Integration is
   package SU renames Ada.Strings.Unbounded;
   package T renames Differential.Target;
   package OS renames GNAT.OS_Lib;
   use type T.Run_Category;
   use type OS.String_Access;

   Jar_Env : constant String := "ADACRAFT_SERVER_JAR";
   Java    : OS.String_Access := OS.Locate_Exec_On_Path ("java");
begin
   if not Ada.Environment_Variables.Exists (Jar_Env)
     or else Ada.Environment_Variables.Value (Jar_Env) = ""
   then
      Ada.Text_IO.Put_Line ("SKIP integration: ADACRAFT_SERVER_JAR not set");
      return;
   end if;
   if Java = null then
      Ada.Text_IO.Put_Line ("SKIP integration: java not found on PATH");
      return;
   end if;
   if not OS.Is_Regular_File (Ada.Environment_Variables.Value (Jar_Env)) then
      Ada.Text_IO.Put_Line ("SKIP integration: jar file not readable");
      return;
   end if;

   declare
      Projs  : Differential.Scenario.Projection_Vectors.Vector;
      Failed : Boolean;
   begin
      Differential.Scenario.Load ("tests/corpus", Projs, Failed);
      if Failed or else Projs.Is_Empty then
         Ada.Text_IO.Put_Line ("FAIL integration: corpus load");
         GNAT.OS_Lib.OS_Exit (1);
      end if;
      declare
         Chosen : Differential.Scenario.Projection := Projs.First_Element;
      begin
         for P of Projs loop
            if SU.To_String (P.Id) = "status-request" then
               Chosen := P;
            end if;
         end loop;
         declare
            Oracle : T.Oracle.Oracle_Target :=
              (Cfg => (Java_Path => SU.To_Unbounded_String (Java.all),
                       Jar_Path   => SU.To_Unbounded_String
                         (Ada.Environment_Variables.Value (Jar_Env)),
                       others     => <>));
            Ada_T  : T.Adacraft.Adacraft_Target;
            O_Run  : constant T.Run_Result :=
              T.Run_Scenario (Oracle, Chosen, 30.0);
            A_Run  : constant T.Run_Result :=
              T.Run_Scenario (Ada_T, Chosen, 30.0);
         begin
            if O_Run.Category /= T.Completed
              or else A_Run.Category /= T.Completed
            then
               Ada.Text_IO.Put_Line
                 ("FAIL integration: run incomplete: "
                  & SU.To_String (O_Run.Detail) & " / "
                  & SU.To_String (A_Run.Detail));
               GNAT.OS_Lib.OS_Exit (1);
            end if;
            declare
               Cmp : constant Differential.Compare.Result :=
                 Differential.Compare.Compare
                   (Differential.Normalize.Normalize (O_Run.Observation),
                    Differential.Normalize.Normalize (A_Run.Observation));
               Res : Differential.Report.Scenario_Result;
               Results : Differential.Report.Result_Vectors.Vector;
            begin
               Res.Id := Chosen.Id;
               Res.Cat := (if Cmp.Pass then Differential.Report.Matched
                           else Differential.Report.Mismatched);
               Res.Diffs := Cmp.Diffs;
               Results.Append (Res);
               declare
                  Json : constant String :=
                    Differential.Report.Render_Json (<>, Results);
               begin
                  if Json'Length = 0 then
                     Ada.Text_IO.Put_Line ("FAIL integration: empty report");
                     GNAT.OS_Lib.OS_Exit (1);
                  end if;
                  Ada.Text_IO.Put_Line (Json);
               end;
               Ada.Text_IO.Put_Line
                 ("integration pipeline ok (match="
                  & Boolean'Image (Cmp.Pass) & ")");
            end;
         end;
      end;
   end;
end Test_Diff_Integration;
