with Adacraft.Protocol.State;

package body Differential.Compare is

   package O renames Differential.Obs;
   package SU renames Ada.Strings.Unbounded;
   use type Ada.Containers.Count_Type;
   use type O.Outcome;
   use type Adacraft.Protocol.State.Connection_State;

   function Image (K : Diff_Kind) return String is
     (case K is
         when State_Differs   => "state_differs",
         when Outcome_Differs => "outcome_differs",
         when Value_Differs   => "value_differs",
         when Field_Missing   => "field_missing",
         when Field_Extra     => "field_extra",
         when Step_Missing    => "step_missing",
         when Step_Extra      => "step_extra");

   procedure Add
     (R    : in out Result;
      Step : Positive;
      Kind : Diff_Kind;
      Path : String;
      Ov   : String;
      Av   : String) is
   begin
      R.Pass := False;
      R.Diffs.Append
        ((Step           => Step,
          Kind           => Kind,
          Path           => SU.To_Unbounded_String (Path),
          Oracle_Value   => SU.To_Unbounded_String (Ov),
          Adacraft_Value => SU.To_Unbounded_String (Av)));
   end Add;

   procedure Compare_Step
     (R    : in out Result;
      Step : Positive;
      Ob   : O.Step_Observation;
      Ad   : O.Step_Observation) is
   begin
      --  State first.
      if Ob.State /= Ad.State then
         Add (R, Step, State_Differs, "state",
              Adacraft.Protocol.State.Connection_State'Image (Ob.State),
              Adacraft.Protocol.State.Connection_State'Image (Ad.State));
      end if;

      if Ob.Result /= Ad.Result then
         Add (R, Step, Outcome_Differs, "outcome",
              O.Image (Ob.Result), O.Image (Ad.Result));
      end if;

      --  Compared fields only; Unlisted is never compared.
      for C in Ob.Fields.Iterate loop
         declare
            Name : constant String := O.Field_Maps.Key (C);
         begin
            if O.Is_Compared_Field (Name) then
               if Ad.Fields.Contains (Name) then
                  if O.Field_Maps.Element (C) /= Ad.Fields.Element (Name)
                  then
                     Add (R, Step, Value_Differs, Name,
                          O.Field_Maps.Element (C),
                          Ad.Fields.Element (Name));
                  end if;
               else
                  Add (R, Step, Field_Missing, Name,
                       O.Field_Maps.Element (C), Absent);
               end if;
            end if;
         end;
      end loop;

      for C in Ad.Fields.Iterate loop
         declare
            Name : constant String := O.Field_Maps.Key (C);
         begin
            if O.Is_Compared_Field (Name)
              and then not Ob.Fields.Contains (Name)
            then
               Add (R, Step, Field_Extra, Name,
                    Absent, O.Field_Maps.Element (C));
            end if;
         end;
      end loop;
   end Compare_Step;

   function Compare
     (Oracle   : Differential.Obs.Observation;
      Adacraft : Differential.Obs.Observation) return Result
   is
      R  : Result;
      No : constant Natural := Natural (Oracle.Steps.Length);
      Na : constant Natural := Natural (Adacraft.Steps.Length);
   begin
      for I in 1 .. Natural'Min (No, Na) loop
         Compare_Step (R, I, Oracle.Steps (I), Adacraft.Steps (I));
      end loop;
      for I in Na + 1 .. No loop
         Add (R, I, Step_Missing, "step",
              O.Image (Oracle.Steps (I).Result), Absent);
      end loop;
      for I in No + 1 .. Na loop
         Add (R, I, Step_Extra, "step",
              Absent, O.Image (Adacraft.Steps (I).Result));
      end loop;
      return R;
   end Compare;

end Differential.Compare;
