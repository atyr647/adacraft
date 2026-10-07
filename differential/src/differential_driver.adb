with Ada.Command_Line;
with Ada.Containers;
with Ada.Containers.Vectors;
with Ada.Strings.Unbounded;
with Ada.Text_IO;
with Differential.Compare;
with Differential.Corpus;
with Differential.Obs;
with Differential.Report;
with Differential.Runner;

procedure Differential_Driver is

   use Ada.Strings.Unbounded;
   use type Ada.Containers.Count_Type;
   use type Differential.Obs.Event_Kind;

   package Arg_Vectors is new Ada.Containers.Vectors
     (Positive, Unbounded_String);

   procedure Diag (Msg : String) is
   begin
      Ada.Text_IO.Put_Line (Ada.Text_IO.Standard_Error, "error: " & Msg);
   end Diag;

   procedure Parse_Endpoint
     (Text : String; Host : out Unbounded_String; Port : out Natural;
      Ok   : out Boolean)
   is
      Colon : Natural := 0;
      P     : Natural := 0;
   begin
      Host := Null_Unbounded_String;
      Port := 0;
      Ok := False;
      for I in reverse Text'Range loop
         if Text (I) = ':' then
            Colon := I;
            exit;
         end if;
      end loop;
      if Colon <= Text'First or else Colon = Text'Last
        or else Text'Last - Colon > 5
      then
         return;
      end if;
      for I in Colon + 1 .. Text'Last loop
         if Text (I) not in '0' .. '9' then
            return;
         end if;
         P := P * 10 + Character'Pos (Text (I)) - Character'Pos ('0');
      end loop;
      if P < 1 or else P > 65535 then
         return;
      end if;
      Host := To_Unbounded_String (Text (Text'First .. Colon - 1));
      Port := P;
      Ok := True;
   end Parse_Endpoint;

   procedure Run_CLI (Argv : Arg_Vectors.Vector; Exit_Code : out Natural) is
      Oracle_Text, Subject_Text, Scenario_Name, Corpus_Path :
        Unbounded_String;
      Have_Oracle, Have_Subject, Have_Scenario, Have_Path : Boolean := False;
      Timeout_Ms : Natural := 5000;
      I : Positive := 1;
      N : constant Natural := Natural (Argv.Length);

      function Arg (K : Positive) return String
      is (To_String (Argv.Element (K)));

      O_Host, S_Host : Unbounded_String;
      O_Port, S_Port : Natural;
      Ok : Boolean;
      Scenarios : Differential.Corpus.Scenario_Vectors.Vector;
      Errors    : Differential.Corpus.Error_Vectors.Vector;
      Passed, Differed, Errored : Natural := 0;
   begin
      Exit_Code := 2;

      while I <= N loop
         declare
            A : constant String := Arg (I);
         begin
            if A = "--oracle" or else A = "--subject"
              or else A = "--scenario" or else A = "--timeout-ms"
            then
               if I = N then
                  Diag ("missing value for " & A);
                  return;
               end if;
               declare
                  V : constant String := Arg (I + 1);
               begin
                  if A = "--oracle" then
                     if Have_Oracle then
                        Diag ("duplicate --oracle");
                        return;
                     end if;
                     Have_Oracle := True;
                     Oracle_Text := To_Unbounded_String (V);
                  elsif A = "--subject" then
                     if Have_Subject then
                        Diag ("duplicate --subject");
                        return;
                     end if;
                     Have_Subject := True;
                     Subject_Text := To_Unbounded_String (V);
                  elsif A = "--scenario" then
                     if Have_Scenario then
                        Diag ("duplicate --scenario");
                        return;
                     end if;
                     Have_Scenario := True;
                     Scenario_Name := To_Unbounded_String (V);
                  else
                     if V'Length = 0 or else V'Length > 9 then
                        Diag ("invalid --timeout-ms");
                        return;
                     end if;
                     Timeout_Ms := 0;
                     for C of V loop
                        if C not in '0' .. '9' then
                           Diag ("invalid --timeout-ms");
                           return;
                        end if;
                        Timeout_Ms := Timeout_Ms * 10
                          + Character'Pos (C) - Character'Pos ('0');
                     end loop;
                     if Timeout_Ms = 0 then
                        Diag ("invalid --timeout-ms");
                        return;
                     end if;
                  end if;
               end;
               I := I + 2;
            elsif A'Length > 0 and then A (A'First) = '-' then
               Diag ("unknown option " & A);
               return;
            else
               if Have_Path then
                  Diag ("more than one corpus path");
                  return;
               end if;
               Have_Path := True;
               Corpus_Path := To_Unbounded_String (A);
               I := I + 1;
            end if;
         end;
      end loop;

      if not Have_Oracle or else not Have_Subject or else not Have_Path then
         Diag ("usage: differential_driver --oracle HOST:PORT "
               & "--subject HOST:PORT [--scenario NAME] [--timeout-ms N] "
               & "CORPUS_PATH");
         return;
      end if;

      Parse_Endpoint (To_String (Oracle_Text), O_Host, O_Port, Ok);
      if not Ok then
         Diag ("invalid --oracle endpoint");
         return;
      end if;
      Parse_Endpoint (To_String (Subject_Text), S_Host, S_Port, Ok);
      if not Ok then
         Diag ("invalid --subject endpoint");
         return;
      end if;

      Differential.Corpus.Load (To_String (Corpus_Path), Scenarios, Errors);
      if Errors.Length > 0 then
         for E of Errors loop
            Diag (Differential.Corpus.Format_Error (E));
         end loop;
         return;
      end if;

      if Have_Scenario then
         declare
            Sel   : Differential.Corpus.Scenario_Vectors.Vector;
            Found : Boolean := False;
         begin
            for S of Scenarios loop
               if S.Name = Scenario_Name then
                  Sel.Append (S);
                  Found := True;
               end if;
            end loop;
            if not Found then
               Diag ("unknown scenario " & To_String (Scenario_Name));
               return;
            end if;
            Scenarios := Sel;
         end;
      end if;

      if Scenarios.Is_Empty then
         Diag ("no scenarios in corpus");
         return;
      end if;

      --  All validation done; sockets are opened only from here on.
      for S of Scenarios loop
         declare
            Name : constant String := To_String (S.Name);
            Orc, Sub : Differential.Compare.Sequence;
         begin
            begin
               Differential.Runner.Run
                 (To_String (O_Host), O_Port, Timeout_Ms, S, Orc);
               if Orc.Length = 1
                 and then Orc.First_Element.Kind
                          = Differential.Obs.Connect_Failed
               then
                  Differential.Report.Error
                    (Name, "oracle connect failed");
                  Errored := Errored + 1;
               else
                  Differential.Runner.Run
                    (To_String (S_Host), S_Port, Timeout_Ms, S, Sub);
                  if Differential.Compare.Equal (Orc, Sub) then
                     Differential.Report.Pass (Name);
                     Passed := Passed + 1;
                  else
                     Differential.Report.Diff (Name, Orc, Sub);
                     Differed := Differed + 1;
                  end if;
               end if;
            exception
               when Differential.Runner.Step_Encoding_Error =>
                  Differential.Report.Error (Name, "step cannot be encoded");
                  Errored := Errored + 1;
            end;
         end;
      end loop;

      Differential.Report.Summary (Passed, Differed, Errored);
      if Errored > 0 then
         Exit_Code := 2;
      elsif Differed > 0 then
         Exit_Code := 1;
      else
         Exit_Code := 0;
      end if;
   end Run_CLI;

   Argv : Arg_Vectors.Vector;
   Code : Natural;
begin
   for K in 1 .. Ada.Command_Line.Argument_Count loop
      Argv.Append (To_Unbounded_String (Ada.Command_Line.Argument (K)));
   end loop;
   Run_CLI (Argv, Code);
   Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Exit_Status (Code));
end Differential_Driver;
