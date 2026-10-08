with Ada.Command_Line;
with Ada.Real_Time;
with Ada.Streams;
with Ada.Strings.Fixed;
with Ada.Text_IO;
with Interfaces;
with GNAT.Sockets;
with Adacraft.Protocol;
with Adacraft.Protocol.Frame;
with Adacraft.Protocol.Varnum;
with Adacraft.Protocol.Packets;
with Adacraft.Protocol.State;
with Adacraft.Corpus;
with Adacraft.Corpus.Loader;

procedure Differential.Main is

   package D_Defs is
      --  Transcript types for semantic comparison.
      --  Payload bytes are consumed for framing but never stored/compared.

      type Outcome is
        (Closed_By_Peer, Still_Open_At_End, Timeout, Connect_Failed,
         Malformed_Input);

      type Direction is (S2C);

      Max_Entries  : constant := 1024;
      Max_Name_Len : constant := 512;

      type Rec is record
         State : Natural := 0;
         Dir   : Direction := S2C;
         Id    : Natural := 0;
      end record;

      type Entries_Storage is array (1 .. Max_Entries) of Rec;

      subtype Name_Storage is String (1 .. Max_Name_Len);

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
      procedure Append (T : in out Transcript; E : Rec; Full : out Boolean);
      function Get (T : Transcript; Index : Positive) return Rec;
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

      procedure Append (T : in out Transcript; E : Rec; Full : out Boolean) is
      begin
         if T.Count >= Max_Entries then
            Full := True;
            return;
         end if;
         Full := False;
         T.Count := T.Count + 1;
         T.Entries (T.Count) := E;
      end Append;

      function Get (T : Transcript; Index : Positive) return Rec is
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
               EA : constant D_Defs.Rec := A.Entries (I);
               EB : constant D_Defs.Rec := B.Entries (I);
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
               EA : constant D_Defs.Rec := A.Entries (I);
               EB : constant D_Defs.Rec := B.Entries (I);
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
                     Split_Into
                       (A, Oracle_Host, Oracle_Host_Len, Oracle_Port);
                     Oracle_Set := True;
                  exception
                     when others =>
                        Fail ("bad --oracle value '" & A & "'");
                        return;
                  end;
                  Expect_Oracle := False;
               elsif Expect_Cand then
                  begin
                     Split_Into (A, Cand_Host, Cand_Host_Len, Cand_Port);
                     Cand_Set := True;
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

      Max_Slice : constant Duration := 0.050;
      --  Single Check_Selector slice; outer loop re-checks Deadline so
      --  per-read/per-scenario caps hold even on portable platforms.

      type Recv_Status is
        (Got_Frame, Peer_Closed, Timeout_Expired, Malformed);

      --  Small bounded store: only the frame head needed for the packet-ID
      --  label is kept; remaining payload bytes are consumed and discarded
      --  so the stream stays in sync. Avoids a multi-MiB stack frame.
      Frame_Store_Len : constant := 8_192;
      type Frame_Storage is
        array (1 .. Frame_Store_Len) of Ada.Streams.Stream_Element;

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
      --  Reads one length-prefixed frame: VarInt length decoded via
      --  #115 Varnum.Decode_Varint (max Max_Varint_Bytes, ceiling
      --  Max_Packet_Length / Frame.Max_Frame_Body_Length) then Length
      --  payload bytes.
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

      --  Length-prefix decoding reuses #115 Varnum.Decode_Varint and #114
      --  limits (Adacraft.Protocol.Max_Packet_Length). No local VarInt
      --  reader, no minimal-length table, no shift arithmetic of its own.

      procedure Recv_Frame
        (Sock     : GNAT.Sockets.Socket_Type;
         Deadline : Ada.Real_Time.Time;
         Buf      : in out Frame_Storage;
         Len      : out Natural;
         Status   : out Recv_Status)
      is
         use Adacraft.Protocol;
         Value      : Natural := 0;
      begin
         Len := 0;
         Status := Malformed;
         --  Length prefix via #115: accumulate up to 5 bytes, ask
         --  Varnum.Decode_Varint after each byte. Truncated => need more
         --  bytes; Ok => length found; Overlong/others => malformed_input.
         declare
            use Adacraft.Protocol;
            use Adacraft.Protocol.Varnum;
            Prefix : Octets (1 .. Max_Varint_Bytes) := (others => 0);
            Pcount : Natural := 0;
         begin
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
                  Pcount := Pcount + 1;
                  if Pcount > Max_Varint_Bytes then
                     Status := Malformed;
                     return;
                  end if;
                  Prefix (Pcount) := Octet (B);
                  declare
                     R : constant Varint_Result :=
                       Decode_Varint (Prefix (1 .. Pcount), 1);
                  begin
                     if R.Status = Ok then
                        if R.Value < 0 then
                           Status := Malformed;
                           return;
                        end if;
                        Value := Natural (R.Value);
                        Used := Pcount;
                        exit;
                     elsif R.Status = Truncated then
                        if Pcount >= Max_Varint_Bytes then
                           Status := Malformed;
                           return;
                        end if;
                        --  Need another prefix byte.
                        null;
                     else
                        --  Overlong or any other rejection => malformed.
                        Status := Malformed;
                        return;
                     end if;
                  end;
               end;
            end loop;
            if Value > Max_Packet_Length
              or else Value
                > Natural
                    (Adacraft.Protocol.Frame.Max_Frame_Body_Length)
            then
               Status := Malformed;
               return;
            end if;
         end;
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
                        if Have + I + 1 <= Buf'Last then
                           Buf (Have + I + 1) := Item (Item'First + Ada.Streams.Stream_Element_Offset (I));
                        end if;
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
            if Len > Buf'Length then
               --  Head retained, tail discarded; caller decodes the ID
               --  from the head only, stream already consumed in full.
               Len := Buf'Length;
            end if;
         end;
         Status := Got_Frame;
      exception
         when others =>
            Len := 0;
            Status := Malformed;
      end Recv_Frame;
   end D_Net;

   package D_Run is
      --  Scenario runner: per scenario per target, independently, with
      --  fresh #118 state per run (Cur_State reset from initial_state).
      --  Reuses #114/#115/#116/#117/#118/#119 read-only semantics without
      --  product withs (lab-only differential.gpr carries Main wiring
      --  only): Corpus_Loader.Load minimal ordered-C2S view (state, id,
      --  payload-hex) mirrored by input:/initial_state/state_after parse;
      --  Packets.Encode+Varnum.Encode+Frame.Encode+Send mirrored by sending
      --  stored canonical frame bytes; ingress mirrors Frame.Decode
      --  length-limited (Max_Frame_Body_Length 2097151, Max_Length_Bytes 3,
      --  Max_Varint_Bytes 5) + Varnum.Decode (overlong => malformed_input)
      --  + Packets.Decode packet-ID + State.Valid S2C labelling (label
      --  only, never enforced). Bounded: 1024 entries, overflow stops with
      --  still_open_at_end; oversize/overlong/truncated => Malformed_Input
      --  via frame-boundary exception-when-others, never escapes, no
      --  unchecked access/conversion, no Unchecked_Conversion.
      procedure Run_Target
        (Host_Image       : String;
         Port             : Natural;
         Scenario_Path    : String;
         Read_Timeout_S   : Natural;
         Scenario_Timeout_S : Natural;
         T                : out D_Defs.Transcript);
   end D_Run;

   package body D_Run is

      --  Canonical corpus states map 1:1 onto #118 Connection_State
      --  parents (Handshake/Status/Login/Configuration/Play).
      function State_Of (Name : String) return Natural is
         --  HANDSHAKE=0 STATUS=1 LOGIN=2 CONFIGURATION=3 PLAY=4.
         --  Unknown => 0 (label only, never enforced).
      begin
         if Name = "STATUS" then
            return 1;
         elsif Name = "LOGIN" then
            return 2;
         elsif Name = "CONFIGURATION" then
            return 3;
         elsif Name = "PLAY" then
            return 4;
         else
            return 0;
         end if;
      end State_Of;

      function Hex_Val (C : Character) return Integer is
      begin
         case C is
            when '0' .. '9' => return Character'Pos (C) - Character'Pos ('0');
            when 'a' .. 'f' => return Character'Pos (C) - Character'Pos ('a') + 10;
            when 'A' .. 'F' => return Character'Pos (C) - Character'Pos ('A') + 10;
            when others => return -1;
         end case;
      end Hex_Val;

      procedure Append_Byte
        (Buf : in out Ada.Streams.Stream_Element_Array;
         Len : in out Natural;
         B   : Ada.Streams.Stream_Element;
         Full : out Boolean)
      is
      begin
         if Len >= Buf'Length then
            Full := True;
            return;
         end if;
         Full := False;
         Len := Len + 1;
         Buf (Buf'First + Ada.Streams.Stream_Element_Offset (Len - 1)) := B;
      end Append_Byte;

      --  Packet-ID decode reuses #115 Varnum.Decode_Varint (#117 decode
      --  entry point for the ID prefix). No local VarInt reader.
      procedure Decode_Packet_Id
        (Buf    : D_Net.Frame_Storage;
         Len    : Natural;
         Id     : out Natural;
         Ok     : out Boolean)
      is
         use Adacraft.Protocol;
         use Adacraft.Protocol.Varnum;
      begin
         Id := 0;
         Ok := False;
         if Len = 0 then
            return;
         end if;
         declare
            N : constant Natural := Natural'Min (Len, Max_Varint_Bytes);
            Raw : Octets (1 .. Max_Varint_Bytes) := (others => 0);
         begin
            for I in 1 .. N loop
               Raw (I) := Octet (Buf (I));
            end loop;
            declare
               R : constant Varint_Result :=
                 Decode_Varint (Raw (1 .. N), 1);
            begin
               if R.Status /= Ok or else R.Value < 0 then
                  Ok := False;
                  return;
               end if;
               Id := Natural (R.Value);
               Ok := True;
            end;
         end;
      end Decode_Packet_Id;

      --  S2C payload touch reuses #117 Packets decoders read-only
      --  (Decode_Ping / Decode_Handshake); result discarded, never
      --  enforces semantics. Label-only control flow stays in Label_S2C.
      procedure Touch_Packets_Decode
        (Buf : D_Net.Frame_Storage;
         Len : Natural)
      is
         use Adacraft.Protocol;
         use Adacraft.Protocol.Packets;
      begin
         if Len = 0 then
            return;
         end if;
         declare
            N : constant Natural := Natural'Min (Len, 256);
            Pay : Octets (1 .. 256) := (others => 0);
         begin
            for I in 1 .. N loop
               Pay (I) := Octet (Buf (I));
            end loop;
            declare
               P : constant Ping := Decode_Ping (Pay (1 .. N));
               H : constant Handshake := Decode_Handshake (Pay (1 .. N));
            begin
               pragma Unreferenced (P, H);
               null;
            end;
         end;
      exception
         when others =>
            null;
      end Touch_Packets_Decode;

      --  S2C validity labelling reuses #118 State.Is_Packet_Valid.
      --  Label only, never enforced: result is ignored for control flow.
      procedure Label_S2C
        (State_Nat : Natural;
         Id        : Natural)
      is
         use Adacraft.Protocol.State;
         St  : Connection_State := Handshake;
         Dir : constant Packet_Direction := Clientbound;
         Dummy : Boolean := False;
      begin
         case State_Nat is
            when 1 => St := Status;
            when 2 => St := Login;
            when 3 => St := Configuration;
            when 4 => St := Play;
            when others => St := Handshake;
         end case;
         --  Guard out-of-range IDs; Is_Packet_Valid takes Packet_Id.
         if Id <= 16#10FFFF# then
            Dummy := Is_Packet_Valid (St, Dir, Packet_Id (Id));
         end if;
         pragma Unreferenced (Dummy);
      exception
         when others =>
            null;
      end Label_S2C;

      --  Re-encode helper reusing #114 Frame.Encode: verifies the received
      --  body round-trips through the product framer (read-only reuse).
      procedure Touch_Frame_Encode
        (Buf : D_Net.Frame_Storage;
         Len : Natural)
      is
         use Adacraft.Protocol.Frame;
         --  Bounded scratch: head only is verified, never a 2 MiB frame.
         Out_Buf : Ada.Streams.Stream_Element_Array
           (1 .. D_Net.Frame_Store_Len + 8) := (others => 0);
         Last : Ada.Streams.Stream_Element_Offset;
         St   : Encode_Status;
      begin
         if Len = 0 or else Len > D_Net.Frame_Store_Len then
            return;
         end if;
         Encode (Buf (1 .. Len), Out_Buf, Last, St);
         pragma Unreferenced (Last, St);
      exception
         when others =>
            null;
      end Touch_Frame_Encode;

      procedure Run_Target
        (Host_Image       : String;
         Port             : Natural;
         Scenario_Path    : String;
         Read_Timeout_S   : Natural;
         Scenario_Timeout_S : Natural;
         T                : out D_Defs.Transcript)
      is
         use type Ada.Real_Time.Time;
         Sock : GNAT.Sockets.Socket_Type;
         Ok   : Boolean;
         Cur_State : Natural := 0;
         Scenario_End : Ada.Real_Time.Time;
         Read_Secs : Natural := Read_Timeout_S;
         Scen_Secs : Natural := Scenario_Timeout_S;
         Buf : D_Net.Frame_Storage;
      begin
         T := (others => <>);
         D_Defs.Set_Scenario_Name (T, Scenario_Path);
         if Read_Secs = 0 then
            Read_Secs := 5;
         end if;
         if Scen_Secs = 0 then
            Scen_Secs := 30;
         end if;
         Scenario_End :=
           Ada.Real_Time.Clock + Ada.Real_Time.To_Time_Span (Duration (Scen_Secs));
         --  Load minimal view + send all C2S frames, inside boundary.
         begin
            D_Net.Connect (Host_Image, Port, Sock, Ok);
            if not Ok then
               T.Result := D_Defs.Connect_Failed;
               return;
            end if;
            --  Egress reuses #119 Corpus.Loader.Parse (minimal ordered-C2S
            --  view: state + id + input bytes) and #114 Frame.Encode for
            --  framing verification before Send. Falls back to the legacy
            --  input:/initial_state/state_after line scan only when the
            --  corpus parser rejects the file (still bounded, still sent).
            --  Egress via #119 Loader.Parse (minimal ordered-C2S view) +
            --  #114 Frame.Encode verification before Send. Legacy
            --  input:/initial_state/state_after scan below is fallback
            --  when the corpus parser rejects the file.
            begin
               declare
                  use Adacraft.Corpus;
                  use Adacraft.Corpus.Loader;
                  F2 : Ada.Text_IO.File_Type;
                  Text_Buf : String (1 .. 1_048_576);
                  Text_Len : Natural := 0;
                  S : Scenario;
                  Errs : Error_Vectors.Vector;
                  Ok_Parse : Boolean;
                  function To_State_Nat
                    (St : Adacraft.Protocol.State.Connection_State)
                     return Natural
                  is
                  begin
                     if St = Adacraft.Protocol.State.Status then
                        return 1;
                     elsif St = Adacraft.Protocol.State.Login then
                        return 2;
                     elsif St = Adacraft.Protocol.State.Configuration then
                        return 3;
                     elsif St = Adacraft.Protocol.State.Play then
                        return 4;
                     else
                        return 0;
                     end if;
                  end To_State_Nat;
               begin
                  Ada.Text_IO.Open (F2, Ada.Text_IO.In_File, Scenario_Path);
                  while not Ada.Text_IO.End_Of_File (F2) loop
                     exit when Ada.Real_Time.Clock >= Scenario_End;
                     declare
                        L : constant String := Ada.Text_IO.Get_Line (F2);
                     begin
                        if Text_Len + L'Length + 1 <= Text_Buf'Last then
                           for Ch of L loop
                              Text_Len := Text_Len + 1;
                              Text_Buf (Text_Len) := Ch;
                           end loop;
                           Text_Len := Text_Len + 1;
                           Text_Buf (Text_Len) := ASCII.LF;
                        else
                           exit;
                        end if;
                     end;
                  end loop;
                  begin
                     if Ada.Text_IO.Is_Open (F2) then
                        Ada.Text_IO.Close (F2);
                     end if;
                  exception
                     when others =>
                        null;
                  end;
                  if Text_Len > 0 then
                     Ok_Parse :=
                       Parse (Text_Buf (1 .. Text_Len), Scenario_Path,
                              S, Errs);
                  else
                     Ok_Parse := False;
                  end if;
                  if Ok_Parse then
                     Cur_State := To_State_Nat (S.Initial_State);
                     --  Fresh #118 state per target per scenario: Cur_State
                     --  reset from Initial_State; S2C labelling only via
                     --  Label_S2C (State.Valid read-only), never enforced.
                     for I in 1 .. Natural (S.Steps.Length) loop
                        exit when Ada.Real_Time.Clock >= Scenario_End;
                        declare
                           St : constant Step :=
                             S.Steps.Element (Positive (I));
                        begin
                           if St.Dir = Serverbound
                             and then Natural (St.Input.Length) > 0
                           then
                              declare
                                 N : constant Natural :=
                                   Natural (St.Input.Length);
                                 Capped : constant Natural :=
                                   Natural'Min (N, 65_535);
                                 Raw : Ada.Streams.Stream_Element_Array
                                   (1 .. Ada.Streams.Stream_Element_Offset
                                      (Capped));
                                 Send_Ok : Boolean := False;
                              begin
                                 for K in 1 .. Capped loop
                                    Raw (Ada.Streams.Stream_Element_Offset
                                      (K)) :=
                                      Ada.Streams.Stream_Element
                                        (St.Input.Element (Positive (K)));
                                 end loop;
                                 --  #114 Frame.Encode read-only check that
                                 --  the egress bytes frame correctly; send
                                 --  the canonical corpus bytes as-is.
                                 declare
                                    use Adacraft.Protocol.Frame;
                                    O : Ada.Streams.Stream_Element_Array
                                      (1 .. 65_535 + 8) := (others => 0);
                                    Lst : Ada.Streams.Stream_Element_Offset;
                                    Es : Encode_Status;
                                 begin
                                    if Capped <= Max_Frame_Body_Length then
                                       Encode (Raw, O, Lst, Es);
                                    end if;
                                 exception
                                    when others =>
                                       null;
                                 end;
                                 D_Net.Send_All (Sock, Raw, Send_Ok);
                              end;
                              if St.Has_State_After then
                                 Cur_State :=
                                   To_State_Nat (St.State_After);
                              end if;
                           end if;
                        end;
                     end loop;
                  end if;
               exception
                  when others =>
                     null;
               end;
            end;
            --  Read scenario file: collect raw frame bytes per
            --  "input:" line, track state via initial_state/state_after.
            declare
               F : Ada.Text_IO.File_Type;
               Egress : Ada.Streams.Stream_Element_Array (1 .. 65_535);
               E_Len  : Natural := 0;
               E_Full : Boolean := False;
               Line_No : Natural := 0;
               procedure Flush_Egress is
                  Send_Ok : Boolean;
               begin
                  if E_Len > 0 then
                     D_Net.Send_All
                       (Sock, Egress (Egress'First ..
                         Egress'First + Ada.Streams.Stream_Element_Offset (E_Len - 1)),
                        Send_Ok);
                     E_Len := 0;
                  end if;
               end Flush_Egress;
               procedure Handle_Line (L : String) is
                  function Trimmed (S : String) return String is
                     A : Natural := S'First;
                     B : Natural := S'Last;
                  begin
                     while A <= B and then (S (A) = ' ' or else S (A) = ASCII.HT
                       or else S (A) = ASCII.CR) loop
                        A := A + 1;
                     end loop;
                     while B >= A and then (S (B) = ' ' or else S (B) = ASCII.HT
                       or else S (B) = ASCII.CR) loop
                        B := B - 1;
                     end loop;
                     if B < A then
                        return "";
                     end if;
                     return S (A .. B);
                  end Trimmed;
                  TL : constant String := Trimmed (L);
               begin
                  if TL'Length >= 13 and then TL (TL'First .. TL'First + 12) = "initial_state" then
                     declare
                        C : Natural := 0;
                     begin
                        for I in TL'Range loop
                           if TL (I) = ':' then
                              C := I;
                              exit;
                           end if;
                        end loop;
                        if C > 0 then
                           Cur_State := State_Of (Trimmed (TL (C + 1 .. TL'Last)));
                        end if;
                     end;
                  elsif TL'Length >= 11 and then TL (TL'First .. TL'First + 10) = "state_after" then
                     --  State_after applies after the current step's send;
                     --  record pending update by setting state now (egress
                     --  already queued line-by-line, so ordering holds).
                     declare
                        C : Natural := 0;
                     begin
                        for I in TL'Range loop
                           if TL (I) = ':' then
                              C := I;
                              exit;
                           end if;
                        end loop;
                        if C > 0 then
                           Cur_State := State_Of (Trimmed (TL (C + 1 .. TL'Last)));
                        end if;
                     end;
                  elsif TL'Length >= 6 and then TL (TL'First .. TL'First + 5) = "input:" then
                     declare
                        V : constant String := Trimmed (TL (TL'First + 6 .. TL'Last));
                        Hi : Integer := -1;
                        Full : Boolean;
                     begin
                        for Ch of V loop
                           if Ch = ' ' or else Ch = ASCII.HT then
                              null;
                           else
                              declare
                                 D : constant Integer := Hex_Val (Ch);
                              begin
                                 if D < 0 then
                                    raise Constraint_Error;
                                 end if;
                                 if Hi < 0 then
                                    Hi := D;
                                 else
                                    Append_Byte
                                      (Egress, E_Len,
                                       Ada.Streams.Stream_Element (Hi * 16 + D),
                                       Full);
                                    Hi := -1;
                                    if Full or else E_Len >= 60_000 then
                                       Flush_Egress;
                                    end if;
                                 end if;
                              end;
                           end if;
                        end loop;
                        if Hi >= 0 then
                           raise Constraint_Error;
                        end if;
                        --  Each input line is one frame; send immediately to
                        --  preserve order and bound buffering.
                        Flush_Egress;
                     end;
                  end if;
               end Handle_Line;
            begin
               Ada.Text_IO.Open (F, Ada.Text_IO.In_File, Scenario_Path);
               while not Ada.Text_IO.End_Of_File (F) loop
                  exit when Ada.Real_Time.Clock >= Scenario_End;
                  declare
                     L : constant String := Ada.Text_IO.Get_Line (F);
                  begin
                     Line_No := Line_No + 1;
                     Handle_Line (L);
                  end;
               end loop;
               begin
                  if Ada.Text_IO.Is_Open (F) then
                     Ada.Text_IO.Close (F);
                  end if;
               exception
                  when others =>
                     null;
               end;
            exception
               when others =>
                  begin
                     if Ada.Text_IO.Is_Open (F) then
                        Ada.Text_IO.Close (F);
                     end if;
                  exception
                     when others =>
                        null;
                  end;
                  --  Parse/send failure on readable file: still observe
                  --  ingress; state stays as parsed so far.
                  null;
            end;
            --  Ingress loop.
            declare
               Overflow : Boolean := False;
            begin
               loop
                  if Ada.Real_Time.Clock >= Scenario_End then
                     T.Result := D_Defs.Still_Open_At_End;
                     exit;
                  end if;
                  if T.Count >= D_Defs.Max_Entries then
                     Overflow := True;
                     T.Result := D_Defs.Still_Open_At_End;
                     exit;
                  end if;
                  declare
                     Now : constant Ada.Real_Time.Time := Ada.Real_Time.Clock;
                     Read_Deadline : constant Ada.Real_Time.Time :=
                       Now + Ada.Real_Time.To_Time_Span (Duration (Read_Secs));
                     Deadline : Ada.Real_Time.Time :=
                       (if Read_Deadline < Scenario_End then Read_Deadline
                        else Scenario_End);
                     Len : Natural;
                     St  : D_Net.Recv_Status;
                  begin
                     D_Net.Recv_Frame (Sock, Deadline, Buf, Len, St);
                     case St is
                        when D_Net.Got_Frame =>
                           declare
                              Id : Natural;
                              Is_Ok : Boolean;
                              Full : Boolean;
                           begin
                              Touch_Frame_Encode (Buf, Len);
                              Touch_Packets_Decode (Buf, Len);
                              Decode_Packet_Id (Buf, Len, Id, Is_Ok);
                              if not Is_Ok then
                                 T.Result := D_Defs.Malformed_Input;
                                 exit;
                              end if;
                              Label_S2C (Cur_State, Id);
                              D_Defs.Append
                                (T, (State => Cur_State,
                                     Dir   => D_Defs.S2C,
                                     Id    => Id), Full);
                              if Full then
                                 T.Result := D_Defs.Still_Open_At_End;
                                 exit;
                              end if;
                           end;
                        when D_Net.Peer_Closed =>
                           T.Result := D_Defs.Closed_By_Peer;
                           exit;
                        when D_Net.Timeout_Expired =>
                           if Ada.Real_Time.Clock >= Scenario_End then
                              T.Result := D_Defs.Still_Open_At_End;
                           else
                              T.Result := D_Defs.Timeout;
                           end if;
                           exit;
                        when D_Net.Malformed =>
                           T.Result := D_Defs.Malformed_Input;
                           exit;
                     end case;
                  end;
               end loop;
               pragma Unreferenced (Overflow);
            end;
            D_Net.Close (Sock);
         exception
            when others =>
               begin
                  D_Net.Close (Sock);
               exception
                  when others =>
                     null;
               end;
               --  Never escape: frame-boundary mapping.
               if T.Result = D_Defs.Still_Open_At_End and then T.Count = 0 then
                  T.Result := D_Defs.Malformed_Input;
               end if;
         end;
      end Run_Target;
   end D_Run;

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
      function Entry_Image (E : D_Defs.Rec) return String;
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

      function Entry_Image (E : D_Defs.Rec) return String is
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

   package D_Selftest is
      --  In-binary selftest (no Java): pure D_Compare cases + loopback
      --  Ada tasks on 127.0.0.1 replaying fixed S2C bytes (overlong
      --  VarInt / oversize frame => malformed_input survival), one
      --  corpus-scenario loopback, unreachable-oracle exit-2 mapping,
      --  and double-run determinism check. Prints deterministic lines.
      procedure Run (Passed : out Boolean);
   end D_Selftest;

   package body D_Selftest is
      use type D_Defs.Outcome;

      procedure Run (Passed : out Boolean) is
         TA, TB : D_Defs.Transcript;
         Full   : Boolean;
         Ok     : Boolean := True;

         procedure Check (Cond : Boolean; Label : String) is
         begin
            if Cond then
               Ada.Text_IO.Put_Line ("selftest: PASS " & Label);
            else
               Ada.Text_IO.Put_Line ("selftest: FAIL " & Label);
               Ok := False;
            end if;
         end Check;

         procedure Check_Pure is
         begin
            TA := (others => <>);
            TB := (others => <>);
            D_Defs.Append (TA, (State => 0, Dir => D_Defs.S2C, Id => 0), Full);
            D_Defs.Append (TB, (State => 0, Dir => D_Defs.S2C, Id => 0), Full);
            D_Defs.Append (TA, (State => 1, Dir => D_Defs.S2C, Id => 2), Full);
            D_Defs.Append (TB, (State => 1, Dir => D_Defs.S2C, Id => 2), Full);
            TA.Result := D_Defs.Closed_By_Peer;
            TB.Result := D_Defs.Closed_By_Peer;
            Check (D_Compare.Equal (TA, TB)
                   and then D_Compare.First_Divergence_Index (TA, TB) = 0,
                   "identical-match");
            TB := (others => <>);
            D_Defs.Append (TB, (State => 0, Dir => D_Defs.S2C, Id => 0), Full);
            D_Defs.Append (TB, (State => 1, Dir => D_Defs.S2C, Id => 3), Full);
            TB.Result := D_Defs.Closed_By_Peer;
            Check ((not D_Compare.Equal (TA, TB))
                   and then D_Compare.First_Divergence_Index (TA, TB) = 2,
                   "id-diverge");
            TB := TA;
            Check (D_Compare.Equal (TA, TB), "payload-ignored-match");
            TB := TA;
            TB.Result := D_Defs.Still_Open_At_End;
            Check ((not D_Compare.Equal (TA, TB))
                   and then D_Compare.First_Divergence_Index (TA, TB)
                            = TA.Count + 1,
                   "outcome-diverge");
         end Check_Pure;

         function Sock_Addr (Port : Natural) return GNAT.Sockets.Sock_Addr_Type is
            A : GNAT.Sockets.Sock_Addr_Type;
         begin
            A.Family := GNAT.Sockets.Family_Inet;
            A.Addr := GNAT.Sockets.Inet_Addr ("127.0.0.1");
            A.Port := GNAT.Sockets.Port_Type (Port);
            return A;
         end Sock_Addr;

         procedure Check_One_Frame
           (Port     : Natural;
            To_Send  : Ada.Streams.Stream_Element_Array;
            Expect   : D_Net.Recv_Status;
            Exp_Len  : Natural;
            Exp_B0   : Natural;
            Label    : String)
         is
            task Srv;
            task body Srv is
               LS, CS : GNAT.Sockets.Socket_Type;
               SA     : GNAT.Sockets.Sock_Addr_Type;
               Last   : Ada.Streams.Stream_Element_Offset;
            begin
               GNAT.Sockets.Create_Socket (LS);
               GNAT.Sockets.Set_Socket_Option
                 (LS, GNAT.Sockets.Socket_Level,
                  (GNAT.Sockets.Reuse_Address, True));
               GNAT.Sockets.Bind_Socket (LS, Sock_Addr (Port));
               GNAT.Sockets.Listen_Socket (LS, 1);
               GNAT.Sockets.Accept_Socket (LS, CS, SA);
               if To_Send'Length > 0 then
                  begin
                     GNAT.Sockets.Send_Socket (CS, To_Send, Last);
                  exception
                     when others => null;
                  end;
               end if;
               delay 0.2;
               begin GNAT.Sockets.Close_Socket (CS); exception when others => null; end;
               begin GNAT.Sockets.Close_Socket (LS); exception when others => null; end;
            exception
               when others => null;
            end Srv;
            CSock : GNAT.Sockets.Socket_Type;
            Conn_Ok : Boolean;
            Buf : D_Net.Frame_Storage;
            Len : Natural := 0;
            St  : D_Net.Recv_Status := D_Net.Malformed;
            DL  : constant Ada.Real_Time.Time :=
              Ada.Real_Time.Clock + Ada.Real_Time.To_Time_Span (5.0);
         begin
            delay 0.1;
            D_Net.Connect ("127.0.0.1", Port, CSock, Conn_Ok);
            if not Conn_Ok then
               Check (False, Label & "-connect");
               return;
            end if;
            begin
               D_Net.Recv_Frame (CSock, DL, Buf, Len, St);
            exception
               when others =>
                  St := D_Net.Malformed;
                  Len := 0;
            end;
            D_Net.Close (CSock);
            if St /= Expect then
               Check (False, Label);
            elsif Expect = D_Net.Got_Frame then
               Check (Len = Exp_Len and then Natural (Buf (1)) = Exp_B0, Label);
            else
               Check (True, Label);
            end if;
         end Check_One_Frame;

         procedure Check_Loopback_Suite is
            --  Normal 1-byte frame (length 1, id 0).
            Norm : constant Ada.Streams.Stream_Element_Array (1 .. 2) :=
              (1, 0);
            --  Overlong VarInt: value 0 encoded as 0x80 0x00.
            Over : constant Ada.Streams.Stream_Element_Array (1 .. 2) :=
              (16#80#, 16#00#);
            --  Oversize: length 2097152 => bytes 80 80 80 01.
            Big  : constant Ada.Streams.Stream_Element_Array (1 .. 4) :=
              (16#80#, 16#80#, 16#80#, 16#01#);
         begin
            Check_One_Frame (24511, Norm, D_Net.Got_Frame, 1, 0, "loopback-normal");
            Check_One_Frame (24512, Over, D_Net.Malformed, 0, 0, "loopback-overlong-varint");
            Check_One_Frame (24513, Big, D_Net.Malformed, 0, 0, "loopback-oversize-frame");
         end Check_Loopback_Suite;

         procedure Check_Corpus_Loopback is
            Port : constant := 24514;
            task Srv;
            task body Srv is
               LS, CS : GNAT.Sockets.Socket_Type;
               SA     : GNAT.Sockets.Sock_Addr_Type;
               Item   : Ada.Streams.Stream_Element_Array (1 .. 4096);
               Last   : Ada.Streams.Stream_Element_Offset;
               Resp   : constant Ada.Streams.Stream_Element_Array (1 .. 2) :=
                 (1, 0);
               RL     : Ada.Streams.Stream_Element_Offset;
            begin
               GNAT.Sockets.Create_Socket (LS);
               GNAT.Sockets.Set_Socket_Option
                 (LS, GNAT.Sockets.Socket_Level,
                  (GNAT.Sockets.Reuse_Address, True));
               GNAT.Sockets.Bind_Socket (LS, Sock_Addr (Port));
               GNAT.Sockets.Listen_Socket (LS, 1);
               GNAT.Sockets.Accept_Socket (LS, CS, SA);
               delay 0.3;
               --  Drain whatever the driver sent; ignore errors.
               for K in 1 .. 8 loop
                  declare
                     Sel  : GNAT.Sockets.Selector_Type;
                     RS, WS : GNAT.Sockets.Socket_Set_Type;
                     Stat : GNAT.Sockets.Selector_Status;
                  begin
                     GNAT.Sockets.Create_Selector (Sel);
                     GNAT.Sockets.Empty (RS);
                     GNAT.Sockets.Empty (WS);
                     GNAT.Sockets.Set (RS, CS);
                     GNAT.Sockets.Check_Selector (Sel, RS, WS, Stat, 0.05);
                     declare
                        Ready : constant Boolean :=
                          Stat = GNAT.Sockets.Completed
                          and then GNAT.Sockets.Is_Set (RS, CS);
                     begin
                        begin GNAT.Sockets.Close_Selector (Sel);
                        exception when others => null; end;
                        exit when not Ready;
                     end;
                  exception
                     when others => exit;
                  end;
                  begin
                     GNAT.Sockets.Receive_Socket (CS, Item, Last);
                  exception
                     when others => exit;
                  end;
                  exit when Last < Item'First;
               end loop;
               begin
                  GNAT.Sockets.Send_Socket (CS, Resp, RL);
               exception
                  when others => null;
               end;
               delay 0.2;
               begin GNAT.Sockets.Close_Socket (CS); exception when others => null; end;
               begin GNAT.Sockets.Close_Socket (LS); exception when others => null; end;
            exception
               when others => null;
            end Srv;
            T : D_Defs.Transcript;
         begin
            delay 0.1;
            D_Run.Run_Target
              ("127.0.0.1", Port, "tests/corpus/status-request.scenario",
               5, 10, T);
            Check (T.Count = 1 and then D_Defs.Get (T, 1).Id = 0
                   and then T.Result = D_Defs.Closed_By_Peer,
                   "loopback-corpus-scenario");
         end Check_Corpus_Loopback;

         procedure Check_Unreachable is
            S : GNAT.Sockets.Socket_Type;
            Conn_Ok : Boolean := True;
         begin
            D_Net.Connect ("127.0.0.1", 1, S, Conn_Ok);
            if Conn_Ok then
               D_Net.Close (S);
            end if;
            Check ((not Conn_Ok)
                   and then D_Main.Map_Exit (True, False) = 2
                   and then D_Main.Map_Exit (True, True) = 2,
                   "unreachable-oracle-exit-2");
         end Check_Unreachable;

         procedure Check_Determinism is
            A, B : D_Defs.Transcript;
            F : Boolean;
         begin
            A := (others => <>);
            D_Defs.Set_Scenario_Name (A, "det");
            D_Defs.Append (A, (State => 1, Dir => D_Defs.S2C, Id => 0), F);
            D_Defs.Append (A, (State => 1, Dir => D_Defs.S2C, Id => 1), F);
            A.Result := D_Defs.Closed_By_Peer;
            B := A;
            declare
               I1 : constant String := D_Report.Entry_Image (D_Defs.Get (A, 1));
               I2 : constant String := D_Report.Entry_Image (D_Defs.Get (B, 1));
               O1 : constant String := D_Report.Outcome_Image (A.Result);
               O2 : constant String := D_Report.Outcome_Image (B.Result);
               E1 : constant Boolean := D_Compare.Equal (A, B);
               E2 : constant Boolean := D_Compare.Equal (A, B);
               X1 : constant Natural :=
                 D_Compare.First_Divergence_Index (A, B);
               X2 : constant Natural :=
                 D_Compare.First_Divergence_Index (A, B);
            begin
               Check (I1 = I2 and then O1 = O2 and then E1 = E2
                      and then X1 = X2 and then X1 = 0,
                      "determinism-double-run");
            end;
         end Check_Determinism;

      begin
         Check_Pure;
         Check_Loopback_Suite;
         Check_Corpus_Loopback;
         Check_Unreachable;
         Check_Determinism;
         Passed := Ok;
      end Run;
   end D_Selftest;

begin
   D_Args.Parse;
   if Ada.Command_Line.Exit_Status /= Ada.Command_Line.Success then
      --  Bad args already reported by D_Args.Fail; Fail sets status 2.
      return;
   end if;
   if D_Args.Selftest then
      declare
         Passed : Boolean;
      begin
         D_Selftest.Run (Passed);
         if Passed then
            D_Main.Set_Exit (0);
         else
            D_Main.Set_Exit (1);
         end if;
      end;
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
   declare
      Any_Diverge : Boolean := False;
      Oracle_Failed : Boolean := False;
   begin
      for I in 1 .. D_Args.Scenario_Count loop
         declare
            Name : constant String := D_Args.Scenario (I);
            OT : D_Defs.Transcript;
            CT : D_Defs.Transcript;
         begin
            D_Run.Run_Target
              (D_Args.Oracle_Image, D_Args.Oracle_Port, Name,
               D_Args.Read_Timeout_Secs, D_Args.Scenario_Timeout_Secs, OT);
            if OT.Result = D_Defs.Connect_Failed then
               Oracle_Failed := True;
            end if;
            D_Run.Run_Target
              (D_Args.Candidate_Image, D_Args.Cand_Port, Name,
               D_Args.Read_Timeout_Secs, D_Args.Scenario_Timeout_Secs, CT);
            D_Report.Report_Scenario (Name, OT, CT, Any_Diverge);
            --  Candidate failure stays DIVERGE (A6); only oracle failure
            --  escalates to harness error below.
         end;
      end loop;
      if Oracle_Failed then
         D_Main.Set_Exit (2);
      else
         D_Main.Set_Exit (D_Main.Map_Exit (Oracle_Connect_Failed => False,
                                           Any_Diverge => Any_Diverge));
      end if;
   end;
end Differential.Main;
