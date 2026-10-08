with Ada.Command_Line;
with Ada.Directories;
with Ada.Streams.Stream_IO;
with Ada.Strings.Unbounded;
with Ada.Text_IO;
with Adacraft.Corpus;
with Adacraft.Corpus.Loader;
with Interfaces;
with Ada.Real_Time;
with Ada.Streams;
with GNAT.Sockets;
with Adacraft.Protocol;
with Adacraft.Protocol.Frame;
with Adacraft.Protocol.Ids;
with Adacraft.Protocol.Packets;
with Adacraft.Protocol.Varnum;
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
         if V > (Limit - (Character'Pos (C) - Character'Pos ('0'))) / 10 then
            return -1;
         end if;
         V := V * 10 + (Character'Pos (C) - Character'Pos ('0'));
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
               N := Parse_Number (Argument (I + 1), Integer'Last);
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
   procedure Load_Scenario
     (Path : String; Name : out Unbounded_String;
      Scn  : out Adacraft.Corpus.Scenario)
   is
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
         Scn := S;
         if Length (S.Id) > 0 then
            Name := S.Id;
         else
            Name := To_Unbounded_String (Ada.Directories.Base_Name (Path));
         end if;
      end;
   end Load_Scenario;

   function Img (N : Long_Long_Integer) return String is
      T : constant String := Long_Long_Integer'Image (N);
   begin
      if T (T'First) = ' ' then
         return T (T'First + 1 .. T'Last);
      end if;
      return T;
   end Img;

   function Outcome_Name (O : Outcome_Kind) return String is
   begin
      return Outcome_Kind'Image (O);
   end Outcome_Name;

   function Summary (O : Observation) return String is
   begin
      return Adacraft.Protocol.State.Connection_State'Image (O.Final_State)
        & "/" & Outcome_Name (O.Outcome);
   end Summary;

   function List_Image (O : Observation) return String is
      R : Unbounded_String;
   begin
      if O.Count = 0 then
         return "none";
      end if;
      for I in 1 .. O.Count loop
         if I > 1 then
            Append (R, ", ");
         end if;
         Append
           (R, Img (Long_Long_Integer (O.Packets (I).Id)) & "@"
            & Adacraft.Protocol.State.Connection_State'Image
                (O.Packets (I).State));
      end loop;
      return To_String (R);
   end List_Image;

   function Same_Lists (A, B : Observation) return Boolean is
   begin
      if A.Count /= B.Count then
         return False;
      end if;
      for I in 1 .. A.Count loop
         if A.Packets (I) /= B.Packets (I) then
            return False;
         end if;
      end loop;
      return True;
   end Same_Lists;

   --  Replays one scenario against one endpoint and records the observation.
   procedure Run_Endpoint
     (Host       : String;
      Port       : Natural;
      S          : Adacraft.Corpus.Scenario;
      Timeout    : Positive;
      Kind       : Endpoint_Kind;
      Obs        : out Observation)
   is
      package P renames Adacraft.Protocol;
      package PS renames Adacraft.Protocol.State;
      package GS renames GNAT.Sockets;
      use type P.Status_Kind;
      use type PS.Result_Kind;
      use type P.Frame.Feed_Status;
      use type GS.Selector_Status;
      use type Ada.Streams.Stream_Element_Offset;
      use type Ada.Real_Time.Time;
      use type Interfaces.Unsigned_32;

      Cap       : constant := 2 * 1024 * 1024;
      Endpoint  : constant String := Host & ":" & Natural'Image (Port);
      Sock      : GS.Socket_Type;
      Sel       : GS.Selector_Type;
      Connected : Boolean := False;
      Bad       : Boolean := False;
      State     : PS.Connection_State := S.Initial_State;
      Total     : Natural := 0;

      procedure On_Frame (Frame : in P.Frame.Byte_Array) is
         N   : constant Natural := Natural'Min (Natural (Frame'Length), 5);
         Buf : P.Octets (1 .. 5) := (others => 0);
      begin
         if Bad then
            return;
         end if;
         for I in 1 .. N loop
            Buf (I) := P.Octet
              (Frame (Frame'First + Ada.Streams.Stream_Element_Offset (I - 1)));
         end loop;
         declare
            V : constant P.Varnum.Varint_Result :=
              P.Varnum.Decode_Varint (Buf (1 .. N), 1);
         begin
            if V.Status /= P.Ok or else V.Value > 1_000_000 then
               Bad := True;
               return;
            end if;
            declare
               Ev : constant PS.Packet_Event :=
                 (Direction => PS.Clientbound,
                  Id        => PS.Packet_Id (V.Value),
                  Intent    => 0);
               T  : constant PS.Transition_Result := PS.Transition (State, Ev);
            begin
               if T.Kind = PS.Rejected then
                  Bad := True;
                  return;
               end if;
               State := T.Next_State;
               Obs.Final_State := State;
               if Obs.Count >= Max_Packets then
                  --  List capacity exceeded: surfaced as a malformed run
                  --  rather than silently truncating.
                  Bad := True;
                  return;
               end if;
               Obs.Count := Obs.Count + 1;
               Obs.Packets (Obs.Count) := (Id => Ev.Id, State => State);
            end;
         end;
      end On_Frame;

      --  Scenario input is already a complete frame (length prefix
      --  included); it is validated with the framing/state units and
      --  replayed as-is, so no encoding is duplicated here.
      procedure Send_Phase is
         Send_State : PS.Connection_State := S.Initial_State;
      begin
         for St of S.Steps loop
            if St.Dir = Adacraft.Corpus.Serverbound then
               declare
                  Input : P.Octets (1 .. Natural (St.Input.Length));
                  Data  : Ada.Streams.Stream_Element_Array
                    (1 .. Ada.Streams.Stream_Element_Offset (Input'Length));
                  First : Ada.Streams.Stream_Element_Offset := 1;
                  Last  : Ada.Streams.Stream_Element_Offset;
               begin
                  for I in Input'Range loop
                     Input (I) := St.Input (I);
                     Data (Ada.Streams.Stream_Element_Offset (I)) :=
                       Ada.Streams.Stream_Element (Input (I));
                  end loop;
                  if Input'Length > 0 then
                     declare
                        F : constant P.Frame.Frame_Decode :=
                          P.Frame.Decode_Frame (Input, 1);
                     begin
                        if F.Status = P.Ok then
                           declare
                              Payload : constant P.Octets :=
                                Input (F.Payload_First .. F.Payload_Last);
                              Intent  : PS.Handshake_Intent := 0;
                           begin
                              if Send_State = PS.Handshake
                                and then F.Packet_Id =
                                  P.Ids.Protocol_Id (P.Ids.Sb_Handshake_Intention)
                              then
                                 declare
                                    H : constant P.Packets.Handshake :=
                                      P.Packets.Decode_Handshake (Payload);
                                 begin
                                    if H.Status = P.Ok then
                                       Intent := PS.Handshake_Intent (H.Intent);
                                    end if;
                                 end;
                              end if;
                              declare
                                 T : constant PS.Transition_Result :=
                                   PS.Transition
                                     (Send_State,
                                      (Direction => PS.Serverbound,
                                       Id        => PS.Packet_Id (F.Packet_Id),
                                       Intent    => Intent));
                              begin
                                 if T.Kind = PS.Rejected then
                                    Fail ("error: scenario packet rejected by "
                                          & "state machine for " & Endpoint);
                                 end if;
                                 Send_State := T.Next_State;
                              end;
                           end;
                        end if;
                     end;
                  end if;
                  while First <= Data'Last loop
                     begin
                        GS.Send_Socket (Sock, Data (First .. Data'Last), Last);
                     exception
                        when GS.Socket_Error =>
                           Fail ("error: write failed to " & Endpoint);
                     end;
                     if Last < First then
                        Fail ("error: write failed to " & Endpoint);
                     end if;
                     First := Last + 1;
                  end loop;
               end;
            end if;
         end loop;
      end Send_Phase;

      procedure Receive_Phase is
         Deadline : constant Ada.Real_Time.Time :=
           Ada.Real_Time.Clock + Ada.Real_Time.Milliseconds (Timeout);
         Dec  : P.Frame.Decoder_Type;
         Buf  : Ada.Streams.Stream_Element_Array (1 .. 4096);
         Last : Ada.Streams.Stream_Element_Offset;
         R, W : GS.Socket_Set_Type;
         St   : GS.Selector_Status;
         Fs   : P.Frame.Feed_Status;
      begin
         loop
            declare
               Remaining : constant Duration :=
                 Ada.Real_Time.To_Duration (Deadline - Ada.Real_Time.Clock);
            begin
               if Remaining <= 0.0 then
                  Obs.Outcome := Open_At_Timeout;
                  return;
               end if;
               GS.Empty (R);
               GS.Empty (W);
               GS.Set (R, Sock);
               GS.Check_Selector (Sel, R, W, St, Remaining);
            end;
            if St = GS.Expired then
               Obs.Outcome := Open_At_Timeout;
               return;
            elsif St /= GS.Completed then
               Obs.Outcome := Closed_By_Server;
               return;
            end if;
            begin
               GS.Receive_Socket (Sock, Buf, Last);
            exception
               when GS.Socket_Error =>
                  Obs.Outcome := Closed_By_Server;
                  return;
            end;
            if Last < Buf'First then
               Obs.Outcome := Closed_By_Server;
               return;
            end if;
            if Total + Natural (Last) >= Cap then
               Obs.Outcome := Malformed_Response;
               return;
            end if;
            Total := Total + Natural (Last);
            P.Frame.Feed (Dec, Buf (1 .. Last), On_Frame'Access, Fs);
            if Bad or else Fs = P.Frame.Framing_Error then
               Obs.Outcome := Malformed_Response;
               return;
            end if;
         end loop;
      end Receive_Phase;
   begin
      Obs.Kind := Kind;
      Obs.Final_State := S.Initial_State;
      Obs.Outcome := Closed_By_Server;
      Obs.Count := 0;
      begin
         declare
            H    : constant GS.Host_Entry_Type := GS.Get_Host_By_Name (Host);
            Addr : constant GS.Inet_Addr_Type := GS.Addresses (H, 1);
         begin
            if Addr.Family /= GS.Family_Inet then
               Fail ("error: unsupported address for " & Endpoint);
            end if;
            GS.Create_Socket (Sock);
            Connected := True;
            GS.Connect_Socket
              (Sock, (Family => GS.Family_Inet, Addr => Addr,
                      Port   => GS.Port_Type (Port)));
         end;
      exception
         when GS.Socket_Error | GS.Host_Error =>
            if Connected then
               GS.Close_Socket (Sock);
            end if;
            Fail ("error: cannot connect to endpoint " & Endpoint);
      end;
      GS.Create_Selector (Sel);
      begin
         Send_Phase;
         Receive_Phase;
      exception
         when others =>
            GS.Close_Selector (Sel);
            GS.Close_Socket (Sock);
            raise;
      end;
      GS.Close_Selector (Sel);
      GS.Close_Socket (Sock);
   end Run_Endpoint;

begin
   Parse_Arguments;
   --  Validate every scenario up front; no network I/O yet.
   for J in First_Scen .. Ada.Command_Line.Argument_Count loop
      declare
         Name : Unbounded_String;
         Scn  : Adacraft.Corpus.Scenario;
      begin
         Load_Scenario (Ada.Command_Line.Argument (J), Name, Scn);
      end;
   end loop;
   declare
      Any_Mismatch : Boolean := False;
      O_Obs, S_Obs : Observation;
   begin
      for J in First_Scen .. Ada.Command_Line.Argument_Count loop
         declare
            Name : Unbounded_String;
            Scn  : Adacraft.Corpus.Scenario;
         begin
            Load_Scenario (Ada.Command_Line.Argument (J), Name, Scn);
            Run_Endpoint
              (To_String (Oracle_Host), Oracle_Port, Scn, Timeout_Ms,
               Oracle, O_Obs);
            Run_Endpoint
              (To_String (Subject_Host), Subject_Port, Scn, Timeout_Ms,
               Subject, S_Obs);
            if O_Obs.Final_State = S_Obs.Final_State
              and then O_Obs.Outcome = S_Obs.Outcome
            then
               Ada.Text_IO.Put_Line ("MATCH " & To_String (Name));
               if not Same_Lists (O_Obs, S_Obs) then
                  Ada.Text_IO.Put_Line
                    ("  oracle-packets: " & List_Image (O_Obs));
                  Ada.Text_IO.Put_Line
                    ("  subject-packets: " & List_Image (S_Obs));
               end if;
            else
               Any_Mismatch := True;
               Ada.Text_IO.Put_Line
                 ("MISMATCH " & To_String (Name) & " oracle="
                  & Summary (O_Obs) & " subject=" & Summary (S_Obs));
               Ada.Text_IO.Put_Line
                 ("  oracle-packets: " & List_Image (O_Obs));
               Ada.Text_IO.Put_Line
                 ("  subject-packets: " & List_Image (S_Obs));
            end if;
         end;
      end loop;
      if Any_Mismatch then
         Ada.Command_Line.Set_Exit_Status (1);
      else
         Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Success);
      end if;
   end;
exception
   when Setup_Error =>
      Ada.Command_Line.Set_Exit_Status (2);
   when Usage_Error =>
      Usage;
      Ada.Command_Line.Set_Exit_Status (2);
end Differential_Main;
