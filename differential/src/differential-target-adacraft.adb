with Ada.Streams;
with Ada.Unchecked_Deallocation;
with Interfaces;
with GNAT.Sockets;
with Adacraft.Protocol;
with Adacraft.Protocol.Frame;
with Adacraft.Protocol.Packets;
with Adacraft.Protocol.State;
with Adacraft.Protocol.Varnum;
with Differential.Client;
with Differential.Extract;

package body Differential.Target.Adacraft is

   package P renames Standard.Adacraft.Protocol;
   package Frame renames Standard.Adacraft.Protocol.Frame;
   package PS renames Standard.Adacraft.Protocol.State;
   package SU renames Ada.Strings.Unbounded;
   package C renames Differential.Client;
   use type Ada.Streams.Stream_Element_Offset;
   use type Ada.Streams.Stream_Element;
   use type P.Status_Kind;
   use type PS.Result_Kind;
   use type PS.Connection_State;
   use type GNAT.Sockets.Selector_Status;

   subtype SEA is Ada.Streams.Stream_Element_Array;
   subtype SEO is Ada.Streams.Stream_Element_Offset;

   Status_Json : constant String :=
     "{""version"":{""name"":""26.3"",""protocol"":777},"
     & """players"":{""max"":20,""online"":0},"
     & """description"":{""text"":""AdaCraft Differential""}}";
   Login_Reason : constant String :=
     "{""text"":""AdaCraft harness: login not supported""}";

   protected type Stop_Flag is
      procedure Set;
      function Is_Set return Boolean;
   private
      Flag : Boolean := False;
   end Stop_Flag;

   protected body Stop_Flag is
      procedure Set is begin Flag := True; end Set;
      function Is_Set return Boolean is (Flag);
   end Stop_Flag;

   type Dec_Access is access Frame.Decoder_Type;
   procedure Free is new Ada.Unchecked_Deallocation
     (Frame.Decoder_Type, Dec_Access);

   procedure Send_Body (Conn : GNAT.Sockets.Socket_Type; Payload : SEA) is
      Output : SEA (1 .. Payload'Length + 3);
      Last   : SEO;
      St     : Frame.Encode_Status;
      Pos    : SEO;
      Sent   : SEO;
   begin
      Frame.Encode (Payload, Output, Last, St);
      if St /= Frame.Ok then
         return;
      end if;
      Pos := 1;
      while Pos <= Last loop
         GNAT.Sockets.Send_Socket (Conn, Output (Pos .. Last), Sent);
         exit when Sent < Pos;
         Pos := Sent + 1;
      end loop;
   exception
      when GNAT.Sockets.Socket_Error => null;
   end Send_Body;

   function String_Packet (Id : Natural; Text : String) return SEA is
      N      : constant Natural := Text'Length;
      Two    : constant Boolean := N >= 128;
      Len_Sz : constant Natural := (if Two then 2 else 1);
      R      : SEA (1 .. SEO (1 + Len_Sz + N));
      Pos    : SEO := 1;
   begin
      R (1) := Ada.Streams.Stream_Element (Id);
      if Two then
         R (2) := Ada.Streams.Stream_Element (N mod 128 + 128);
         R (3) := Ada.Streams.Stream_Element (N / 128);
         Pos := 3;
      else
         R (2) := Ada.Streams.Stream_Element (N);
         Pos := 2;
      end if;
      for Ch of Text loop
         Pos := Pos + 1;
         R (Pos) := Ada.Streams.Stream_Element (Character'Pos (Ch));
      end loop;
      return R;
   end String_Packet;

   procedure Serve
     (Conn    : GNAT.Sockets.Socket_Type;
      Initial : PS.Connection_State;
      Flag    : in out Stop_Flag)
   is
      use GNAT.Sockets;
      Dec   : Dec_Access := new Frame.Decoder_Type;
      State : PS.Connection_State := Initial;
      Alive : Boolean := True;

      procedure On_Frame (F : Frame.Byte_Array) is
         Body_Bytes : P.Octets (1 .. Natural (F'Length));
         Value      : Interfaces.Integer_32;
         Consumed   : Natural;
         Vs         : P.Varnum.Status_Type;
         Intent     : PS.Handshake_Intent := 0;
         Before     : constant PS.Connection_State := State;
      begin
         if not Alive then
            return;
         end if;
         for I in Body_Bytes'Range loop
            Body_Bytes (I) :=
              P.Octet (F (F'First + SEO (I - 1)));
         end loop;
         P.Varnum.Decode (Body_Bytes, 1, Value, Consumed, Vs);
         if Vs /= P.Varnum.Ok or else Value < 0 then
            Alive := False;
            return;
         end if;
         if Before = PS.Handshake and then Value = 0 then
            declare
               Hs : constant P.Packets.Handshake :=
                 P.Packets.Decode_Handshake
                   (Body_Bytes (Consumed + 1 .. Body_Bytes'Last));
            begin
               if Hs.Status = P.Ok then
                  Intent := PS.Handshake_Intent (Hs.Intent);
               end if;
            end;
         end if;
         declare
            R : constant PS.Transition_Result :=
              PS.Transition
                (Before, (Direction => PS.Serverbound,
                          Id        => PS.Packet_Id (Value),
                          Intent    => Intent));
         begin
            if R.Kind = PS.Rejected then
               Alive := False;
               return;
            end if;
            State := R.Next_State;
         end;
         if Before = PS.Status and then Value = 0 then
            Send_Body (Conn, String_Packet (0, Status_Json));
         elsif Before = PS.Status and then Value = 1
           and then Body_Bytes'Last - Consumed = 8
         then
            declare
               Pong : SEA (1 .. 9);
            begin
               Pong (1) := 1;
               for I in 1 .. 8 loop
                  Pong (SEO (I) + 1) :=
                    Ada.Streams.Stream_Element (Body_Bytes (Consumed + I));
               end loop;
               Send_Body (Conn, Pong);
            end;
         elsif Before = PS.Login and then Value = 0 then
            Send_Body (Conn, String_Packet (0, Login_Reason));
            Alive := False;
         end if;
      end On_Frame;

      R, W : Socket_Set_Type;
      Sel  : Selector_Status;
      Item : SEA (1 .. 4096);
      L    : SEO;
      Fed  : Frame.Feed_Status;
   begin
      while Alive and then not Flag.Is_Set loop
         Empty (R);
         Empty (W);
         Set (R, Conn);
         Check_Selector (R, W, Sel, 0.05);
         if Sel = Completed then
            Receive_Socket (Conn, Item, L);
            if L < Item'First then
               Alive := False;
            else
               Frame.Feed (Dec.all, Item (1 .. L), On_Frame'Access, Fed);
               if Fed = Frame.Framing_Error then
                  Alive := False;
               end if;
            end if;
         end if;
      end loop;
      Free (Dec);
   exception
      when others =>
         Free (Dec);
   end Serve;

   task type Server_Task (Flag : not null access Stop_Flag) is
      entry Start (S : GNAT.Sockets.Socket_Type;
                   Initial : PS.Connection_State);
   end Server_Task;

   task body Server_Task is
      use GNAT.Sockets;
      Srv   : Socket_Type;
      Init  : PS.Connection_State;
      Conn  : Socket_Type;
      Peer  : Sock_Addr_Type;
      R, W  : Socket_Set_Type;
      Sel   : Selector_Status;
      Got   : Boolean := False;
   begin
      accept Start (S : Socket_Type; Initial : PS.Connection_State) do
         Srv := S;
         Init := Initial;
      end Start;
      while not Flag.Is_Set loop
         Empty (R);
         Empty (W);
         Set (R, Srv);
         Check_Selector (R, W, Sel, 0.05);
         if Sel = Completed then
            Accept_Socket (Srv, Conn, Peer);
            Got := True;
            exit;
         end if;
      end loop;
      if Got then
         Serve (Conn, Init, Flag.all);
         begin
            Close_Socket (Conn);
         exception
            when others => null;
         end;
      end if;
   exception
      when others => null;
   end Server_Task;

   overriding function Run_Scenario
     (T        : in out Adacraft_Target;
      Scenario : Differential.Scenario.Projection;
      Timeout  : Duration) return Run_Result
   is
      pragma Unreferenced (T, Timeout);
      use GNAT.Sockets;
      Result : Run_Result;
      Flag   : aliased Stop_Flag;
      Srv    : Socket_Type;
      Addr   : Sock_Addr_Type :=
        (Family => Family_Inet, Addr => Loopback_Inet_Addr, Port => 0);
      Port   : Port_Type;
   begin
      Create_Socket (Srv);
      Bind_Socket (Srv, Addr);
      Listen_Socket (Srv, 1);
      Port := Get_Socket_Name (Srv).Port;
      declare
         Task_Obj : Server_Task (Flag'Access);
         Tcp      : C.Tcp_Transport;
         Ok       : Boolean;
         Output   : C.Run_Output;
      begin
         Task_Obj.Start (Srv, Scenario.Initial_State);
         C.Connect (Tcp, Port, Ok);
         if not Ok then
            Result.Category := Failed;
            Result.Detail := SU.To_Unbounded_String ("connect failed");
         else
            C.Execute (Tcp, Scenario, Output);
            C.Disconnect (Tcp);
            Result.Observation :=
              Differential.Extract.Extract
                (Output, SU.To_String (Scenario.Id));
            if Output.Failed then
               Result.Category := Failed;
               Result.Detail := Output.Detail;
            else
               Result.Category := Completed;
            end if;
         end if;
         Flag.Set;
         while not Task_Obj'Terminated loop
            delay 0.01;
         end loop;
      end;
      Close_Socket (Srv);
      return Result;
   exception
      when others =>
         begin
            Close_Socket (Srv);
         exception
            when others => null;
         end;
         Result.Category := Failed;
         Result.Detail := SU.To_Unbounded_String ("adacraft target error");
         return Result;
   end Run_Scenario;

end Differential.Target.Adacraft;
