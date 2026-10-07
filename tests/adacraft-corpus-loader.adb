with Ada.Characters.Handling;
with Ada.Containers;
with Ada.Directories;
with Ada.Streams;
with Ada.Streams.Stream_IO;
with Ada.Strings;
with Ada.Strings.Fixed;
with Interfaces;
with Adacraft.Protocol.State;

package body Adacraft.Corpus.Loader is
   use Ada.Strings.Unbounded;
   use type Ada.Containers.Count_Type;
   use type Ada.Directories.File_Size;
   package PS renames Adacraft.Protocol.State;

   function Trim (T : String) return String is
      F : Integer := T'First;
      L : Integer := T'Last;
      function WS (C : Character) return Boolean is
        (C = ' ' or else C = ASCII.HT or else C = ASCII.CR);
   begin
      while F <= L and then WS (T (F)) loop
         F := F + 1;
      end loop;
      while L >= F and then WS (T (L)) loop
         L := L - 1;
      end loop;
      return R : String (1 .. L - F + 1) do
         R := T (F .. L);
      end return;
   end Trim;

   function Less (Left, Right : Unbounded_String) return Boolean is
      A : constant String := To_String (Left);
      B : constant String := To_String (Right);
      N : constant Natural := Natural'Min (A'Length, B'Length);
   begin
      for I in 0 .. N - 1 loop
         declare
            CA : constant Natural := Character'Pos (A (A'First + I));
            CB : constant Natural := Character'Pos (B (B'First + I));
         begin
            if CA /= CB then
               return CA < CB;
            end if;
         end;
      end loop;
      return A'Length < B'Length;
   end Less;

   package Sorting is new Name_Vectors.Generic_Sorting ("<" => Less);

   function Discover (Dir : String) return Name_Vectors.Vector is
      Result : Name_Vectors.Vector;
      Search : Ada.Directories.Search_Type;
      Item   : Ada.Directories.Directory_Entry_Type;
      Prefix : constant String :=
        (if Dir'Length > 0 and then Dir (Dir'Last) = '/' then Dir else Dir & "/");
   begin
      Ada.Directories.Start_Search
        (Search, Dir, "*.scenario",
         Ada.Directories.Filter_Type'(Ada.Directories.Ordinary_File => True,
                                       others => False));
      while Ada.Directories.More_Entries (Search) loop
         Ada.Directories.Get_Next_Entry (Search, Item);
         declare
            Name : constant String := Ada.Directories.Simple_Name (Item);
         begin
            if Name'Length > 9
              and then Name (Name'Last - 8 .. Name'Last) = ".scenario"
              and then Name (Name'First) /= '_'
            then
               Result.Append (To_Unbounded_String (Prefix & Name));
            end if;
         end;
      end loop;
      Ada.Directories.End_Search (Search);
      Sorting.Sort (Result);
      return Result;
   end Discover;

   generic
      type E is (<>);
   procedure Parse_Enum (Value : String; Result : out E; Ok : out Boolean);

   procedure Parse_Enum (Value : String; Result : out E; Ok : out Boolean) is
   begin
      Result := E'First;
      Ok := False;
      for X in E loop
         if Ada.Characters.Handling.To_Lower (E'Image (X)) = Value then
            Result := X;
            Ok := True;
            return;
         end if;
      end loop;
   end Parse_Enum;

   procedure Parse_Category is new Parse_Enum (Category);
   procedure Parse_Provenance is new Parse_Enum (Provenance);
   procedure Parse_Direction is new Parse_Enum (Direction);
   procedure Parse_Outcome is new Parse_Enum (Outcome);

   procedure Parse_State
     (Value : String; Result : out PS.Connection_State; Ok : out Boolean) is
   begin
      Result := PS.Handshake;
      Ok := False;
      for X in PS.Parent_State loop
         if PS.Connection_State'Image (X) = Value then
            Result := X;
            Ok := True;
            return;
         end if;
      end loop;
   end Parse_State;

   function Digit (C : Character) return Integer is
   begin
      case C is
         when '0' .. '9' => return Character'Pos (C) - Character'Pos ('0');
         when 'a' .. 'f' => return Character'Pos (C) - Character'Pos ('a') + 10;
         when 'A' .. 'F' => return Character'Pos (C) - Character'Pos ('A') + 10;
         when others     => return -1;
      end case;
   end Digit;

   procedure Parse_Nat
     (Value : String; Base : Positive; N : out Natural; Ok : out Boolean)
   is
      V : Integer;
   begin
      N := 0;
      Ok := Value'Length > 0 and then Value'Length <= 7;
      if not Ok then
         return;
      end if;
      for C of Value loop
         V := Digit (C);
         if V < 0 or else V >= Base then
            Ok := False;
            N := 0;
            return;
         end if;
         N := N * Base + V;
      end loop;
   end Parse_Nat;

   function Format_Error (E : Error) return String is
   begin
      return To_String (E.Path) & ":"
        & Ada.Strings.Fixed.Trim (Natural'Image (E.Line), Ada.Strings.Left)
        & ": " & To_String (E.Reason);
   end Format_Error;

   function Parse
     (Text   : String;
      Path   : String;
      S      : out Scenario;
      Errors : in out Error_Vectors.Vector) return Boolean
   is
      Start      : constant Ada.Containers.Count_Type := Errors.Length;
      Seen_Top   : Unbounded_String;
      Seen_Step  : Unbounded_String;
      Seen_First : Boolean := False;
      In_Step    : Boolean := False;
      Have_Cur   : Boolean := False;
      Skip       : Boolean := False;
      Out_Ok     : Boolean := False;
      Prov_Ok    : Boolean := False;
      Step_Count : Natural := 0;
      Cur        : Step;

      procedure Err (Line : Natural; Reason : String) is
      begin
         Errors.Append
           (Error'(Path   => To_Unbounded_String (Path),
                   Line   => Line,
                   Reason => To_Unbounded_String (Reason)));
      end Err;

      function Has (Set : Unbounded_String; Key : String) return Boolean is
        (Index (Set, " " & Key & " ") > 0);

      procedure Parse_Hex (Value : String; Dest : in out Byte_Vectors.Vector;
                           Line : Natural) is
         Count : Natural := 0;
         Hi    : Natural := 0;
         V     : Integer;
      begin
         Dest.Clear;
         for C of Value loop
            if C /= ' ' and then C /= ASCII.HT then
               V := Digit (C);
               if V < 0 then
                  Err (Line, "invalid hex digit '" & C & "' in input");
                  Dest.Clear;
                  return;
               end if;
               if Count mod 2 = 0 then
                  Hi := V;
               else
                  Dest.Append (Interfaces.Unsigned_8 (Hi * 16 + V));
               end if;
               Count := Count + 1;
            end if;
         end loop;
         if Count = 0 then
            Err (Line, "empty input");
         elsif Count mod 2 /= 0 then
            Err (Line, "odd number of hex digits in input");
            Dest.Clear;
         end if;
      end Parse_Hex;

      procedure Finish_Step is
      begin
         if not Has (Seen_Step, "direction") then
            Err (Cur.Line, "step missing required field direction");
         end if;
         if not Has (Seen_Step, "input") then
            Err (Cur.Line, "step missing required field input");
         end if;
         if not Has (Seen_Step, "outcome") then
            Err (Cur.Line, "step missing required field outcome");
         end if;
         if Out_Ok then
            if Cur.Expected = Accepted then
               if not Has (Seen_Step, "packet_id") then
                  Err (Cur.Line, "accepted step missing required field packet_id");
               end if;
               if not Has (Seen_Step, "state_after") then
                  Err (Cur.Line, "accepted step missing required field state_after");
               end if;
               if Cur.Has_Rejection_Category then
                  Err (Cur.Line,
                       "rejection_category only valid on rejected or incomplete steps");
               end if;
            else
               if Has (Seen_Step, "packet_id") then
                  Err (Cur.Line, "packet_id only valid on accepted steps");
               end if;
               if Has (Seen_Step, "state_after") then
                  Err (Cur.Line, "state_after only valid on accepted steps");
               end if;
               if Cur.Canonical then
                  Err (Cur.Line, "canonical only valid on accepted steps");
               end if;
            end if;
         end if;
         S.Steps.Append (Cur);
         Have_Cur := False;
      end Finish_Step;

      procedure Step_Field (Key, Value : String; Line : Natural) is
         Ok : Boolean;
         N  : Natural;
      begin
         if Key = "direction" then
            Parse_Direction (Value, Cur.Dir, Ok);
            if not Ok then
               Err (Line, "invalid direction """ & Value & """");
            end if;
         elsif Key = "input" then
            Parse_Hex (Value, Cur.Input, Line);
         elsif Key = "outcome" then
            Parse_Outcome (Value, Cur.Expected, Out_Ok);
            if not Out_Ok then
               Err (Line, "invalid outcome """ & Value & """");
            end if;
         elsif Key = "packet_id" then
            if Value'Length > 2 and then Value (Value'First .. Value'First + 1) = "0x" then
               Parse_Nat (Value (Value'First + 2 .. Value'Last), 16, N, Ok);
            else
               Parse_Nat (Value, 10, N, Ok);
            end if;
            if Ok then
               Cur.Packet_Id := N;
               Cur.Has_Packet_Id := True;
            else
               Err (Line, "invalid packet_id """ & Value & """");
            end if;
         elsif Key = "state_after" then
            Parse_State (Value, Cur.State_After, Ok);
            if Ok then
               Cur.Has_State_After := True;
            else
               Err (Line, "invalid state_after """ & Value & """");
            end if;
         elsif Key = "canonical" then
            if Value = "true" then
               Cur.Canonical := True;
            elsif Value /= "false" then
               Err (Line, "invalid canonical value """ & Value & """");
            end if;
         elsif Key = "rejection_category" then
            if Value = "" then
               Err (Line, "empty rejection_category");
            else
               Cur.Has_Rejection_Category := True;
               Cur.Rejection_Category := To_Unbounded_String (Value);
            end if;
         end if;
      end Step_Field;

      procedure Scalar_Field (Key, Value : String; Line : Natural) is
         Ok : Boolean;
         N  : Natural;
      begin
         if Key = "id" then
            Ok := Value'Length > 0;
            for C of Value loop
               if C <= ' ' or else C >= ASCII.DEL then
                  Ok := False;
               end if;
            end loop;
            if Ok then
               S.Id := To_Unbounded_String (Value);
               S.Id_Line := Line;
            else
               Err (Line, "invalid id """ & Value & """");
            end if;
         elsif Key = "title" then
            if Value = "" then
               Err (Line, "empty title");
            end if;
            S.Title := To_Unbounded_String (Value);
         elsif Key = "description" then
            if Value = "" then
               Err (Line, "empty description");
            end if;
            S.Description := To_Unbounded_String (Value);
         elsif Key = "category" then
            Parse_Category (Value, S.Cat, Ok);
            if not Ok then
               Err (Line, "invalid category """ & Value & """");
            end if;
         elsif Key = "protocol" then
            Parse_Nat (Value, 10, N, Ok);
            if not Ok then
               Err (Line, "invalid protocol """ & Value & """");
            elsif N /= 777 then
               Err (Line, "protocol must be 777");
            else
               S.Protocol_Version := N;
            end if;
         elsif Key = "provenance" then
            declare
               V : String := Value;
            begin
               for C of V loop
                  if C = '-' then
                     C := '_';
                  end if;
               end loop;
               Ok := Ada.Strings.Fixed.Index (Value, "_") = 0;
               if Ok then
                  Parse_Provenance (V, S.Prov, Ok);
               end if;
            end;
            Prov_Ok := Ok;
            if not Ok then
               Err (Line, "invalid provenance """ & Value & """");
            end if;
         elsif Key = "initial_state" then
            Parse_State (Value, S.Initial_State, Ok);
            if not Ok then
               Err (Line, "invalid initial_state """ & Value & """");
            end if;
         elsif Key = "final_state" then
            Parse_State (Value, S.Final_State, Ok);
            if Ok then
               S.Has_Final_State := True;
            else
               Err (Line, "invalid final_state """ & Value & """");
            end if;
         elsif Key = "reference" then
            if Value = "" then
               Err (Line, "empty reference");
            else
               S.Has_Reference := True;
               S.Reference := To_Unbounded_String (Value);
            end if;
         end if;
      end Scalar_Field;

      procedure Handle (Line : String; Line_No : Natural) is
         C : Natural := 0;
      begin
         if Line = "" or else Line (Line'First) = '#' then
            return;
         end if;
         for I in Line'Range loop
            if Line (I) = ':' then
               C := I;
               exit;
            end if;
         end loop;
         if C = 0 then
            Err (Line_No, "malformed line (no ':')");
            return;
         end if;
         declare
            Key   : constant String := Trim (Line (Line'First .. C - 1));
            Value : constant String := Trim (Line (C + 1 .. Line'Last));
            Valid : Boolean := Key'Length > 0;
         begin
            for K of Key loop
               if not (K in 'a' .. 'z' or else K = '_') then
                  Valid := False;
               end if;
            end loop;
            if not Valid then
               Err (Line_No, "invalid key """ & Key & """");
               return;
            end if;
            if not Seen_First then
               Seen_First := True;
               if Key = "corpus_format" then
                  if Value /= "1" then
                     Err (Line_No, "unknown corpus_format """ & Value & """");
                  end if;
                  Seen_Top := Seen_Top & " corpus_format ";
                  return;
               else
                  Err (Line_No, "file must start with corpus_format: 1");
               end if;
            end if;
            if Key = "step" then
               if Value /= "" then
                  Err (Line_No, "step: takes no value");
               end if;
               if Have_Cur then
                  Finish_Step;
               end if;
               In_Step := True;
               Skip := False;
               Seen_Step := Null_Unbounded_String;
               Out_Ok := False;
               if Step_Count >= Max_Steps then
                  if Step_Count = Max_Steps then
                     Err (Line_No, "too many steps (maximum 1024)");
                  end if;
                  Step_Count := Step_Count + 1;
                  Skip := True;
               else
                  Step_Count := Step_Count + 1;
                  Cur := Step'(others => <>);
                  Cur.Line := Line_No;
                  Have_Cur := True;
               end if;
            elsif In_Step then
               if Skip then
                  return;
               end if;
               if Has (Seen_Step, Key) then
                  Err (Line_No, "duplicate key """ & Key & """ in step");
               else
                  Seen_Step := Seen_Step & " " & Key & " ";
                  Step_Field (Key, Value, Line_No);
               end if;
            else
               if Has (Seen_Top, Key) then
                  Err (Line_No, "duplicate key """ & Key & """");
               else
                  Seen_Top := Seen_Top & " " & Key & " ";
                  Scalar_Field (Key, Value, Line_No);
               end if;
            end if;
         end;
      end Handle;

      Pos     : Natural := Text'First;
      Line_No : Natural := 0;
   begin
      S := Scenario'(others => <>);
      S.Path := To_Unbounded_String (Path);
      while Pos <= Text'Last loop
         declare
            E : Natural := Pos;
         begin
            while E <= Text'Last and then Text (E) /= ASCII.LF loop
               E := E + 1;
            end loop;
            Line_No := Line_No + 1;
            Handle (Trim (Text (Pos .. E - 1)), Line_No);
            Pos := E + 1;
         end;
      end loop;
      if Have_Cur then
         Finish_Step;
      end if;
      if not Seen_First then
         Err (1, "empty file: must start with corpus_format: 1");
      end if;
      declare
         type Name_Array is array (Positive range <>) of access constant String;
         Id  : aliased constant String := "id";
         Ti  : aliased constant String := "title";
         De  : aliased constant String := "description";
         Ca  : aliased constant String := "category";
         Pr  : aliased constant String := "protocol";
         Pv  : aliased constant String := "provenance";
         Ist : aliased constant String := "initial_state";
         Req : constant Name_Array := (Id'Access, Ti'Access, De'Access, Ca'Access,
                                       Pr'Access, Pv'Access, Ist'Access);
      begin
         for R of Req loop
            if not Has (Seen_Top, R.all) then
               Err (1, "missing required field " & R.all);
            end if;
         end loop;
      end;
      if Prov_Ok and then S.Prov = Regression and then not S.Has_Reference then
         Err (1, "provenance regression: missing reference");
      end if;
      if S.Steps.Length = 0 and then Step_Count = 0 then
         Err (1, "scenario has no steps");
      end if;
      for I in 1 .. Natural (S.Steps.Length) loop
         if S.Steps (I).Expected /= Accepted
           and then I /= Natural (S.Steps.Length)
         then
            Err (S.Steps (I).Line, "terminal step must be last");
         end if;
      end loop;
      return Errors.Length = Start;
   exception
      when others =>
         Err (1, "internal error while parsing");
         return False;
   end Parse;

   function Read_File (Path : String) return String is
      use Ada.Streams;
      F    : Stream_IO.File_Type;
      N    : constant Stream_Element_Offset :=
        Stream_Element_Offset (Ada.Directories.Size (Path));
      Buf  : Stream_Element_Array (1 .. N);
      Last : Stream_Element_Offset;
   begin
      Stream_IO.Open (F, Stream_IO.In_File, Path);
      Stream_IO.Read (F, Buf, Last);
      Stream_IO.Close (F);
      return R : String (1 .. Natural (Last)) do
         for I in 1 .. Last loop
            R (Integer (I)) := Character'Val (Integer (Buf (I)));
         end loop;
      end return;
   end Read_File;

   procedure Load
     (Dir       : String;
      Scenarios : out Scenario_Vectors.Vector;
      Errors    : out Error_Vectors.Vector)
   is
      Names : Name_Vectors.Vector;

      procedure Add_Err (P : String; Line : Natural; Reason : String) is
      begin
         Errors.Append
           (Error'(Path   => To_Unbounded_String (P),
                   Line   => Line,
                   Reason => To_Unbounded_String (Reason)));
      end Add_Err;
   begin
      Scenarios.Clear;
      Errors.Clear;
      begin
         Names := Discover (Dir);
      exception
         when others =>
            Add_Err (Dir, 1, "cannot read corpus directory");
            return;
      end;
      for N of Names loop
         declare
            P  : constant String := To_String (N);
            S  : Scenario;
            Ok : Boolean;
         begin
            if Ada.Directories.Size (P) > Ada.Directories.File_Size (Max_File_Size) then
               Add_Err (P, 1, "file too large (maximum 1048576 bytes)");
            else
               Ok := Parse (Read_File (P), P, S, Errors);
               if Ok then
                  declare
                     Dup : Boolean := False;
                  begin
                     for Prev of Scenarios loop
                        if Prev.Id = S.Id then
                           Dup := True;
                           Add_Err (P, S.Id_Line,
                                    "duplicate scenario id """ & To_String (S.Id)
                                    & """ (first in " & To_String (Prev.Path) & ")");
                        end if;
                     end loop;
                     if not Dup then
                        Scenarios.Append (S);
                     end if;
                  end;
               end if;
            end if;
         exception
            when others =>
               Add_Err (P, 1, "cannot read file");
         end;
      end loop;
   end Load;

end Adacraft.Corpus.Loader;
