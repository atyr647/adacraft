with Ada.Command_Line;
with Ada.Real_Time;
with Ada.Streams;
with Ada.Strings.Fixed;
with Ada.Text_IO;
with GNAT.Sockets;

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

   package D_Net is
      --  Bounded TCP layer (GNAT.Sockets + Ada.Real_Time only).
      --  No Java, no process spawn, single-threaded per target.
      --  Pattern only inspected from src/network/adacraft-network.*
      --  (Send/Receive_Socket) and src/protocol/adacraft-protocol-buffer.*
      --  (bounded octet handling); nothing copied semantically.
      --  All waits use Check_Selector + Real_Time deadlines; per-read and
      --  per-scenario deadlines enforced by callers via Deadline params.

      Max_Frame_Len : constant := 2_097_151;
      --  Minecraft length-prefix ceiling (2**21 - 1). Larger => malformed.

      Max_Slice : constant Duration := 0.050;
      --  Single Check_Selector slice; outer loop re-checks Deadline so
      --  per-read/per-scenario caps hold even on portable platforms.

      type Recv_Status is
        (Got_Frame, Peer_Closed, Timeout_Expired, Malformed);

      type Frame_Storage is
        array (1 .. Max_Frame_Len) of Ada.Streams.Stream_Element;

      procedure Connect
        (Host_Image : String;
         Port       : Natural;
         Sock       : out GNAT.Sockets.Socket_Type;
         Ok         : out Boolean;
         Timeout_Secs : Natural := 5);
      --  Blocking Connect_Socket wrapped in a handler; Ok=False on any
      --  failure (bad host/port/unreachable). Timeout_Secs documents the
      --  5s budget enforced by the caller's scenario deadline and the OS;
      --  no thread is spawned. Sock is valid only when Ok=True.

      procedure Close (Sock : in out GNAT.Sockets.Socket_Type);
      --  Never raises; ignores errors.

      procedure Send_All
        (Sock : GNAT.Sockets.Socket_Type;
         Data : Ada.Streams.Stream_Element_Array;
         Ok   : out Boolean);
      --  Bounded loop over Send_Socket until all bytes sent. Ok=False on
      --  any socket error; never raises.

      function Is_Readable
        (Sock     : GNAT.Sockets.Socket_Type;
         Deadline : Ada.Real_Time.Time) return Boolean;
      --  Check_Selector loop in Max_Slice slices until readable or
      --  Deadline passes. False on timeout or any selector error.

      procedure Recv_Frame
        (Sock     : GNAT.Sockets.Socket_Type;
         Deadline : Ada.Real_Time.Time;
         Buf      : in out Frame_Storage;
         Len      : out Natural;
         Status   : out Recv_Status);
      --  Reads one length-prefixed frame: VarInt length (max 5 bytes,
      --  minimal encoding, 0 .. Max_Frame_Len) then Length payload bytes.
      --  Payload is stored in Buf(1..Len) for the caller to frame/decode;
      --  D_Net never interprets it. Oversize/overlong/negative/truncated
      --  encodings => Malformed (never raises). Peer close with zero bytes
      --  outstanding => Peer_Closed. Deadline passed while waiting =>
      --  Timeout_Expired. Never raises; all exceptions map to a Status.
   end D_Net;

   package body D_Net is
      use type Ada.Real_Time.Time;
      use type Ada.Streams.Stream_Element_Offset;
      use type GNAT.Sockets.Selector_Status;

      procedure Connect
        (Host_Image : String;
         Port       : Natural;
         Sock       : out GNAT.Sockets.Socket_Type;
         Ok         : out Boolean;
         Timeout_Secs : Natural := 5)
      is
         pragma Unreferenced (Timeout_Secs);
         Addr : GNAT.Sockets.Sock_Addr_Type;
      begin
         Ok := False;
         if Port > 65_535 or else Host_Image'Length = 0 then
            return;
         end if;
         begin
            GNAT.Sockets.Create_Socket (Sock);
         exception
            when others =>
               return;
         end;
         begin
            Addr.Addr := GNAT.Sockets.Inet_Addr (Host_Image);
            Addr.Port := GNAT.Sockets.Port_Type (Port);
            GNAT.Sockets.Connect_Socket (Sock, Addr);
            Ok := True;
         exception
            when others =>
               begin
                  GNAT.Sockets.Close_Socket (Sock);
               exception
                  when others =>
                     null;
               end;
               Ok := False;
         end;
      end Connect;

      procedure Close (Sock : in out GNAT.Sockets.Socket_Type) is
      begin
         begin
            GNAT.Sockets.Close_Socket (Sock);
         exception
            when others =>
               null;
         end;
      end Close;

      procedure Send_All
        (Sock : GNAT.Sockets.Socket_Type;
         Data : Ada.Streams.Stream_Element_Array;
         Ok   : out Boolean)
      is
         Next : Ada.Streams.Stream_Element_Offset := Data'First;
         Last : Ada.Streams.Stream_Element_Offset;
      begin
         Ok := False;
         if Data'Length = 0 then
            Ok := True;
            return;
         end if;
         while Next <= Data'Last loop
            begin
               GNAT.Sockets.Send_Socket (Sock, Data (Next .. Data'Last), Last);
            exception
               when others =>
                  return;
            end;
            exit when Last < Next;
            Next := Last + 1;
         end loop;
         Ok := (Next > Data'Last);
      end Send_All;

      function Is_Readable
        (Sock     : GNAT.Sockets.Socket_Type;
         Deadline : Ada.Real_Time.Time) return Boolean
      is
      begin
         loop
            declare
               Now : constant Ada.Real_Time.Time := Ada.Real_Time.Clock;
            begin
               if Now >= Deadline then
                  return False;
               end if;
               declare
                  Remaining : constant Duration :=
                    Ada.Real_Time.To_Duration (Deadline - Now);
                  Slice : Duration := Max_Slice;
                  Sel   : GNAT.Sockets.Selector_Type;
                  R_Set : GNAT.Sockets.Socket_Set_Type;
                  W_Set : GNAT.Sockets.Socket_Set_Type;
                  Stat  : GNAT.Sockets.Selector_Status;
               begin
                  if Remaining < Slice then
                     Slice := Remaining;
                  end if;
                  begin
                     GNAT.Sockets.Create_Selector (Sel);
                  exception
                     when others =>
                        return False;
                  end;
                  begin
                     GNAT.Sockets.Empty (R_Set);
                     GNAT.Sockets.Empty (W_Set);
                     GNAT.Sockets.Set (R_Set, Sock);
                     GNAT.Sockets.Check_Selector
                       (Sel, R_Set, W_Set, Stat, Slice);
                     declare
                        Ready : constant Boolean :=
                          (Stat = GNAT.Sockets.Completed
                           and then GNAT.Sockets.Is_Set (R_Set, Sock));
                     begin
                        begin
                           GNAT.Sockets.Close_Selector (Sel);
                        exception
                           when others =>
                              null;
                        end;
                        if Ready then
                           return True;
                        end if;
                        if Stat = GNAT.Sockets.Expired then
                           null; --  re-check Deadline above
                        else
                           --  Aborted or empty: poll again until Deadline.
                           null;
                        end if;
                     end;
                  exception
                     when others =>
                        begin
                           GNAT.Sockets.Close_Selector (Sel);
                        exception
                           when others =>
                              null;
                        end;
                        return False;
                  end;
               end;
            end;
         end loop;
      exception
         when others =>
            return False;
      end Is_Readable;

      procedure Recv_Byte
        (Sock     : GNAT.Sockets.Socket_Type;
         Deadline : Ada.Real_Time.Time;
         Value    : out Ada.Streams.Stream_Element;
         Got      : out Boolean;
         Closed   : out Boolean;
         Timedout : out Boolean)
      is
         Item : Ada.Streams.Stream_Element_Array (1 .. 1);
         Last : Ada.Streams.Stream_Element_Offset;
      begin
         Value := 0;
         Got := False;
         Closed := False;
         Timedout := False;
         if not Is_Readable (Sock, Deadline) then
            if Ada.Real_Time.Clock >= Deadline then
               Timedout := True;
            else
               Closed := True;
            end if;
            return;
         end if;
         begin
            GNAT.Sockets.Receive_Socket (Sock, Item, Last);
         exception
            when others =>
               Closed := True;
               return;
         end;
         if Last < Item'First then
            Closed := True;
            return;
         end if;
         Value := Item (Item'First);
         Got := True;
      end Recv_Byte;

      function Minimal_Varint_Len (V : Natural) return Natural is
      begin
         if V < 128 then
            return 1;
         elsif V < 16_384 then
            return 2;
         elsif V < 2_097_152 then
            return 3;
         elsif V < 268_435_456 then
            return 4;
         else
            return 5;
         end if;
      end Minimal_Varint_Len;

      procedure Recv_Frame
        (Sock     : GNAT.Sockets.Socket_Type;
         Deadline : Ada.Real_Time.Time;
         Buf      : in out Frame_Storage;
         Len      : out Natural;
         Status   : out Recv_Status)
      is
         Value : Natural := 0;
         Shift : Natural := 0;
         Used  : Natural := 0;
      begin
         Len := 0;
         Status := Malformed;
         --  Length prefix: up to 5 VarInt bytes, minimal encoding only.
         loop
            declare
               B        : Ada.Streams.Stream_Element;
               Got      : Boolean;
               Closed   : Boolean;
               Timedout : Boolean;
            begin
               Recv_Byte (Sock, Deadline, B, Got, Closed, Timedout);
               if Timedout then
                  Status := Timeout_Expired;
                  return;
               elsif Closed or else not Got then
                  Status := Peer_Closed;
                  return;
               end if;
               Used := Used + 1;
               if Used > 5 then
                  Status := Malformed; --  overlong VarInt
                  return;
               end if;
               declare
                  Low7 : constant Natural :=
                    Natural (B and 16#7F#);
               begin
                  if Shift >= 28 and then Low7 > 15 then
                     Status := Malformed; --  overflow / negative
                     return;
                  end if;
                  Value := Value + Low7 * (2 ** Shift);
               end;
               if (B and 16#80#) = 0 then
                  exit;
               end if;
               Shift := Shift + 7;
            end;
         end loop;
         if Value > Max_Frame_Len then
            Status := Malformed; --  oversize frame
            return;
         end if;
         if Minimal_Varint_Len (Value) /= Used then
            Status := Malformed; --  non-minimal (overlong) encoding
            return;
         end if;
         Len := Value;
         if Len = 0 then
            Status := Got_Frame;
            return;
         end if;
         --  Payload: exactly Len bytes, bounded by Max_Frame_Len.
         declare
            Have : Natural := 0;
         begin
            while Have < Len loop
               exit when Ada.Real_Time.Clock >= Deadline;
               if not Is_Readable (Sock, Deadline) then
                  if Ada.Real_Time.Clock >= Deadline then
                     Status := Timeout_Expired;
                  else
                     Status := Peer_Closed;
                  end if;
                  Len := 0;
                  return;
               end if;
               declare
                  Want  : constant Positive := Len - Have;
                  Chunk : constant Positive := Natural'Min (Want, 4096);
                  Item  : Ada.Streams.Stream_Element_Array
                    (1 .. Ada.Streams.Stream_Element_Offset (Chunk));
                  Last  : Ada.Streams.Stream_Element_Offset;
               begin
                  begin
                     GNAT.Sockets.Receive_Socket (Sock, Item, Last);
                  exception
                     when others =>
                        --  Truncated payload counts as malformed; a clean
                        --  close with zero bytes read is peer-closed, but
                        --  mid-frame loss cannot be decoded.
                        if Have = 0 and then Len = 0 then
                           Status := Peer_Closed;
                        else
                           Status := Malformed;
                        end if;
                        Len := 0;
                        return;
                  end;
                  if Last < Item'First then
                     if Have = 0 then
                        --  Length said >0 but peer closed immediately:
                        --  truncated frame.
                        Status := Malformed;
                     else
                        Status := Malformed;
                     end if;
                     Len := 0;
                     return;
                  end if;
                  declare
                     N : constant Natural :=
                       Natural (Last - Item'First + 1);
                  begin
                     for I in 0 .. N - 1 loop
                        Buf (Have + I + 1) := Item (Item'First + Ada.Streams.Stream_Element_Offset (I));
                     end loop;
                     Have := Have + N;
                  end;
               end;
            end loop;
            if Have < Len then
               if Ada.Real_Time.Clock >= Deadline then
                  Status := Timeout_Expired;
               else
                  Status := Malformed; --  truncated frame
               end if;
               Len := 0;
               return;
            end if;
         end;
         Status := Got_Frame;
      exception
         when others =>
            Len := 0;
            Status := Malformed;
      end Recv_Frame;
   end D_Net;

   package D_Report is
      --  Deterministic human-readable report (AC 6, FR-8).
      --  Only Ada.Text_IO.Put_Line (LF-terminated lines), fixed field
      --  widths, CLI scenario order, no wall-clock / PIDs / map order.
      --  Format per scenario:
      --    scenario: <name>
      --    oracle: <n> entries outcome=<outcome>
      --    oracle[   1]: state=    0 dir=S2C id=    0
      --    ...
      --    candidate: <n> entries outcome=<outcome>
      --    candidate[   1]: ...
      --    MATCH | DIVERGE index=<i> [oracle=<entry>] [candidate=<entry>]
      --  Pure Put_Line wrappers except for I/O itself; Entry/Outcome
      --  images are pure functions (deterministic, byte-identical re-run).
      function Outcome_Image (O : D_Defs.Outcome) return String;
      function Entry_Image (E : D_Defs.Entry) return String;
      procedure Report_Scenario
        (Name       : String;
         Oracle_T   : D_Defs.Transcript;
         Cand_T     : D_Defs.Transcript;
         Any_Diverge : in out Boolean);
   end D_Report;

   package body D_Report is
      function Pad_Left (S : String; Width : Positive) return String is
      begin
         if S'Length >= Width then
            return S;
         end if;
         declare
            P : String (1 .. Width - S'Length) := (others => ' ');
         begin
            return P & S;
         end;
      end Pad_Left;

      function Num (N : Natural; Width : Positive) return String is
         T : constant String :=
           Ada.Strings.Fixed.Trim (Natural'Image (N), Ada.Strings.Both);
      begin
         return Pad_Left (T, Width);
      end Num;

      function Outcome_Image (O : D_Defs.Outcome) return String is
      begin
         case O is
            when D_Defs.Closed_By_Peer   => return "closed_by_peer";
            when D_Defs.Still_Open_At_End => return "still_open_at_end";
            when D_Defs.Timeout          => return "timeout";
            when D_Defs.Connect_Failed   => return "connect_failed";
            when D_Defs.Malformed_Input  => return "malformed_input";
         end case;
      end Outcome_Image;

      function Dir_Image (D : D_Defs.Direction) return String is
      begin
         case D is
            when D_Defs.S2C => return "S2C";
         end case;
      end Dir_Image;

      function Entry_Image (E : D_Defs.Entry) return String is
      begin
         return "state=" & Num (E.State, 5) & " dir=" & Dir_Image (E.Dir) &
           " id=" & Num (E.Id, 5);
      end Entry_Image;

      procedure Put_Transcript
        (Label : String; T : D_Defs.Transcript)
      is
      begin
         Ada.Text_IO.Put_Line
           (Label & ": " & Num (T.Count, 4) & " entries outcome=" &
            Outcome_Image (T.Result));
         for I in 1 .. T.Count loop
            Ada.Text_IO.Put_Line
              (Label & "[" & Num (I, 4) & "]: " &
               Entry_Image (D_Defs.Get (T, I)));
         end loop;
      end Put_Transcript;

      procedure Report_Scenario
        (Name       : String;
         Oracle_T   : D_Defs.Transcript;
         Cand_T     : D_Defs.Transcript;
         Any_Diverge : in out Boolean)
      is
         Idx : constant Natural :=
           D_Compare.First_Divergence_Index (Oracle_T, Cand_T);
      begin
         --  Scenario name first, then oracle lines, then candidate lines,
         --  then verdict. Caller preserves CLI order.
         Ada.Text_IO.Put_Line ("scenario: " & Name);
         Put_Transcript ("oracle", Oracle_T);
         Put_Transcript ("candidate", Cand_T);
         if Idx = 0 then
            Ada.Text_IO.Put_Line ("MATCH");
         else
            Any_Diverge := True;
            if Idx <= Oracle_T.Count and then Idx <= Cand_T.Count then
               Ada.Text_IO.Put_Line
                 ("DIVERGE index=" &
                  Ada.Strings.Fixed.Trim
                    (Natural'Image (Idx), Ada.Strings.Both) &
                  " oracle=(" & Entry_Image (D_Defs.Get (Oracle_T, Idx)) &
                  ") candidate=(" & Entry_Image (D_Defs.Get (Cand_T, Idx)) &
                  ")");
            elsif Oracle_T.Count /= Cand_T.Count then
               Ada.Text_IO.Put_Line
                 ("DIVERGE index=" &
                  Ada.Strings.Fixed.Trim
                    (Natural'Image (Idx), Ada.Strings.Both) &
                  " oracle-count=" &
                  Ada.Strings.Fixed.Trim
                    (Natural'Image (Oracle_T.Count), Ada.Strings.Both) &
                  " candidate-count=" &
                  Ada.Strings.Fixed.Trim
                    (Natural'Image (Cand_T.Count), Ada.Strings.Both));
            else
               --  Entry sequences (incl. counts) equal, outcomes differ.
               Ada.Text_IO.Put_Line
                 ("DIVERGE index=" &
                  Ada.Strings.Fixed.Trim
                    (Natural'Image (Idx), Ada.Strings.Both) &
                  " oracle-outcome=" & Outcome_Image (Oracle_T.Result) &
                  " candidate-outcome=" & Outcome_Image (Cand_T.Result));
            end if;
         end if;
      end Report_Scenario;
   end D_Report;

   package D_Main is
      --  Exit mapping (AC 7):
      --    bad-args / unreadable scenario            -> 2 (harness error)
      --    oracle Connect_Failed                     -> 2 (harness error)
      --    candidate connect/timeout/close failure   -> DIVERGE (exit 1 path)
      --    all scenarios MATCH                       -> 0
      --    any scenario DIVERGE                      -> 1
      --  Pure mapping plus readability pre-check used before any
      --  network I/O so harness errors never masquerade as DIVERGE.
      function Map_Exit
        (Oracle_Connect_Failed : Boolean;
         Any_Diverge           : Boolean) return Integer;
      --  2 when Oracle_Connect_Failed, else 1 when Any_Diverge, else 0.

      function Check_Scenarios_Readable return Boolean;
      --  Tries to open each CLI scenario for reading (Ada.Text_IO only).
      --  Returns True when all readable; on failure prints
      --  "differential: unreadable scenario '<p>'" to Standard_Error and
      --  returns False (caller maps to exit 2).

      procedure Set_Exit (Code : Integer);
      --  0 -> Success, 1/2 -> numeric exit status via Set_Exit_Status.
   end D_Main;

   package body D_Main is
      function Map_Exit
        (Oracle_Connect_Failed : Boolean;
         Any_Diverge           : Boolean) return Integer
      is
      begin
         if Oracle_Connect_Failed then
            return 2;
         elsif Any_Diverge then
            return 1;
         else
            return 0;
         end if;
      end Map_Exit;

      function Check_Scenarios_Readable return Boolean is
      begin
         for I in 1 .. D_Args.Scenario_Count loop
            declare
               Name : constant String := D_Args.Scenario (I);
               F    : Ada.Text_IO.File_Type;
            begin
               begin
                  Ada.Text_IO.Open (F, Ada.Text_IO.In_File, Name);
               exception
                  when others =>
                     Ada.Text_IO.Put_Line
                       (Ada.Text_IO.Standard_Error,
                        "differential: unreadable scenario '" & Name & "'");
                     return False;
               end;
               begin
                  if Ada.Text_IO.Is_Open (F) then
                     Ada.Text_IO.Close (F);
                  end if;
               exception
                  when others =>
                     null;
               end;
            end;
         end loop;
         return True;
      end Check_Scenarios_Readable;

      procedure Set_Exit (Code : Integer) is
      begin
         if Code = 0 then
            Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Success);
         else
            Ada.Command_Line.Set_Exit_Status
              (Ada.Command_Line.Exit_Status (Code));
         end if;
      end Set_Exit;
   end D_Main;

begin
   D_Args.Parse;
   if Ada.Command_Line.Exit_Status /= Ada.Command_Line.Success then
      --  Bad args already reported by D_Args.Fail; Fail sets status 2.
      return;
   end if;
   if not D_Main.Check_Scenarios_Readable then
      D_Main.Set_Exit (2);
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
   --  No D_Run yet: no transcripts to compare, no oracle connection
   --  attempted, so Oracle_Connect_Failed = False, Any_Diverge = False.
   D_Main.Set_Exit (D_Main.Map_Exit (Oracle_Connect_Failed => False,
                                     Any_Diverge           => False));
end Differential_Main;
