with Ada.Command_Line;
with Ada.Environment_Variables;
with Ada.Strings.Fixed;
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

--  adacraft-diff: lab-only CLI. Exit codes: 0 all match, 1 mismatch,
--  2 infrastructure/prerequisite failure (precedence 2 > 1 > 0).
procedure Differential.Main is
   package SU renames Ada.Strings.Unbounded;
   package CL renames Ada.Command_Line;
   package R renames Differential.Report;
   package T renames Differential.Target;
   package OS renames GNAT.OS_Lib;
   use type T.Run_Category;
   use type OS.String_Access;

   Corpus_Dir : SU.Unbounded_String :=
     SU.To_Unbounded_String ("tests/corpus");
   Jar        : SU.Unbounded_String;
   Java       : SU.Unbounded_String := SU.To_Unbounded_String ("java");
   Report_Out : SU.Unbounded_String;
   Step_Wait  : constant Duration := 30.0;

   function Env (Name : String) return String is
     (if Ada.Environment_Variables.Exists (Name)
      then Ada.Environment_Variables.Value (Name) else "");

   --  The single place where exit-code precedence is applied.
   function Exit_Code (Tally : R.Tally) return Natural is
     (if Tally.Infrastructure > 0 then 2
      elsif Tally.Mismatched > 0 then 1
      else 0);

   procedure Finish (Code : Natural) is
   begin
      CL.Set_Exit_Status (CL.Exit_Status (Code));
   end Finish;

   function Capture (Prog : String; Args : OS.Argument_List) return String is
      Out_File : constant String := "obj/diff-capture.txt";
      Ok       : Boolean;
      Code     : Integer;
      F        : Ada.Text_IO.File_Type;
   begin
      OS.Spawn (Prog, Args, Out_File, Ok, Code, True);
      Ada.Text_IO.Open (F, Ada.Text_IO.In_File, Out_File);
      declare
         L : constant String :=
           (if Ada.Text_IO.End_Of_File (F) then ""
            else Ada.Text_IO.Get_Line (F));
      begin
         Ada.Text_IO.Close (F);
         return L;
      end;
   exception
      when others => return "unavailable";
   end Capture;

   function Java_Found return Boolean is
      J : constant String := SU.To_String (Java);
   begin
      if Ada.Strings.Fixed.Index (J, "/") > 0 then
         return OS.Is_Executable_File (J);
      end if;
      declare
         P : OS.String_Access := OS.Locate_Exec_On_Path (J);
      begin
         if P = null then
            return False;
         end if;
         OS.Free (P);
         return True;
      end;
   end Java_Found;

   function Sha256 (Path : String) return String is
      P : OS.String_Access := OS.Locate_Exec_On_Path ("sha256sum");
   begin
      if P = null then
         return "unavailable";
      end if;
      declare
         Args : OS.Argument_List := (1 => new String'(Path));
         Line : constant String := Capture (P.all, Args);
         Sp   : constant Natural := Ada.Strings.Fixed.Index (Line, " ");
      begin
         OS.Free (Args (1));
         OS.Free (P);
         return (if Sp > 1 then Line (Line'First .. Sp - 1) else Line);
      end;
   end Sha256;

   function Java_Version return String is
      Args : OS.Argument_List := (1 => new String'("-version"));
      V    : constant String := Capture (SU.To_String (Java), Args);
   begin
      OS.Free (Args (1));
      return V;
   end Java_Version;

   Projections : Differential.Scenario.Projection_Vectors.Vector;
   Load_Failed : Boolean;
   Results     : R.Result_Vectors.Vector;
   Prov        : R.Provenance;
begin
   --  Discovery: CLI option, then environment, else defaults.
   Jar := SU.To_Unbounded_String (Env ("ADACRAFT_SERVER_JAR"));
   if Env ("ADACRAFT_JAVA") /= "" then
      Java := SU.To_Unbounded_String (Env ("ADACRAFT_JAVA"));
   end if;
   declare
      I : Positive := 1;
   begin
      while I <= CL.Argument_Count loop
         declare
            A : constant String := CL.Argument (I);
         begin
            if I < CL.Argument_Count then
               if A = "--jar" then
                  Jar := SU.To_Unbounded_String (CL.Argument (I + 1));
                  I := I + 1;
               elsif A = "--java" then
                  Java := SU.To_Unbounded_String (CL.Argument (I + 1));
                  I := I + 1;
               elsif A = "--corpus" then
                  Corpus_Dir := SU.To_Unbounded_String (CL.Argument (I + 1));
                  I := I + 1;
               elsif A = "--report" then
                  Report_Out := SU.To_Unbounded_String (CL.Argument (I + 1));
                  I := I + 1;
               end if;
            end if;
         end;
         I := I + 1;
      end loop;
   end;

   if SU.Length (Jar) = 0 or else not OS.Is_Regular_File (SU.To_String (Jar))
   then
      Ada.Text_IO.Put_Line
        (Ada.Text_IO.Standard_Error,
         "infrastructure: server.jar not found (use --jar or "
         & "ADACRAFT_SERVER_JAR)");
      Finish (2);
      return;
   end if;
   if not Java_Found then
      Ada.Text_IO.Put_Line
        (Ada.Text_IO.Standard_Error,
         "infrastructure: java not found (use --java, ADACRAFT_JAVA, "
         & "or PATH)");
      Finish (2);
      return;
   end if;

   Differential.Scenario.Load
     (SU.To_String (Corpus_Dir), Projections, Load_Failed);
   if Load_Failed or else Projections.Is_Empty then
      Ada.Text_IO.Put_Line
        (Ada.Text_IO.Standard_Error,
         "infrastructure: corpus unreadable or empty");
      Finish (2);
      return;
   end if;

   for Proj of Projections loop
      declare
         Res : R.Scenario_Result;
      begin
         Res.Id := Proj.Id;
         if Proj.Failure /= Differential.Scenario.No_Failure then
            Res.Cat := R.Infrastructure;
            Res.Detail := Proj.Reason;
         else
            declare
               Oracle : Differential.Target.Oracle.Oracle_Target :=
                 (Cfg => (Java_Path => Java, Jar_Path => Jar,
                          others => <>));
               Ada_T  : Differential.Target.Adacraft.Adacraft_Target;
               O_Run  : constant T.Run_Result :=
                 T.Run_Scenario (Oracle, Proj, Step_Wait);
               A_Run  : constant T.Run_Result :=
                 T.Run_Scenario (Ada_T, Proj, Step_Wait);
            begin
               if O_Run.Category /= T.Completed then
                  Res.Cat := R.Infrastructure;
                  Res.Detail := O_Run.Detail;
               elsif A_Run.Category /= T.Completed then
                  Res.Cat := R.Mismatched;
                  Res.Detail := SU.To_Unbounded_String
                    ("adacraft produced no observation: ")
                    & A_Run.Detail;
               else
                  declare
                     NO : constant Differential.Obs.Observation :=
                       Differential.Normalize.Normalize (O_Run.Observation);
                     NA : constant Differential.Obs.Observation :=
                       Differential.Normalize.Normalize (A_Run.Observation);
                     Cmp : constant Differential.Compare.Result :=
                       Differential.Compare.Compare (NO, NA);
                  begin
                     Res.Cat :=
                       (if Cmp.Pass then R.Matched else R.Mismatched);
                     Res.Diffs := Cmp.Diffs;
                     for S of NO.Steps loop
                        for C in S.Unlisted.Iterate loop
                           Differential.Obs.Field_Maps.Include
                             (Res.Unlisted,
                              Differential.Obs.Field_Maps.Key (C),
                              Differential.Obs.Field_Maps.Element (C));
                        end loop;
                     end loop;
                  end;
               end if;
            end;
         end if;
         Results.Append (Res);
      end;
   end loop;

   Prov.Jar_Path := Jar;
   Prov.Jar_Sha256 := SU.To_Unbounded_String (Sha256 (SU.To_String (Jar)));
   Prov.Java_Version := SU.To_Unbounded_String (Java_Version);
   Prov.Observed_Protocol := SU.To_Unbounded_String ("777");
   Prov.Corpus_Id := Corpus_Dir;

   declare
      Json : constant String := R.Render_Json (Prov, Results);
   begin
      if SU.Length (Report_Out) > 0 then
         declare
            F : Ada.Text_IO.File_Type;
         begin
            Ada.Text_IO.Create
              (F, Ada.Text_IO.Out_File, SU.To_String (Report_Out));
            Ada.Text_IO.Put_Line (F, Json);
            Ada.Text_IO.Close (F);
         end;
      else
         Ada.Text_IO.Put_Line (Json);
      end if;
   end;
   Ada.Text_IO.Put_Line
     (Ada.Text_IO.Standard_Error, R.Render_Summary (Results));
   Finish (Exit_Code (R.Tally_Of (Results)));
end Differential.Main;
