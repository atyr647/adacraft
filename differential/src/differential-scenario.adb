with Adacraft.Corpus.Loader;

package body Differential.Scenario is
   use Ada.Strings.Unbounded;
   use type Ada.Containers.Count_Type;
   use type Corpus.Category;

   function Is_Supported (S : Corpus.Scenario) return Boolean is
     (S.Protocol_Version = 777
      and then S.Steps.Length > 0
      and then (S.Cat = Corpus.Handshake
                or else S.Cat = Corpus.Status
                or else S.Cat = Corpus.Login));

   function Project (S : Corpus.Scenario) return Projection is
      R   : Projection;
      Idx : Natural := 0;
   begin
      R.Id := S.Id;
      R.Cat := S.Cat;
      R.Initial_State := S.Initial_State;
      R.Has_Final_State := S.Has_Final_State;
      R.Final_State := S.Final_State;
      if not Is_Supported (S) then
         R.Failure := Infrastructure_Failure;
         R.Reason := To_Unbounded_String
           ("unsupported scenario kind: category "
            & Corpus.Category'Image (S.Cat) & ", protocol"
            & Natural'Image (S.Protocol_Version) & ", steps"
            & Ada.Containers.Count_Type'Image (S.Steps.Length));
         return R;
      end if;
      for St of S.Steps loop
         Idx := Idx + 1;
         R.Actions.Append
           (Action'(Index           => Idx,
                    Dir             => St.Dir,
                    Frame           => St.Input,
                    Expected        => St.Expected,
                    Has_Packet_Id   => St.Has_Packet_Id,
                    Packet_Id       => St.Packet_Id,
                    Has_State_After => St.Has_State_After,
                    State_After     => St.State_After,
                    Timeout         => Default_Step_Timeout));
      end loop;
      return R;
   end Project;

   procedure Load
     (Dir         : String;
      Projections : out Projection_Vectors.Vector;
      Load_Failed : out Boolean)
   is
      Scenarios : Corpus.Scenario_Vectors.Vector;
      Errors    : Corpus.Error_Vectors.Vector;
   begin
      Projections.Clear;
      Adacraft.Corpus.Loader.Load (Dir, Scenarios, Errors);
      Load_Failed := Errors.Length > 0;
      for S of Scenarios loop
         Projections.Append (Project (S));
      end loop;
   end Load;

   function Exit_Code (F : Failure_Category) return Natural is
     (case F is when No_Failure => 0, when Infrastructure_Failure => 2);

end Differential.Scenario;
