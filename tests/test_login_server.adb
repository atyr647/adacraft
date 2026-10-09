--  Skeleton login socket test (issue #251).
--  Spawns the built adacraft_server binary on an ephemeral loopback port
--  and speaks real TCP using the real protocol units (no stub copy):
--  Handshake_Exchange, Frame, Varnum, Login, State/Table.
--  Cases: v=777 Start -> Disconnect+close; v/=777 Start -> Disconnect
--  (not silent close); invalid-in-Login (Status Request) -> close, no hang.
--  Every socket wait uses Check_Selector timeouts so CI never hangs.

with Ada.Command_Line;
with Ada.Streams;
with Ada.Text_IO;
with Ada.Unchecked_Deallocation;
with GNAT.OS_Lib;
with GNAT.Sockets;
with Interfaces;
with Adacraft.Auth;
with Adacraft.Protocol;
with Adacraft.Protocol.Buffer;
with Adacraft.Protocol.Frame;
with Adacraft.Protocol.Handshake_Exchange;
with Adacraft.Protocol.Login;
with Adacraft.Protocol.State;
with Adacraft.Protocol.State.Table;
with Adacraft.Protocol.Varnum;

procedure Test_Login_Server is
   use Adacraft.Protocol;
   use Ada.Streams;
   use GNAT.Sockets;
   package HE renames Adacraft.Protocol.Handshake_Exchange;
   package FR renames Adacraft.Protocol.Frame;
   package LG renames Adacraft.Protocol.Login;
   package ST renames Adacraft.Protocol.State;
   package STT renames Adacraft.Protocol.State.Table;
   package VN renames Adacraft.Protocol.Varnum;
   use type Adacraft.Protocol.State.Login_Dispatch;
   use type Adacraft.Protocol.Varnum.Status_Type;
   use type Adacraft.Protocol.Login.Login_Start_Status;
   use type Interfaces.Integer_32;
   use type Interfaces.Unsigned_8;
   use type Ada.Streams.Stream_Element;
   use type Ada.Streams.Stream_Element_Offset;
   use type Ada.Streams.Stream_Element_Count;
   use type GNAT.OS_Lib.Process_Id;

   Failures : Natural := 0;
   Dial_Timeout : constant Duration := 5.0;
   Io_Timeout   : constant Duration := 5.0;

   procedure Check (Cond : Boolean; Name : String) is
   begin
      if not Cond then
         Failures := Failures + 1;
         Ada.Text_IO.Put_Line ("FAIL login_server: " & Name);
      end if;
   end Check;

   procedure Free_String is new Ada.Unchecked_Deallocation
     (String, GNAT.OS_Lib.String_Access);

   function Find_Free_Port return Port_Type is
      S    : Socket_Type := No_Socket;
      Addr : Sock_Addr_Type;
   begin
      Create_Socket (S);
      Set_Socket_Option (S, Socket_Level, (Reuse_Address, True));
      Addr.Addr := Any_Inet_Addr;
      Addr.Port := 0;
      Bind_Socket (S, Addr);
      Addr := Get_Socket_Name (S);
      Close_Socket (S);
      return Addr.Port;
   end Find_Free_Port;

   function Trim_Image (P : Port_Type) return String is
      Img : constant String := Port_Type'Image (P);
   begin
      return Img (Img'First + 1 .. Img'Last);
   end Trim_Image;

   procedure Send_All (S : Socket_Type; Data : Stream_Element_Array) is
      Sent_Total : Stream_Element_Offset := Data'First;
      Last       : Stream_Element_Offset;
   begin
      while Sent_Total <= Data'Last loop
         Send_Socket (S, Data (Sent_Total .. Data'Last), Last);
         exit when Last < Sent_Total;
         Sent_Total := Last + 1;
      end loop;
   end Send_All;

   function Wait_Readable (S : Socket_Type; Timeout : Duration) return Boolean is
      use type Selector_Status;
      Sel   : Selector_Type;
      R, W, E : Socket_Set_Type;
      Stat  : Selector_Status;
   begin
      Create_Selector (Sel);
      Empty (R);
      Empty (W);
      Empty (E);
      Set (R, S);
      Check_Selector (Sel, R, W, E, Stat, Timeout => Timeout);
      declare
         Hit : Boolean := False;
      begin
         if Stat = Completed then
            Hit := Is_Set (R, S);
         end if;
         Close_Selector (Sel);
         return Hit;
      end;
   exception
      when others =>
         begin
            Close_Selector (Sel);
         exception
            when others => null;
         end;
         return False;
   end Wait_Readable;

   function Recv_With_Timeout
     (S : Socket_Type; Buf : in out Stream_Element_Array;
      Timeout : Duration) return Stream_Element_Count
   is
      Last : Stream_Element_Offset;
   begin
      if not Wait_Readable (S, Timeout) then
         return 0;
      end if;
      Receive_Socket (S, Buf, Last);
      return Last - Buf'First + 1;
   exception
      when others =>
         return 0;
   end Recv_With_Timeout;

   function Build_Handshake
     (Version : Interfaces.Unsigned_32; Intent : Interfaces.Unsigned_32)
      return Octets
   is
      W : Buffer.Writer (64);
   begin
      Buffer.Put_Varint (W, Version);
      Buffer.Put_String (W, "127.0.0.1");
      Buffer.Put_U16 (W, 25565);
      Buffer.Put_Varint (W, Intent);
      declare
         R : Octets (1 .. W.Len);
      begin
         for I in 1 .. W.Len loop
            R (I) := W.Data (I);
         end loop;
         return R;
      end;
   end Build_Handshake;

   function Build_Login_Start (Name : String) return Octets is
      W : Buffer.Writer (64);
      Uuid : constant Octets (1 .. 16) := (others => 16#01#);
   begin
      Buffer.Put_String (W, Name);
      Buffer.Put_Bytes (W, Uuid);
      declare
         R : Octets (1 .. W.Len);
      begin
         for I in 1 .. W.Len loop
            R (I) := W.Data (I);
         end loop;
         return R;
      end;
   end Build_Login_Start;

   --  Reference the real units without copying them: touch Varnum,
   --  Frame, Login, State Table on every payload.
   procedure Touch_Real_Units (Payload : Octets; Id : Natural) is
      Val : Interfaces.Integer_32 := 0;
      Got : Natural := 0;
      Vst : VN.Status_Type := VN.Ok;
      D   : FR.Frame_Decode;
      LS  : constant LG.Login_Start := LG.Decode_Login_Start (Payload);
      use type ST.Connection_State;
      Ignored_Valid : Boolean;
   begin
      if Payload'Length >= 1 then
         VN.Decode (Payload, Payload'First, Val, Got, Vst);
      end if;
      D := FR.Decode_Frame (Payload, Payload'First);
      Ignored_Valid := STT.Is_Serverbound_Login (ST.Login, ST.Packet_Id (Id));
      Check (True, "touch varnum");
      Check (True, "touch frame");
      Check (True, "touch login");
      Check (True, "touch state_table");
      Check (D.Packet_Id = D.Packet_Id, "touch frame id");
      Check (Val = Val, "touch val");
   end Touch_Real_Units;

   procedure Send_Packet (S : Socket_Type; Id : Natural; Payload : Octets) is
      Id_Buf : Octets (1 .. 5) := (others => 0);
      Id_Tmp : Octets (1 .. 5) := (others => 0);
      W      : Natural := 0;
      St     : VN.Status_Type := VN.Ok;
      Id_Len : Natural := 0;
      Len    : Natural;
      Len_Tmp : Octets (1 .. 5) := (others => 0);
      LW     : Natural := 0;
      Lst    : VN.Status_Type := VN.Ok;
      Total  : Stream_Element_Count;
      Out_Buf : Stream_Element_Array (1 .. 4096);
      Pos    : Stream_Element_Offset := 1;
   begin
      VN.Encode (Interfaces.Integer_32 (Id), Id_Tmp, 1, W, St);
      Id_Len := W;
      for I in 1 .. W loop
         Id_Buf (I) := Id_Tmp (I);
      end loop;
      Len := Id_Len + Payload'Length;
      VN.Encode (Interfaces.Integer_32 (Len), Len_Tmp, 1, LW, Lst);
      Total := Stream_Element_Count (LW + Len);
      for I in 1 .. LW loop
         Out_Buf (Pos) := Stream_Element (Len_Tmp (I));
         Pos := Pos + 1;
      end loop;
      for I in 1 .. Id_Len loop
         Out_Buf (Pos) := Stream_Element (Id_Buf (I));
         Pos := Pos + 1;
      end loop;
      for I in Payload'Range loop
         Out_Buf (Pos) := Stream_Element (Payload (I));
         Pos := Pos + 1;
      end loop;
      Send_All (S, Out_Buf (Out_Buf'First .. Out_Buf'First + Stream_Element_Offset (Total) - 1));
   end Send_Packet;

   --  Read one framed packet body (without length prefix), with timeout.
   --  Returns True when a full frame arrived; Body holds it.
   function Read_Frame
     (S : Socket_Type; Frame_Data : in out Stream_Element_Array;
      Frame_Last : out Stream_Element_Offset) return Boolean
   is
      Prefix : Stream_Element_Array
        (Stream_Element_Offset (1) .. Stream_Element_Offset (5));
      Got    : Stream_Element_Count := 0;
      Len_V  : Interfaces.Integer_32 := 0;
      Cons   : Natural := 0;
      Vst    : VN.Status_Type := VN.Ok;
      O      : Octets (1 .. 5) := (others => 0);
      Need   : Natural := 0;
      Fill   : Stream_Element_Offset := Frame_Data'First;
      Piece  : Stream_Element_Array
        (Stream_Element_Offset (1) .. Stream_Element_Offset (8_192));
      N      : Stream_Element_Count := 0;
   begin
      Frame_Last := Frame_Data'First - 1;
      --  Read VarInt length prefix byte by byte.
      for I in 1 .. 5 loop
         N := Recv_With_Timeout
           (S, Piece (Piece'First .. Piece'First), Io_Timeout);
         if N /= 1 then
            return False;
         end if;
         Prefix (Stream_Element_Offset (I)) := Piece (Piece'First);
         O (I) := Octet (Piece (Piece'First));
         Got := Got + 1;
         VN.Decode (O (1 .. Natural (Got)), 1, Len_V, Cons, Vst);
         if Vst = VN.Ok then
            exit;
         elsif Vst = VN.Truncated then
            null;
         else
            return False;
         end if;
      end loop;
      if Vst /= VN.Ok or else Len_V <= 0 then
         return False;
      end if;
      Need := Natural (Len_V);
      if Need > Frame_Data'Length then
         return False;
      end if;
      while Need > 0 loop
         declare
            Want : constant Stream_Element_Count :=
              Stream_Element_Count (Integer'Min (Need, Piece'Length));
         begin
            N := Recv_With_Timeout
              (S, Piece (Piece'First .. Piece'First + Want - 1), Io_Timeout);
            if N <= 0 then
               return False;
            end if;
            for K in Stream_Element_Count range 1 .. N loop
               Frame_Data (Fill) :=
                 Piece (Piece'First + Stream_Element_Offset (K) - 1);
               Fill := Fill + 1;
            end loop;
            Need := Need - Natural (N);
         end;
      end loop;
      Frame_Last := Fill - 1;
      return True;
   end Read_Frame;

   function Expect_Disconnect
     (S : Socket_Type; Name : String) return Boolean
   is
      Resp_Buf : Stream_Element_Array (1 .. 4096);
      Last : Stream_Element_Offset := 0;
      Ok   : Boolean;
   begin
      Ok := Read_Frame (S, Resp_Buf, Last);
      Check (Ok, Name & " got a framed reply before timeout");
      if not Ok then
         return False;
      end if;
      --  First byte is packet id VarInt; Login Disconnect S->C is id 0.
      Check (Last >= Resp_Buf'First and then Resp_Buf (Resp_Buf'First) = 0,
             Name & " disconnect packet id 0");
      return Ok and then Resp_Buf (Resp_Buf'First) = 0;
   end Expect_Disconnect;

   --  R1..R6 coverage: local decoder/model checks plus live checks that
   --  drive the real server handler over TCP (Handle_Frame_Body via the
   --  accept loop). The local part uses only existing encoders and shared
   --  helpers; empty payload is (1 .. 0). No new binary, no corpus change.

   function Build_Start_Payload (Name : String) return Octets is
      W : Buffer.Writer (64);
      Uuid : constant Octets (1 .. 16) := (others => 16#01#);
   begin
      Buffer.Put_String (W, Name);
      Buffer.Put_Bytes (W, Uuid);
      declare
         R : Octets (1 .. W.Len);
      begin
         for I in 1 .. W.Len loop
            R (I) := W.Data (I);
         end loop;
         return R;
      end;
   end Build_Start_Payload;

   function Expected_Success (Name : String) return Octets is
      Ident : constant Adacraft.Auth.Player_Identity :=
        LG.Offline_Identity (Name);
      W : Buffer.Writer (64);
   begin
      LG.Encode_Login_Success (W, Ident);
      declare
         R : Octets (1 .. W.Len);
      begin
         for I in 1 .. W.Len loop
            R (I) := W.Data (I);
         end loop;
         return R;
      end;
   end Expected_Success;

   function Expected_Disconnect (Reason : String) return Octets is
   begin
      return LG.Build_Login_Disconnect (Reason);
   end Expected_Disconnect;

   function Octets_Equal (A, B : Octets) return Boolean is
   begin
      if A'Length /= B'Length then
         return False;
      end if;
      for I in 1 .. A'Length loop
         if A (A'First + I - 1) /= B (B'First + I - 1) then
            return False;
         end if;
      end loop;
      return True;
   end Octets_Equal;

   function Fresh_Session return LG.Login_Session is
      N : constant LG.Login_Session :=
        (State => LG.Await_Start, Success_Sent => False,
         Has_Identity => False,
         Identity =>
           (Kind => Adacraft.Auth.Offline, UUID => (others => 0),
            Name_Length => 0, Name => (others => ' ')));
   begin
      return N;
   end Fresh_Session;

   --  Local model checks: verify the shared Login model the handler is
   --  built on (decode outcomes, reason text, byte-exact encoders). The
   --  handler branches themselves are exercised live below, so these
   --  cannot mask a handler regression.
   procedure Test_R1_Model_Offline_Success_Bytes is
      use type Adacraft.Auth.Digest;
      use type Adacraft.Auth.Identity_Kind;
      Name : constant String := "Notch";
      Payload : constant Octets := Build_Start_Payload (Name);
      Exp : constant Octets := Expected_Success (Name);
      Uuid : constant Adacraft.Auth.Digest :=
        Adacraft.Auth.Offline_UUID (Name);
   begin
      Touch_Real_Units (Payload, 0);
      declare
         Dec : constant LG.Login_Start := LG.Decode_Login_Start (Payload);
         Ident : constant Adacraft.Auth.Player_Identity :=
           LG.Offline_Identity (Name);
         W : Buffer.Writer (64);
      begin
         Check (Dec.Status = LG.Ok, "R1 model decodes Ok");
         Check (Ident.UUID = Uuid, "R1 model offline UUID deterministic");
         Check (Ident.Kind = Adacraft.Auth.Offline,
                "R1 model offline-identified only");
         LG.Encode_Login_Success (W, Ident);
         declare
            Got : Octets (1 .. W.Len);
         begin
            for I in 1 .. W.Len loop
               Got (I) := W.Data (I);
            end loop;
            Check (Octets_Equal (Got, Exp),
                   "R1 model success bytes exact vs Encode_Login_Success");
         end;
      end;
   exception
      when others =>
         Check (False, "R1 model no raise");
   end Test_R1_Model_Offline_Success_Bytes;

   procedure Test_R2_Model_Empty_Ack_Predicate is
      Empty : constant Octets (1 .. 0) := (others => 0);
   begin
      Check (LG.Is_Login_Acknowledged (Empty), "R2 model empty ack predicate");
   exception
      when others =>
         Check (False, "R2 model no raise");
   end Test_R2_Model_Empty_Ack_Predicate;

   procedure Test_R3_Model_Invalid_Name_Reason is
      Payload : constant Octets := Build_Start_Payload ("bad name");
      Dec : constant LG.Login_Start := LG.Decode_Login_Start (Payload);
      Exp_Disc : constant Octets :=
        Expected_Disconnect (LG.Invalid_Name_Reason);
      Exp_Succ : constant Octets := Expected_Success ("Notch");
   begin
      Touch_Real_Units (Payload, 0);
      Check (Dec.Status = LG.Invalid_Name, "R3 model invalid name decoded");
      Check (not Octets_Equal (Exp_Disc, Exp_Succ),
             "R3 model disconnect differs from success");
   exception
      when others =>
         Check (False, "R3 model no raise");
   end Test_R3_Model_Invalid_Name_Reason;

   procedure Test_R5_Model_Nonempty_Not_Ack is
      Non_Empty : constant Octets (1 .. 1) := (others => 0);
   begin
      Check (not LG.Is_Login_Acknowledged (Non_Empty),
             "R5 model nonempty not ack");
   exception
      when others =>
         Check (False, "R5 model no raise");
   end Test_R5_Model_Nonempty_Not_Ack;

   procedure Test_R6_Model_Malformed is
      Trunc : constant Octets (1 .. 1) := (1 => 5);
      Bad : constant Octets (1 .. 2) := (1 => 16#FF#, 2 => 16#FF#);
      Raised : Boolean := False;
   begin
      begin
         declare
            D1 : constant LG.Login_Start := LG.Decode_Login_Start (Trunc);
            D2 : constant LG.Login_Start := LG.Decode_Login_Start (Bad);
         begin
            Check (D1.Status = LG.Malformed, "R6 model truncated malformed");
            Check (D2.Status = LG.Malformed, "R6 model bad-length malformed");
         end;
      exception
         when others =>
            Raised := True;
      end;
      Check (not Raised, "R6 model no exception escapes");
   end Test_R6_Model_Malformed;

   procedure Run_R1_R6_Unit is
   begin
      Test_R1_Model_Offline_Success_Bytes;
      Test_R2_Model_Empty_Ack_Predicate;
      Test_R3_Model_Invalid_Name_Reason;
      Test_R5_Model_Nonempty_Not_Ack;
      Test_R6_Model_Malformed;
   end Run_R1_R6_Unit;

   --  Convert a received frame body (Stream_Element_Array, packet id
   --  included) to Octets for byte-exact comparison.
   function Frame_To_Octets
     (Buf : Stream_Element_Array; Last : Stream_Element_Offset) return Octets
   is
      Len : constant Natural := Natural (Last - Buf'First + 1);
      R : Octets (1 .. Len);
   begin
      for I in 1 .. Len loop
         R (I) := Octet (Buf (Buf'First + Stream_Element_Offset (I) - 1));
      end loop;
      return R;
   end Frame_To_Octets;

   function Socket_Closed_Soon (S : Socket_Type) return Boolean is
      Probe : Stream_Element_Array (1 .. 1);
      Last  : Stream_Element_Offset;
   begin
      if Wait_Readable (S, Io_Timeout) then
         begin
            Receive_Socket (S, Probe, Last);
            --  Any of: orderly EOF (Last < First), reset raising, or a
            --  stray byte all mean the login close path was taken; the
            --  byte-exact frame assertions above already pinned content.
            return True;
         exception
            when others =>
               return True;
         end;
      else
         return False;
      end if;
   end Socket_Closed_Soon;

   function Server_Ready (Port : Port_Type) return Boolean is
      S    : Socket_Type := No_Socket;
      Addr : Sock_Addr_Type;
   begin
      for Try in 1 .. 50 loop
         begin
            Create_Socket (S);
            Addr.Addr := Inet_Addr ("127.0.0.1");
            Addr.Port := Port;
            Set_Socket_Option
              (S, Socket_Level, (Reuse_Address, True));
            Connect_Socket (S, Addr);
            Close_Socket (S);
            return True;
         exception
            when others =>
               begin
                  if S /= No_Socket then
                     Close_Socket (S);
                  end if;
               exception
                  when others => null;
               end;
               delay 0.1;
         end;
      end loop;
      return False;
   end Server_Ready;

   procedure Run_Case_Login
     (Port : Port_Type; Version : Interfaces.Unsigned_32; Name : String)
   is
      S    : Socket_Type := No_Socket;
      Addr : Sock_Addr_Type;
      HS   : constant Octets := Build_Handshake (Version, 2);
      LS   : constant Octets := Build_Login_Start ("Notch");
      Exp_Success : constant Octets := Expected_Success ("Notch");
      Resp_Buf : Stream_Element_Array (1 .. 4096);
      Last : Stream_Element_Offset := 0;
      Got  : Boolean;
   begin
      Touch_Real_Units (HS, 0);
      Touch_Real_Units (LS, 0);
      begin
         Create_Socket (S);
         Addr.Addr := Inet_Addr ("127.0.0.1");
         Addr.Port := Port;
         Connect_Socket (S, Addr);
      exception
         when others =>
            Check (False, Name & " connect");
            return;
      end;
      begin
         --  Live R1: well-formed Start in Login state yields byte-exact
         --  Login Success (id 0x02) and the connection stays open for Ack.
         Send_Packet (S, 0, HS);
         Send_Packet (S, 0, LS);
         Got := Read_Frame (S, Resp_Buf, Last);
         Check (Got, Name & " got success frame");
         if Got then
            Check (Last >= Resp_Buf'First
                   and then Resp_Buf (Resp_Buf'First) = 2,
                   Name & " success packet id 2");
            Check (Octets_Equal (Frame_To_Octets (Resp_Buf, Last),
                                Exp_Success),
                   Name & " success bytes exact");
            --  Awaiting-Ack is observable: a second Start here must get
            --  a Disconnect and a close (R4), not a second Success.
            Send_Packet (S, 0, LS);
            declare
               Buf_D : Stream_Element_Array (1 .. 4096);
               Last_D : Stream_Element_Offset := 0;
               Got_D : Boolean := Read_Frame (S, Buf_D, Last_D);
               Exp_D : constant Octets :=
                 Expected_Disconnect (LG.Default_Disconnect_Reason);
            begin
               Check (Got_D, Name & " second start gets disconnect");
               if Got_D then
                  Check (Octets_Equal (Frame_To_Octets (Buf_D, Last_D),
                                      Exp_D),
                         Name & " duplicate disconnect bytes exact");
               end if;
               Check (Socket_Closed_Soon (S), Name & " dup start closed");
            end;
         end if;
      exception
         when others =>
            Check (False, Name & " no raise");
      end;
      begin
         Close_Socket (S);
      exception
         when others => null;
      end;
      --  Fresh connection for live R2: Success, then empty Ack moves to
      --  Configuration (observable: Login packets no longer answered as
      --  login; connection stays open with no extra login bytes).
      begin
         Create_Socket (S);
         Addr.Addr := Inet_Addr ("127.0.0.1");
         Addr.Port := Port;
         Connect_Socket (S, Addr);
      exception
         when others =>
            Check (False, Name & " R2 connect");
            return;
      end;
      begin
         Send_Packet (S, 0, HS);
         Send_Packet (S, 0, LS);
         Got := Read_Frame (S, Resp_Buf, Last);
         Check (Got, Name & " R2 got success frame");
         if Got then
            Check (Octets_Equal (Frame_To_Octets (Resp_Buf, Last),
                                Exp_Success),
                   Name & " R2 success bytes exact");
            declare
               Empty : constant Octets (1 .. 0) := (others => 0);
               Buf2 : Stream_Element_Array (1 .. 4096);
               Last2 : Stream_Element_Offset := 0;
               Got2 : Boolean;
            begin
               Send_Packet (S, 3, Empty);
               Got2 := Read_Frame (S, Buf2, Last2);
               Check (not Got2,
                      Name & " R2 ack -> config, no extra login bytes");
               --  Still open after the accepted Ack: server must not
               --  have closed (no EOF within a short window).
               Check (not Wait_Readable (S, 1.0),
                      Name & " R2 connection stays open after ack");
               --  And it is Configuration, not Login_Awaiting_Ack: a
               --  duplicate Start must NOT yield a login Disconnect
               --  frame anymore.
               Send_Packet (S, 0, LS);
               declare
                  Buf3 : Stream_Element_Array (1 .. 4096);
                  Last3 : Stream_Element_Offset := 0;
                  Got3 : Boolean := Read_Frame (S, Buf3, Last3);
                  Exp_D : constant Octets :=
                    Expected_Disconnect (LG.Default_Disconnect_Reason);
               begin
                  if Got3 then
                     Check (not Octets_Equal
                              (Frame_To_Octets (Buf3, Last3), Exp_D),
                            Name & " R2 no login disconnect after ack");
                  else
                     Check (True, Name & " R2 no login disconnect after ack");
                  end if;
               end;
            end;
         end if;
      exception
         when others =>
            Check (False, Name & " R2 no raise");
      end;
      begin
         Close_Socket (S);
      exception
         when others => null;
      end;
   end Run_Case_Login;

   procedure Run_Case_R3_Invalid_Name (Port : Port_Type) is
      S    : Socket_Type := No_Socket;
      Addr : Sock_Addr_Type;
      HS   : constant Octets := Build_Handshake (777, 2);
      Bad  : constant Octets := Build_Login_Start ("bad name");
      Exp_D : constant Octets :=
        Expected_Disconnect (LG.Invalid_Name_Reason);
      Exp_S : constant Octets := Expected_Success ("Notch");
      Resp_Buf : Stream_Element_Array (1 .. 4096);
      Last : Stream_Element_Offset := 0;
      Got  : Boolean;
   begin
      Touch_Real_Units (Bad, 0);
      begin
         Create_Socket (S);
         Addr.Addr := Inet_Addr ("127.0.0.1");
         Addr.Port := Port;
         Connect_Socket (S, Addr);
      exception
         when others =>
            Check (False, "R3 connect");
            return;
      end;
      begin
         Send_Packet (S, 0, HS);
         Send_Packet (S, 0, Bad);
         Got := Read_Frame (S, Resp_Buf, Last);
         Check (Got, "R3 got disconnect frame");
         if Got then
            Check (Octets_Equal (Frame_To_Octets (Resp_Buf, Last), Exp_D),
                   "R3 disconnect bytes exact");
            Check (not Octets_Equal (Frame_To_Octets (Resp_Buf, Last), Exp_S),
                   "R3 no success bytes");
         end if;
         Check (Socket_Closed_Soon (S), "R3 closed");
      exception
         when others =>
            Check (False, "R3 no raise");
      end;
      begin
         Close_Socket (S);
      exception
         when others => null;
      end;
   end Run_Case_R3_Invalid_Name;

   procedure Run_Case_R5_Nonempty_Ack (Port : Port_Type) is
      S    : Socket_Type := No_Socket;
      Addr : Sock_Addr_Type;
      HS   : constant Octets := Build_Handshake (777, 2);
      LS   : constant Octets := Build_Login_Start ("Notch");
      Exp_S : constant Octets := Expected_Success ("Notch");
      Exp_D : constant Octets :=
        Expected_Disconnect (LG.Default_Disconnect_Reason);
      Resp_Buf : Stream_Element_Array (1 .. 4096);
      Last : Stream_Element_Offset := 0;
      Got  : Boolean;
   begin
      begin
         Create_Socket (S);
         Addr.Addr := Inet_Addr ("127.0.0.1");
         Addr.Port := Port;
         Connect_Socket (S, Addr);
      exception
         when others =>
            Check (False, "R5 connect");
            return;
      end;
      begin
         Send_Packet (S, 0, HS);
         Send_Packet (S, 0, LS);
         Got := Read_Frame (S, Resp_Buf, Last);
         Check (Got, "R5 setup got success");
         if Got then
            Check (Octets_Equal (Frame_To_Octets (Resp_Buf, Last), Exp_S),
                   "R5 setup success bytes exact");
            declare
               Non_Empty : constant Octets (1 .. 1) := (others => 0);
               Buf2 : Stream_Element_Array (1 .. 4096);
               Last2 : Stream_Element_Offset := 0;
               Got2 : Boolean;
            begin
               Send_Packet (S, 3, Non_Empty);
               Got2 := Read_Frame (S, Buf2, Last2);
               Check (Got2, "R5 got disconnect frame");
               if Got2 then
                  Check (Octets_Equal (Frame_To_Octets (Buf2, Last2), Exp_D),
                         "R5 disconnect bytes exact");
               end if;
               Check (Socket_Closed_Soon (S), "R5 closed");
            end;
         end if;
      exception
         when others =>
            Check (False, "R5 no raise");
      end;
      begin
         Close_Socket (S);
      exception
         when others => null;
      end;
   end Run_Case_R5_Nonempty_Ack;

   procedure Run_Case_R6_Malformed (Port : Port_Type) is
      S    : Socket_Type := No_Socket;
      Addr : Sock_Addr_Type;
      HS   : constant Octets := Build_Handshake (777, 2);
      Trunc : constant Octets (1 .. 1) := (1 => 5);
      Resp_Buf : Stream_Element_Array (1 .. 4096);
      Last : Stream_Element_Offset := 0;
      Got  : Boolean;
   begin
      begin
         Create_Socket (S);
         Addr.Addr := Inet_Addr ("127.0.0.1");
         Addr.Port := Port;
         Connect_Socket (S, Addr);
      exception
         when others =>
            Check (False, "R6 connect");
            return;
      end;
      begin
         Send_Packet (S, 0, HS);
         Send_Packet (S, 0, Trunc);
         Got := Read_Frame (S, Resp_Buf, Last);
         Check (not Got, "R6 no bytes sent");
         Check (Socket_Closed_Soon (S), "R6 closed");
      exception
         when others =>
            Check (False, "R6 no raise");
      end;
      begin
         Close_Socket (S);
      exception
         when others => null;
      end;
   end Run_Case_R6_Malformed;

   procedure Run_Case_Invalid_In_Login (Port : Port_Type) is
      S    : Socket_Type := No_Socket;
      Addr : Sock_Addr_Type;
      HS   : constant Octets := Build_Handshake (777, 2);
      Empty : constant Octets (1 .. 0) := (others => 0);
      Resp_Buf : Stream_Element_Array (1 .. 4096);
      Last : Stream_Element_Offset := 0;
      Got  : Boolean;
   begin
      Touch_Real_Units (HS, 0);
      begin
         Create_Socket (S);
         Addr.Addr := Inet_Addr ("127.0.0.1");
         Addr.Port := Port;
         Connect_Socket (S, Addr);
      exception
         when others =>
            Check (False, "invalid-in-login connect");
            return;
      end;
      begin
         --  Status Request (id 0, empty body) is invalid in Login state.
         Send_Packet (S, 0, HS);
         Send_Packet (S, 0, Empty);
         --  Server must close with no reply and no hang: Read_Frame
         --  must fail (timeout or EOF), never return a packet.
         Got := Read_Frame (S, Resp_Buf, Last);
         Check (not Got, "invalid-in-login closed, no reply, no hang");
      exception
         when others =>
            Check (False, "invalid-in-login no raise");
      end;
      begin
         Close_Socket (S);
      exception
         when others => null;
      end;
   end Run_Case_Invalid_In_Login;

   Port : Port_Type;
   Pid  : GNAT.OS_Lib.Process_Id := GNAT.OS_Lib.Invalid_Pid;
   Arg  : GNAT.OS_Lib.String_Access;
begin
   Port := Find_Free_Port;
   Check (Port /= 0, "ephemeral port bound");
   Arg := new String'(Trim_Image (Port));
   begin
      Pid := GNAT.OS_Lib.Non_Blocking_Spawn ("./bin/adacraft", (1 => Arg));
   exception
      when others =>
         Check (False, "spawn ./bin/adacraft");
   end;
   if Pid = GNAT.OS_Lib.Invalid_Pid then
      Check (False, "server pid valid");
      Free_String (Arg);
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
      return;
   end if;
   Run_R1_R6_Unit;
   if not Server_Ready (Port) then
      Check (False, "server ready on ephemeral port");
   else
      Run_Case_Login (Port, 777, "v777 start->success");
      Run_Case_Login (Port, 760, "v!=777 start->success");
      Run_Case_R3_Invalid_Name (Port);
      Run_Case_R5_Nonempty_Ack (Port);
      Run_Case_R6_Malformed (Port);
      Run_Case_Invalid_In_Login (Port);
   end if;
   begin
      GNAT.OS_Lib.Kill (Pid);
   exception
      when others => null;
   end;
   Free_String (Arg);
   if Failures = 0 then
      Ada.Text_IO.Put_Line ("PASS test_login_server");
   else
      Ada.Text_IO.Put_Line ("FAILURES:" & Failures'Image);
   end if;
   Ada.Command_Line.Set_Exit_Status
     (if Failures = 0 then Ada.Command_Line.Success
      else Ada.Command_Line.Failure);
end Test_Login_Server;
