with Ada.Command_Line;
with Ada.Strings.Fixed;
with Ada.Text_IO;

procedure Differential_Main is

   package D_Defs is
      --  Transcript types for semantic comparison.
      --  Payload bytes are consumed for framing but never stored/compared.

      type Outcome is
        (Closed_By_Peer, Still_Open_At_End, Timeout, Connect_Failed,
         Malformed_Input);

      type Direction is (S2C);

      Max_Entries  : constant := 1024;
      Max_Name_Len : constant := 512;

      type Entry is record
         State : Natural := 0;
         Dir   : Direction := S2C;
         Id    : Natural := 0;
      end record;

      type Entries_Storage is array (1 .. Max_Entries) of Entry;

      type Name_Storage is String (1 .. Max_Name_Len);

      type Transcript is record
         Count    : Natural range 0 .. Max_Entries := 0;
         Entries  : Entries_Storage :=
           (others => (State => 0, Dir => S2C, Id => 0));
         Result   : Outcome := Still_Open_At_End;
         Name_Len : Natural range 0 .. Max_Name_Len := 0;
         Name     : Name_Storage := (others => ' ');
      end record;

      function Scenario_Name (T : Transcript) return String;
      procedure Set_Scenario_Name (T : in out Transcript; S : String);
      procedure Append (T : in out Transcript; E : Entry; Full : out Boolean);
      function Get (T : Transcript; Index : Positive) return Entry;
   end D_Defs;

   package body D_Defs is
      function Scenario_Name (T : Transcript) return String is
      begin
         if T.Name_Len = 0 then
            return "";
         end if;
         return T.Name (1 .. T.Name_Len);
      end Scenario_Name;

      procedure Set_Scenario_Name (T : in out Transcript; S : String) is
         N : constant Natural := Natural'Min (S'Length, Max_Name_Len);
      begin
         T.Name := (others => ' ');
         T.Name_Len := N;
         if N > 0 then
            declare
               J : Positive := 1;
            begin
               for I in S'Range loop
                  exit when J > N;
                  T.Name (J) := S (I);
                  J := J + 1;
               end loop;
            end;
         end if;
      end Set_Scenario_Name;

      procedure Append (T : in out Transcript; E : Entry; Full : out Boolean) is
      begin
         if T.Count >= Max_Entries then
            Full := True;
            return;
         end if;
         Full := False;
         T.Count := T.Count + 1;
         T.Entries (T.Count) := E;
      end Append;

      function Get (T : Transcript; Index : Positive) return Entry is
      begin
         if Index < 1 or else Index > T.Count then
            raise Constraint_Error;
         end if;
         return T.Entries (Index);
      end Get;
   end D_Defs;

   package D_Compare is
      --  Pure semantic comparison: Entry sequence (State, Dir, Id) plus
      --  terminal Outcome only. Payload is never stored so it cannot affect
      --  the result. No side effects, no I/O, no exceptions on valid input.
      function Equal (A, B : D_Defs.Transcript) return Boolean;
      function First_Divergence_Index
        (A, B : D_Defs.Transcript) return Natural;
      --  0 means equal (same as Equal = True).
      --  Otherwise 1-based index of first differing Entry; when Entries are
      --  equal up to Min (Count) but Counts differ, returns Min + 1; when
      --  Entries (including Count) are equal but Outcomes differ,
      --  returns Count + 1.
   end D_Compare;

   package body D_Compare is
      function Entries_Equal (A, B : D_Defs.Transcript) return Boolean is
      begin
         if A.Count /= B.Count then
            return False;
         end if;
         for I in 1 .. A.Count loop
            declare
               EA : constant D_Defs.Entry := A.Entries (I);
               EB : constant D_Defs.Entry := B.Entries (I);
            begin
               if EA.State /= EB.State or else EA.Dir /= EB.Dir
                 or else EA.Id /= EB.Id
               then
                  return False;
               end if;
            end;
         end loop;
         return True;
      end Entries_Equal;

      function Equal (A, B : D_Defs.Transcript) return Boolean is
      begin
         return A.Result = B.Result and then Entries_Equal (A, B);
      end Equal;

      function First_Divergence_Index
        (A, B : D_Defs.Transcript) return Natural
      is
         Min_Count : constant Natural := Natural'Min (A.Count, B.Count);
      begin
         for I in 1 .. Min_Count loop
            declare
               EA : constant D_Defs.Entry := A.Entries (I);
               EB : constant D_Defs.Entry := B.Entries (I);
            begin
               if EA.State /= EB.State or else EA.Dir /= EB.Dir
                 or else EA.Id /= EB.Id
               then
                  return I;
               end if;
            end;
         end loop;
         if A.Count /= B.Count then
            return Min_Count + 1;
         end if;
         if A.Result /= B.Result then
            return A.Count + 1;
         end if;
         return 0;
      end First_Divergence_Index;
   end D_Compare;

   package D_Args is
      Read_Timeout_Secs     : Natural := 5;
      Scenario_Timeout_Secs : Natural := 30;
      Selftest              : Boolean := False;
      Oracle_Host           : String (1 .. 256) := (others => ' ');
      Oracle_Host_Len       : Natural := 0;
      Oracle_Port           : Natural := 0;
      Oracle_Set            : Boolean := False;
      Cand_Host             : String (1 .. 256) := (others => ' ');
      Cand_Host_Len         : Natural := 0;
      Cand_Port             : Natural := 0;
      Cand_Set              : Boolean := False;
      Scenario_Count        : Natural := 0;

      procedure Parse;
      function Oracle_Image return String;
      function Candidate_Image return String;
      function Scenario (Index : Positive) return String;
   end D_Args;

   package body D_Args is
      Max_Scenarios : constant := 64;
      Scenarios     : array (1 .. Max_Scenarios) of String (1 .. 512) :=
        (others => (others => ' '));
      Scenario_Lens : array (1 .. Max_Scenarios) of Natural := (others => 0);

      procedure Fail (Msg : String) is
      begin
         Ada.Text_IO.Put_Line (Ada.Text_IO.Standard_Error, "differential: " & Msg);
         Ada.Text_IO.Put_Line
           (Ada.Text_IO.Standard_Error,
            "usage: differential-main --oracle H:P --candidate H:P " &
            "[--read-timeout S] [--scenario-timeout S] [--selftest] <scenario>...");
         Ada.Command_Line.Set_Exit_Status (2);
      end Fail;

      procedure Split_Host_Port (Value : String) is
         Sep : Natural;
      begin
         Sep := Ada.Strings.Fixed.Index (Value, ":", Ada.Strings.Backward);
         if Sep = 0 or else Sep = Value'First or else Sep = Value'Last then
            raise Constraint_Error;
         end if;
         declare
            H : constant String := Value (Value'First .. Sep - 1);
            P : constant String := Value (Sep + 1 .. Value'Last);
         begin
            if Oracle_Set and then not Cand_Set then
               if H'Length > Cand_Host'Length then
                  raise Constraint_Error;
               end if;
               Cand_Host (1 .. H'Length) := H;
               Cand_Host_Len := H'Length;
               Cand_Port := Natural'Value (P);
               Cand_Set := True;
            elsif not Oracle_Set then
               if H'Length > Oracle_Host'Length then
                  raise Constraint_Error;
               end if;
               Oracle_Host (1 .. H'Length) := H;
               Oracle_Host_Len := H'Length;
               Oracle_Port := Natural'Value (P);
               Oracle_Set := True;
            end if;
            if Cand_Port > 65_535 or else Oracle_Port > 65_535 then
               raise Constraint_Error;
            end if;
         end;
      end Split_Host_Port;

      function Oracle_Image return String is
      begin
         if Oracle_Host_Len = 0 then
            return "";
         end if;
         return Oracle_Host (1 .. Oracle_Host_Len);
      end Oracle_Image;

      function Candidate_Image return String is
      begin
         if Cand_Host_Len = 0 then
            return "";
         end if;
         return Cand_Host (1 .. Cand_Host_Len);
      end Candidate_Image;

      function Scenario (Index : Positive) return String is
      begin
         if Index > Scenario_Count then
            return "";
         end if;
         return Scenarios (Index) (1 .. Scenario_Lens (Index));
      end Scenario;

      procedure Parse is
         use Ada.Command_Line;
         I              : Positive := 1;
         Expect_Oracle  : Boolean := False;
         Expect_Cand    : Boolean := False;
         Expect_Read    : Boolean := False;
         Expect_Scen    : Boolean := False;
      begin
         while I <= Argument_Count loop
            declare
               A : constant String := Argument (I);
            begin
               if Expect_Oracle then
                  begin
                     Oracle_Set := False;
                     declare
                        Save_O : constant Boolean := Cand_Set;
                     begin
                        Cand_Set := True;
                        Split_Host_Port (A);
                        Cand_Set := Save_O;
                        Oracle_Set := True;
                        --  Split wrote to oracle slot because Oracle_Set was False
                        --  on entry; re-split correctly by moving last parse:
                        null;
                     end;
                  exception
                     when others =>
                        Fail ("bad --oracle value '" & A & "'");
                        return;
                  end;
                  --  Above helper splits by slot state; redo simply:
                  Oracle_Set := False;
                  declare
                     Tmp_C_Set : constant Boolean := Cand_Set;
                     Tmp_C_H   : String (1 .. 256) := Cand_Host;
                     Tmp_C_L   : constant Natural := Cand_Host_Len;
                     Tmp_C_P   : constant Natural := Cand_Port;
                  begin
                     Split_Host_Port (A);
                     --  Split wrote into oracle slot; but if candidate was
                     --  already set it wrote into candidate slot, so restore
                     --  candidate when it was set before.
                     if Tmp_C_Set and then Cand_Set then
                        --  Ambiguous; keep oracle from this parse: the value
                        --  just parsed landed in candidate slot, move it.
                        Oracle_Host (1 .. Cand_Host_Len) := Cand_Host (1 .. Cand_Host_Len);
                        Oracle_Host_Len := Cand_Host_Len;
                        Oracle_Port := Cand_Port;
                        Cand_Host := Tmp_C_H;
                        Cand_Host_Len := Tmp_C_L;
                        Cand_Port := Tmp_C_P;
                     end if;
                     Oracle_Set := True;
                  exception
                     when others =>
                        Cand_Host := Tmp_C_H;
                        Cand_Host_Len := Tmp_C_L;
                        Cand_Port := Tmp_C_P;
                        Fail ("bad --oracle value '" & A & "'");
                        return;
                  end;
                  Expect_Oracle := False;
               elsif Expect_Cand then
                  begin
                     if not Oracle_Set then
                        --  Force write to candidate slot.
                        Oracle_Set := True;
                        Split_Host_Port (A);
                        --  Landed in candidate slot only if oracle set; move back
                        Cand_Host (1 .. Oracle_Host_Len) := Oracle_Host (1 .. Oracle_Host_Len);
                        Cand_Host_Len := Oracle_Host_Len;
                        Cand_Port := Oracle_Port;
                        Oracle_Set := False;
                        Oracle_Host_Len := 0;
                        Oracle_Port := 0;
                        Cand_Set := True;
                     else
                        Split_Host_Port (A);
                     end if;
                  exception
                     when others =>
                        Fail ("bad --candidate value '" & A & "'");
                        return;
                  end;
                  Expect_Cand := False;
               elsif Expect_Read then
                  begin
                     Read_Timeout_Secs := Natural'Value (A);
                  exception
                     when others =>
                        Fail ("bad --read-timeout value '" & A & "'");
                        return;
                  end;
                  Expect_Read := False;
               elsif Expect_Scen then
                  begin
                     Scenario_Timeout_Secs := Natural'Value (A);
                  exception
                     when others =>
                        Fail ("bad --scenario-timeout value '" & A & "'");
                        return;
                  end;
                  Expect_Scen := False;
               elsif A = "--oracle" then
                  Expect_Oracle := True;
               elsif A = "--candidate" then
                  Expect_Cand := True;
               elsif A = "--read-timeout" then
                  Expect_Read := True;
               elsif A = "--scenario-timeout" then
                  Expect_Scen := True;
               elsif A = "--selftest" then
                  Selftest := True;
               elsif A'Length > 0 and then A (A'First) = '-' then
                  Fail ("unknown option '" & A & "'");
                  return;
               else
                  if Scenario_Count >= Max_Scenarios then
                     Fail ("too many scenarios");
                     return;
                  end if;
                  if A'Length > 512 then
                     Fail ("scenario path too long");
                     return;
                  end if;
                  Scenario_Count := Scenario_Count + 1;
                  Scenarios (Scenario_Count) (1 .. A'Length) := A;
                  Scenario_Lens (Scenario_Count) := A'Length;
               end if;
            end;
            I := I + 1;
         end loop;

         if Expect_Oracle or else Expect_Cand or else Expect_Read or else Expect_Scen then
            Fail ("missing option value");
            return;
         end if;
         if not Oracle_Set then
            Fail ("missing --oracle H:P");
            return;
         end if;
         if not Cand_Set then
            Fail ("missing --candidate H:P");
            return;
         end if;
         if not Selftest and then Scenario_Count = 0 then
            Fail ("no scenario given");
            return;
         end if;
      end Parse;
   end D_Args;

begin
   D_Args.Parse;
   if Ada.Command_Line.Exit_Status /= Ada.Command_Line.Success then
      return;
   end if;
   Ada.Text_IO.Put_Line
     ("oracle=" & D_Args.Oracle_Image & ":" &
      Ada.Strings.Fixed.Trim (Natural'Image (D_Args.Oracle_Port), Ada.Strings.Both) &
      " candidate=" & D_Args.Candidate_Image & ":" &
      Ada.Strings.Fixed.Trim (Natural'Image (D_Args.Cand_Port), Ada.Strings.Both) &
      " read-timeout=" &
      Ada.Strings.Fixed.Trim (Natural'Image (D_Args.Read_Timeout_Secs), Ada.Strings.Both) &
      " scenario-timeout=" &
      Ada.Strings.Fixed.Trim (Natural'Image (D_Args.Scenario_Timeout_Secs), Ada.Strings.Both) &
      " scenarios=" &
      Ada.Strings.Fixed.Trim (Natural'Image (D_Args.Scenario_Count), Ada.Strings.Both));
   Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Success);
end Differential_Main;
