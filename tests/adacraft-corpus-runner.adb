with Ada.Strings.Unbounded;
with Ada.Text_IO;

package body Adacraft.Corpus.Runner is

   use Ada.Strings.Unbounded;

   procedure Init_Dispatch (D : out Dispatch_Session) is
   begin
      D := (others => <>);
   end Init_Dispatch;

   procedure Replay (S : Scenario; Failure : out Unbounded_String) is
      D : Dispatch_Session;
   begin
      Init_Dispatch (D);
      D.Proto_State := S.Initial_State;
      Failure := To_Unbounded_String
        ("gap: no server dispatch entry returning framed bytes");
   end Replay;

   procedure Run_All
     (Scenarios : Scenario_Vectors.Vector;
      F : Filter;
      Summary : out Run_Summary)
   is
      Failure : Unbounded_String;
   begin
      Summary := (others => <>);
      for S of Scenarios loop
         if (not F.Has_Id or else S.Id = F.Id)
           and then (not F.Has_Category or else S.Cat = F.Cat)
         then
            Summary.Total := Summary.Total + 1;
            Summary.Per (S.Cat) := Summary.Per (S.Cat) + 1;
            Replay (S, Failure);
            if Length (Failure) = 0 then
               Summary.Passed := Summary.Passed + 1;
            else
               Summary.Failed := Summary.Failed + 1;
               Ada.Text_IO.Put_Line
                 ("FAIL scenario=" & To_String (S.Id)
                  & " file=" & To_String (S.Path)
                  & " " & To_String (Failure));
            end if;
         end if;
      end loop;
      Ada.Text_IO.Put_Line
        ("golden corpus: scenarios="
         & Natural'Image (Summary.Total)
         & " passed=" & Natural'Image (Summary.Passed)
         & " failed=" & Natural'Image (Summary.Failed));
   end Run_All;

end Adacraft.Corpus.Runner;
