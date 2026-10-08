with Ada.Command_Line;
with Ada.Exceptions;
with Ada.Strings.Unbounded;
with Ada.Text_IO;
with Differential.Args;
with Differential.Capture;
with Differential.Compare;
with Differential.Report;
with Differential.Selftest;
with Differential.Transcript;

procedure Differential.Main is
   use Ada.Strings.Unbounded;

   function All_Match
     (Scenarios : Differential.Report.Scenario_Result_Vectors.Vector)
      return Boolean
   is
   begin
      for Item of Scenarios loop
         if not Item.Verdict.Is_Match then
            return False;
         end if;
      end loop;
      return True;
   end All_Match;

begin
   declare
      Options : constant Differential.Args.Options :=
        Differential.Args.Parse;
   begin
      if Options.Selftest then
         Differential.Selftest.Check;
         if Differential.Selftest.Base_Result then
            Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Success);
         else
            Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
         end if;
      else
         --  Empty_Provider has no scenarios yet; the corpus loader is deferred.
         declare
            Scenarios : Differential.Report.Scenario_Result_Vectors.Vector;
         begin
            Ada.Text_IO.Put_Line
              (Differential.Report.Format (Scenarios));
            if All_Match (Scenarios) then
               Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Success);
            else
               Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
            end if;
         end;
      end if;
   end;
exception
   when Differential.Args.Usage_Error =>
      Ada.Command_Line.Set_Exit_Status (2);
   when E : Differential.Capture.Setup_Error =>
      Ada.Text_IO.Put_Line
        (Ada.Text_IO.Standard_Error,
         "Setup error: " & Ada.Exceptions.Exception_Message (E));
      Ada.Command_Line.Set_Exit_Status (2);
   when E : others =>
      Ada.Text_IO.Put_Line
        (Ada.Text_IO.Standard_Error,
         "Setup error: " & Ada.Exceptions.Exception_Message (E));
      Ada.Command_Line.Set_Exit_Status (2);
end Differential.Main;
