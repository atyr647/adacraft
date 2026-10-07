with Ada.Characters.Handling;
with Ada.Command_Line;
with Ada.Strings.Unbounded;
with Ada.Text_IO;
with Adacraft.Corpus;
with Adacraft.Corpus.Loader;
with Adacraft.Corpus.Runner;

procedure Test_Golden_Corpus is
   package C renames Adacraft.Corpus;
   package L renames Adacraft.Corpus.Loader;
   package R renames Adacraft.Corpus.Runner;
   use type Ada.Strings.Unbounded.Unbounded_String;

   Scenarios : C.Scenario_Vectors.Vector;
   Errors    : C.Error_Vectors.Vector;
   F         : R.Filter;
   Summary   : R.Run_Summary;
   Bad       : Boolean := False;
begin
   for I in 1 .. Ada.Command_Line.Argument_Count loop
      declare
         A : constant String := Ada.Command_Line.Argument (I);
      begin
         if A'Length > 11 and then A (A'First .. A'First + 10) = "--scenario=" then
            F.Has_Id := True;
            F.Id := Ada.Strings.Unbounded.To_Unbounded_String
              (A (A'First + 11 .. A'Last));
         elsif A'Length > 11 and then A (A'First .. A'First + 10) = "--category=" then
            declare
               V     : constant String := A (A'First + 11 .. A'Last);
               Found : Boolean := False;
            begin
               for Cat in C.Category loop
                  if Ada.Characters.Handling.To_Lower (C.Category'Image (Cat)) = V then
                     F.Has_Category := True;
                     F.Cat := Cat;
                     Found := True;
                  end if;
               end loop;
               if not Found then
                  Ada.Text_IO.Put_Line ("FAIL unknown category " & V);
                  Bad := True;
               end if;
            end;
         else
            Ada.Text_IO.Put_Line ("FAIL unknown argument " & A);
            Bad := True;
         end if;
      end;
   end loop;

   L.Load ("tests/corpus", Scenarios, Errors);
   for E of Errors loop
      Ada.Text_IO.Put_Line ("FAIL " & L.Format_Error (E));
      Bad := True;
   end loop;

   R.Run_All (Scenarios, F, Summary);
   if Summary.Total = 0 then
      Ada.Text_IO.Put_Line ("FAIL no scenarios selected");
      Bad := True;
   end if;
   if Summary.Failed > 0 then
      Bad := True;
   end if;

   if Bad then
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
   end if;
end Test_Golden_Corpus;
