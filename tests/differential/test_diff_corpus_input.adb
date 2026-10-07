with Ada.Command_Line;
with Ada.Containers;
with Ada.Strings.Unbounded;
with Ada.Text_IO;
with Adacraft.Corpus;
with Adacraft.Corpus.Loader;
with Differential.Scenario;

--  DR-2: every checked-in corpus scenario projects unchanged; unsupported
--  kinds map to the infrastructure-failure category. Run from repo root.
procedure Test_Diff_Corpus_Input is
   package C renames Adacraft.Corpus;
   package D renames Differential.Scenario;
   use type Ada.Containers.Count_Type;
   use type Ada.Strings.Unbounded.Unbounded_String;
   use type C.Direction;
   use type C.Outcome;
   use type C.Byte_Vectors.Vector;
   use type D.Failure_Category;
   use type D.PS.Connection_State;

   Failures : Natural := 0;

   procedure Check (Cond : Boolean; Name : String) is
   begin
      if not Cond then
         Ada.Text_IO.Put_Line ("FAIL " & Name);
         Failures := Failures + 1;
      end if;
   end Check;

   Scenarios : C.Scenario_Vectors.Vector;
   Errors    : C.Error_Vectors.Vector;
   Projs     : D.Projection_Vectors.Vector;
   Failed    : Boolean;
begin
   C.Loader.Load ("tests/corpus", Scenarios, Errors);
   Check (Errors.Length = 0, "corpus loads without errors");
   Check (Scenarios.Length > 0, "corpus is not empty");

   for S of Scenarios loop
      declare
         Name : constant String := Ada.Strings.Unbounded.To_String (S.Id);
         P    : constant D.Projection := D.Project (S);
         I    : Natural := 0;
      begin
         Check (P.Failure = D.No_Failure, Name & " supported");
         Check (P.Id = S.Id, Name & " id");
         Check (P.Initial_State = S.Initial_State, Name & " initial state");
         Check (P.Has_Final_State = S.Has_Final_State, Name & " final flag");
         Check (P.Actions.Length = S.Steps.Length, Name & " step count");
         if P.Actions.Length = S.Steps.Length then
            for St of S.Steps loop
               I := I + 1;
               declare
                  A : constant D.Action := P.Actions (I);
               begin
                  Check (A.Frame = St.Input, Name & " bytes" & I'Image);
                  Check (A.Dir = St.Dir, Name & " dir" & I'Image);
                  Check (A.Expected = St.Expected, Name & " outcome" & I'Image);
                  Check (A.Has_Packet_Id = St.Has_Packet_Id
                         and then A.Packet_Id = St.Packet_Id,
                         Name & " packet id" & I'Image);
                  Check (A.Has_State_After = St.Has_State_After,
                         Name & " state_after flag" & I'Image);
                  Check (A.Timeout = D.Default_Step_Timeout,
                         Name & " default timeout" & I'Image);
               end;
            end loop;
         end if;
      end;
   end loop;

   D.Load ("tests/corpus", Projs, Failed);
   Check (not Failed, "adapter load clean");
   Check (Projs.Length = Scenarios.Length, "adapter projects all scenarios");

   declare
      Base : constant C.Scenario := Scenarios.First_Element;
      Bad  : C.Scenario := Base;
      P    : D.Projection;
   begin
      Bad.Cat := C.Play;
      P := D.Project (Bad);
      Check (P.Failure = D.Infrastructure_Failure,
             "unsupported category is infrastructure failure");
      Check (D.Exit_Code (P.Failure) = 2, "infrastructure failure exits 2");
      Check (P.Actions.Length = 0, "no invented actions for unsupported");

      Bad := Base;
      Bad.Protocol_Version := 778;
      Check (D.Project (Bad).Failure = D.Infrastructure_Failure,
             "wrong protocol is infrastructure failure");

      Bad := Base;
      Bad.Steps.Clear;
      Check (D.Project (Bad).Failure = D.Infrastructure_Failure,
             "scenario without steps is infrastructure failure");
      Check (D.Exit_Code (D.No_Failure) = 0, "no failure exits 0");
   end;

   if Failures > 0 then
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
   end if;
end Test_Diff_Corpus_Input;
