with Ada.Command_Line;
with Ada.Directories;
with Ada.Streams.Stream_IO;
with Ada.Strings.Unbounded;
with Ada.Text_IO;
with Adacraft.Corpus;
with Adacraft.Corpus.Loader;
with Adacraft.Protocol.State;

procedure Differential_Main is
   use Ada.Strings.Unbounded;

   type Outcome_Kind is (Closed_By_Server, Open_At_Timeout, Malformed_Response);
   type Endpoint_Kind is (Oracle, Subject);

   Max_Packets : constant := 65_536;

   type Packet_Record is record
      Id    : Adacraft.Protocol.State.Packet_Id := 0;
      State : Adacraft.Protocol.State.Connection_State :=
        Adacraft.Protocol.State.Handshake;
   end record;

   type Packet_Array is array (1 .. Max_Packets) of Packet_Record;

   type Observation is record
      Kind        : Endpoint_Kind := Oracle;
      Final_State : Adacraft.Protocol.State.Connection_State :=
        Adacraft.Protocol.State.Handshake;
      Outcome     : Outcome_Kind := Closed_By_Server;
      Count       : Natural := 0;
      Packets     : Packet_Array;
   end record;

   pragma Unreferenced (Observation);

   Usage_Error : exception;
   Setup_Error : exception;

   Default_Timeout_Ms : constant := 5_000;

   Oracle_Host   : Unbounded_String;
   Subject_Host  : Unbounded_String;
   Oracle_Port   : Natural := 0;
   Subject_Port  : Natural := 0;
   Have_Oracle   : Boolean := False;
   Have_Subject  : Boolean := False;
   Have_Timeout  : Boolean := False;
   Timeout_Ms    : Positive := Default_Timeout_Ms;
   First_Scen    : Natural := 0;

   procedure Usage is
   begin
      Ada.Text_IO.Put_Line
        (Ada.Text_IO.Standard_Error,
         "usage: differential-main --oracle HOST:PORT --subject HOST:PORT"
         & " [--timeout-ms N] SCENARIO...");
   end Usage;

   --  Parses a decimal number of digits only; returns -1 when invalid
   --  or larger than Limit.
   function Parse_Number (S : String; Limit : Natural) return Integer is
      V : Natural := 0;
   begin
      if S'Length = 0 then
         return -1;
      end if;
      for C of S loop
         if C not in '0' .. '9' then
            return -1;
         end if;
         if V > Limit / 10 then
            return -1;
         end if;
         V := V * 10 + (Character'Pos (C) - Character'Pos ('0'));
         if V > Limit then
            return -1;
         end if;
      end loop;
      return V;
   end Parse_Number;

   procedure Parse_Endpoint
     (S : String; Host : out Unbounded_String; Port : out Natural)
   is
      Colon : Natural := 0;
      N     : Integer;
   begin
      Host := Null_Unbounded_String;
      Port := 0;
      for I in S'Range loop
         if S (I) = ':' then
            if Colon /= 0 then
               raise Usage_Error;
            end if;
            Colon := I;
         end if;
      end loop;
      if Colon = 0 or else Colon = S'First then
         raise Usage_Error;
      end if;
      N := Parse_Number (S (Colon + 1 .. S'Last), 65_535);
      if N < 1 then
         raise Usage_Error;
      end if;
      Host := To_Unbounded_String (S (S'First .. Colon - 1));
      Port := N;
   end Parse_Endpoint;

   procedure Parse_Arguments is
      use Ada.Command_Line;
      I : Positive := 1;
      N : Integer;
   begin
      while I <= Argument_Count loop
         declare
            A : constant String := Argument (I);
         begin
            if A = "--oracle" or else A = "--subject" then
               if Argument_Count < I + 1
                 or else (A = "--oracle" and Have_Oracle)
                 or else (A = "--subject" and Have_Subject)
               then
                  raise Usage_Error;
               end if;
               if A = "--oracle" then
                  Parse_Endpoint (Argument (I + 1), Oracle_Host, Oracle_Port);
                  Have_Oracle := True;
               else
                  Parse_Endpoint (Argument (I + 1), Subject_Host, Subject_Port);
                  Have_Subject := True;
               end if;
               I := I + 2;
            elsif A = "--timeout-ms" then
               if Argument_Count < I + 1 or else Have_Timeout then
                  raise Usage_Error;
               end if;
               N := Parse_Number (Argument (I + 1), 1_000_000_000);
               if N < 1 then
                  raise Usage_Error;
               end if;
               Timeout_Ms := N;
               Have_Timeout := True;
               I := I + 2;
            elsif A'Length >= 2 and then A (A'First .. A'First + 1) = "--" then
               raise Usage_Error;
            else
               First_Scen := I;
               exit;
            end if;
         end;
      end loop;
      if not Have_Oracle or not Have_Subject or First_Scen = 0 then
         raise Usage_Error;
      end if;
      for J in First_Scen .. Argument_Count loop
         declare
            A : constant String := Argument (J);
         begin
            if A'Length = 0
              or else (A'Length >= 2 and then A (A'First .. A'First + 1) = "--")
            then
               raise Usage_Error;
            end if;
         end;
      end loop;
   end Parse_Arguments;

   procedure Fail (Msg : String) is
   begin
      Ada.Text_IO.Put_Line (Ada.Text_IO.Standard_Error, Msg);
      raise Setup_Error;
   end Fail;

   --  Loads and validates one #119 scenario; returns its output name.
   function Load_Scenario (Path : String) return String is
      use Ada.Streams.Stream_IO;
      F    : File_Type;
      Size : Natural := 0;
   begin
      if not Ada.Directories.Exists (Path)
        or else Ada.Directories.Kind (Path) /= Ada.Directories.Ordinary_File
      then
         Fail ("error: scenario not found or not a file: " & Path);
      end if;
      declare
         Sz : constant Ada.Directories.File_Size := Ada.Directories.Size (Path);
      begin
         if Sz = 0 then
            Fail ("error: scenario is empty: " & Path);
         elsif Sz > Adacraft.Corpus.Max_File_Size then
            Fail ("error: scenario too large: " & Path);
         end if;
         Size := Natural (Sz);
      end;
      begin
         Open (F, In_File, Path);
      exception
         when others =>
            Fail ("error: cannot open scenario: " & Path);
      end;
      declare
         Text : String (1 .. Size);
         Errs : Adacraft.Corpus.Error_Vectors.Vector;
         S    : Adacraft.Corpus.Scenario;
         Ok   : Boolean;
      begin
         begin
            String'Read (Stream (F), Text);
         exception
            when others =>
               Close (F);
               Fail ("error: cannot read scenario: " & Path);
         end;
         Close (F);
         Ok := Adacraft.Corpus.Loader.Parse (Text, Path, S, Errs);
         if not Ok then
            for E of Errs loop
               Ada.Text_IO.Put_Line
                 (Ada.Text_IO.Standard_Error,
                  "error: " & Adacraft.Corpus.Loader.Format_Error (E));
            end loop;
            raise Setup_Error;
         end if;
         if Length (S.Id) > 0 then
            return To_String (S.Id);
         end if;
         return Ada.Directories.Base_Name (Path);
      end;
   end Load_Scenario;

begin
   Parse_Arguments;
   --  Validate every scenario up front; no network I/O yet.
   for J in First_Scen .. Ada.Command_Line.Argument_Count loop
      declare
         Name : constant String := Load_Scenario (Ada.Command_Line.Argument (J));
         pragma Unreferenced (Name);
      begin
         null;
      end;
   end loop;
   Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Success);
exception
   when Setup_Error =>
      Ada.Command_Line.Set_Exit_Status (2);
   when Usage_Error =>
      Usage;
      Ada.Command_Line.Set_Exit_Status (2);
end Differential_Main;
