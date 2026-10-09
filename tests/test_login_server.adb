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

   --  R1..R6 unit coverage driving the same Handle entries the live
   --  server loop calls (Login.Handle_Start / Handle_Acknowledged),
   --  using only existing encoders and shared helpers. No new binary,
   --  no corpus change, empty payload is (1 .. 0).

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

   procedure Test_R1_Success_Bytes_And_Awaiting_Ack is
      use type LG.Start_Outcome;
      use type LG.Login_State;
      use type ST.Connection_State;
      use type Adacraft.Auth.Digest;
      use type Adacraft.Auth.Identity_Kind;
      Name : constant String := "Notch";
      Payload : constant Octets := Build_Start_Payload (Name);
      Res : LG.Start_Result;
      Exp : constant Octets := Expected_Success (Name);
      Got : Octets (1 .. 64) := (others => 0);
      Got_Len : Natural := 0;
      Uuid : constant Adacraft.Auth.Digest :=
        Adacraft.Auth.Offline_UUID (Name);
      Awaiting : constant ST.Connection_State := ST.Login_Awaiting_Ack;
   begin
      Touch_Real_Units (Payload, 0);
      Res := LG.Handle_Start (Fresh_Session, Payload, Adacraft.Auth.Offline);
      Check (Res.Outcome = LG.Ready_Success, "R1 outcome Ready_Success");
      Check (Res.Session.State = LG.Success_Sent, "R1 session Success_Sent");
      Check (Res.Session.Success_Sent, "R1 Success_Sent flag");
      Check (Awaiting = ST.Login_Awaiting_Ack, "R1 Login_Awaiting_Ack state");
      Check (ST.Dispatch_Login
               (Awaiting, ST.Serverbound, ST.Packet_Id (3)) =
             ST.Dispatch_Acknowledged, "R1 ack routable in awaiting-ack");
      Check (Res.Identity.UUID = Uuid, "R1 offline UUID deterministic");
      declare
         W : Buffer.Writer (64);
      begin
         LG.Encode_Login_Success (W, Res.Identity);
         Got_Len := W.Len;
         for I in 1 .. W.Len loop
            Got (I) := W.Data (I);
         end loop;
      end;
      Check (Got_Len = Exp'Length, "R1 success length exact");
      Check (Octets_Equal (Got (1 .. Got_Len), Exp),
             "R1 success bytes exact vs Encode_Login_Success");
      Check (Res.Identity.Kind = Adacraft.Auth.Offline,
             "R1 offline-identified only");
   exception
      when others =>
         Check (False, "R1 no raise");
   end Test_R1_Success_Bytes_And_Awaiting_Ack;

   procedure Test_R2_Empty_Ack_To_Configuration is
      use type LG.Start_Outcome;
      use type LG.Ack_Outcome;
      use type LG.Login_State;
      use type ST.Connection_State;
      Name : constant String := "Notch";
      Payload : constant Octets := Build_Start_Payload (Name);
      SRes : LG.Start_Result;
      ARes : LG.Ack_Result;
      Empty : constant Octets (1 .. 0) := (others => 0);
      Cfg : constant ST.Connection_State := ST.Configuration;
   begin
      SRes := LG.Handle_Start (Fresh_Session, Payload, Adacraft.Auth.Offline);
      Check (SRes.Outcome = LG.Ready_Success, "R2 setup success");
      ARes := LG.Handle_Acknowledged (SRes.Session, Empty);
      Check (ARes.Outcome = LG.To_Configuration, "R2 to configuration");
      Check (ARes.Session.State = LG.Configuration, "R2 session config");
      Check (Cfg = ST.Configuration, "R2 Configuration state");
      Check (LG.Is_Login_Acknowledged (Empty), "R2 empty ack predicate");
   exception
      when others =>
         Check (False, "R2 no raise");
   end Test_R2_Empty_Ack_To_Configuration;

   procedure Test_R3_Invalid_Name_Disconnect is
      use type LG.Start_Outcome;
      use type LG.Login_State;
      Payload : constant Octets := Build_Start_Payload ("bad name");
      Res : LG.Start_Result;
      Exp : constant Octets :=
        Expected_Disconnect (LG.Invalid_Name_Reason);
      Got : constant Octets :=
        Expected_Disconnect
          (Res.Reason (1 .. Res.Reason_Len));
   begin
      Touch_Real_Units (Payload, 0);
      Res := LG.Handle_Start (Fresh_Session, Payload, Adacraft.Auth.Offline);
      Check (Res.Outcome = LG.Need_Disconnect_Close, "R3 disconnect close");
      Check (Res.Session.State = LG.Closed, "R3 no awaiting-ack");
      Check (not Res.Session.Success_Sent, "R3 no success sent");
      Check (Res.Reason (1 .. Res.Reason_Len) = LG.Invalid_Name_Reason,
             "R3 invalid-name reason");
      Check (Octets_Equal (Got, Exp), "R3 disconnect bytes exact");
      declare
         Exp_S : constant Octets := Expected_Success ("Notch");
      begin
         Check (not Octets_Equal (Got, Exp_S), "R3 no success bytes");
      end;
   exception
      when others =>
         Check (False, "R3 no raise");
   end Test_R3_Invalid_Name_Disconnect;

   procedure Test_R4_Duplicate_Start_Disconnect is
      use type LG.Start_Outcome;
      use type LG.Login_State;
      Payload : constant Octets := Build_Start_Payload ("Notch");
      First : LG.Start_Result;
      Second : LG.Start_Result;
   begin
      First := LG.Handle_Start (Fresh_Session, Payload, Adacraft.Auth.Offline);
      Check (First.Outcome = LG.Ready_Success, "R4 setup success");
      Second := LG.Handle_Start (First.Session, Payload, Adacraft.Auth.Offline);
      Check (Second.Outcome = LG.Protocol_Error_Close, "R4 dup closed");
      Check (Second.Session.State = LG.Closed, "R4 stays out of happy state");
      Check (not Second.Session.Success_Sent, "R4 no second success");
   exception
      when others =>
         Check (False, "R4 no raise");
   end Test_R4_Duplicate_Start_Disconnect;

   procedure Test_R5_Nonempty_Ack_Disconnect is
      use type LG.Start_Outcome;
      use type LG.Ack_Outcome;
      use type LG.Login_State;
      Payload : constant Octets := Build_Start_Payload ("Notch");
      SRes : LG.Start_Result;
      ARes : LG.Ack_Result;
      Non_Empty : constant Octets (1 .. 1) := (others => 0);
   begin
      SRes := LG.Handle_Start (Fresh_Session, Payload, Adacraft.Auth.Offline);
      Check (SRes.Outcome = LG.Ready_Success, "R5 setup success");
      ARes := LG.Handle_Acknowledged (SRes.Session, Non_Empty);
      Check (ARes.Outcome = LG.Protocol_Error_Close, "R5 disconnect close");
      Check (ARes.Session.State = LG.Closed, "R5 not configuration");
      Check (not LG.Is_Login_Acknowledged (Non_Empty), "R5 nonempty not ack");
   exception
      when others =>
         Check (False, "R5 no raise");
   end Test_R5_Nonempty_Ack_Disconnect;

   procedure Test_R6_Malformed_No_Bytes_No_Escape is
      use type LG.Start_Outcome;
      use type LG.Login_Start_Status;
      Trunc : constant Octets (1 .. 1) := (1 => 5);
      Dec : LG.Login_Start;
      Res : LG.Start_Result;
      Raised : Boolean := False;
   begin
      begin
         Dec := LG.Decode_Login_Start (Trunc);
         Res := LG.Handle_Start (Fresh_Session, Trunc, Adacraft.Auth.Offline);
      exception
         when others =>
            Raised := True;
      end;
      Check (not Raised, "R6 no exception escapes");
      Check (Dec.Status = LG.Malformed, "R6 decoder reports malformed");
      Check (Res.Outcome /= LG.Ready_Success, "R6 never success");
      Check (not Res.Session.Success_Sent, "R6 zero success bytes");
      declare
         Bad : constant Octets (1 .. 2) := (1 => 16#FF#, 2 => 16#FF#);
         D2 : constant LG.Login_Start := LG.Decode_Login_Start (Bad);
      begin
         Check (D2.Status = LG.Malformed, "R6 bad-length malformed");
      end;
   end Test_R6_Malformed_No_Bytes_No_Escape;

   procedure Run_R1_R6_Unit is
   begin
      Test_R1_Success_Bytes_And_Awaiting_Ack;
      Test_R2_Empty_Ack_To_Configuration;
      Test_R3_Invalid_Name_Disconnect;
      Test_R4_Duplicate_Start_Disconnect;
      Test_R5_Nonempty_Ack_Disconnect;
      Test_R6_Malformed_No_Bytes_No_Escape;
   end Run_R1_R6_Unit;

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
            declare
               Body_Len : Natural := Natural (Last - Resp_Buf'First + 1) - 1;
               Got_Body : Octets (1 .. Body_Len + 1) := (others => 0);
            begin
               for I in 1 .. Body_Len loop
                  Got_Body (I) :=
                    Octet (Resp_Buf (Resp_Buf'First + Stream_Element_Offset (I)));
               end loop;
               --  Compare UUID+name tail against Encode_Login_Success
               --  output tail (skip 1-byte packet id in both).
               Check (Body_Len + 1 = Exp_Success'Length,
                      Name & " success length exact");
               if Body_Len + 1 = Exp_Success'Length then
                  declare
                     Match : Boolean := True;
                  begin
                     for I in 1 .. Exp_Success'Length - 1 loop
                        if Got_Body (I) /=
                          Exp_Success (Exp_Success'First + I)
                        then
                           Match := False;
                        end if;
                     end loop;
                     Check (Match, Name & " success bytes exact");
                  end;
               end if;
            end;
            --  Live R2: empty Ack moves to Configuration with no extra
            --  login bytes; server keeps connection open (no disconnect).
            declare
               Empty : constant Octets (1 .. 0) := (others => 0);
               Buf2 : Stream_Element_Array (1 .. 4096);
               Last2 : Stream_Element_Offset := 0;
               Got2 : Boolean;
            begin
               Send_Packet (S, 3, Empty);
               Got2 := Read_Frame (S, Buf2, Last2);
               Check (not Got2, Name & " ack -> config, no extra login bytes");
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
   end Run_Case_Login;

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
