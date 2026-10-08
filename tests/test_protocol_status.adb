--  Status tests: exact default JSON bytes, escaping, MOTD bound,
--  repeat request, ping echo, short ping, pong-then-close framing.
with Ada.Text_IO;
with Interfaces;
with Adacraft.Protocol.Buffer;
with Adacraft.Protocol.Packets;
with Adacraft.Protocol.Status_Info;
with Adacraft.Protocol.Status_Json;

procedure Test_Protocol_Status is
   package Protocol renames Adacraft.Protocol;
   package Packets renames Adacraft.Protocol.Packets;
   package Info renames Adacraft.Protocol.Status_Info;
   package Json renames Adacraft.Protocol.Status_Json;
   use type Interfaces.Unsigned_64;
   use type Protocol.Status_Kind;

   Failures : Natural := 0;

   procedure Check (Cond : Boolean; Name : String) is
   begin
      if not Cond then
         Ada.Text_IO.Put_Line ("FAIL " & Name);
         Failures := Failures + 1;
      end if;
   end Check;

   function To_Str (W : Protocol.Buffer.Writer) return String is
      S : String (1 .. W.Len) := (others => ' ');
   begin
      for I in 1 .. W.Len loop
         S (I) := Character'Val (Natural (W.Data (I)));
      end loop;
      return S;
   end To_Str;

begin
   --  Exact default JSON bytes.
   declare
      J        : constant String := Json.To_Json (Info.Default_Info);
      Expected : constant String :=
        "{""version"":{""name"":""26.3"",""protocol"":777},"
        & """players"":{""max"":20,""online"":0},"
        & """description"":{""text"":""AdaCraft""},"
        & """enforcesSecureChat"":false}";
   begin
      Check (J = Expected, "exact default JSON bytes");
      Check (J'Length <= Json.Max_Json_Length, "JSON fits bound");
   end;

   --  Escaping: quote, backslash, controls, non-ASCII passthrough.
   declare
      Q : constant String := Json.To_Json (Info.Create ("a""b\c"));
   begin
      Check (Q =
        "{""version"":{""name"":""26.3"",""protocol"":777},"
        & """players"":{""max"":20,""online"":0},"
        & """description"":{""text"":""a\""b\\c""},"
        & """enforcesSecureChat"":false}", "escape quote/backslash");
   end;
   declare
      C : Character := Character'Val (1);
      J : constant String := Json.To_Json (Info.Create ("x" & C & "y"));
   begin
      Check (J =
        "{""version"":{""name"":""26.3"",""protocol"":777},"
        & """players"":{""max"":20,""online"":0},"
        & """description"":{""text"":""x\u0001y""},"
        & """enforcesSecureChat"":false}", "escape control \u00XX");
   end;
   declare
      Nl : constant String := Json.To_Json (Info.Create ("a" & Character'Val (10) & "b"));
   begin
      Check (Nl =
        "{""version"":{""name"":""26.3"",""protocol"":777},"
        & """players"":{""max"":20,""online"":0},"
        & """description"":{""text"":""a\nb""},"
        & """enforcesSecureChat"":false}", "escape newline");
   end;
   declare
      --  Non-ASCII UTF-8 bytes pass through unescaped (2-byte e-acute).
      Raw : constant String :=
        "caf" & Character'Val (16#C3#) & Character'Val (16#A9#);
      J   : constant String := Json.To_Json (Info.Create (Raw));
      Exp : constant String :=
        "{""version"":{""name"":""26.3"",""protocol"":777},"
        & """players"":{""max"":20,""online"":0},"
        & """description"":{""text"":""" & Raw & """},"
        & """enforcesSecureChat"":false}";
   begin
      Check (J = Exp, "non-ASCII passthrough");
   end;

   --  MOTD bound: construction fails beyond 256 bytes.
   declare
      Long  : String (1 .. 257) := (others => 'x');
      Raised : Boolean := False;
   begin
      begin
         declare
            Dummy : constant Info.Status_Info := Info.Create (Long);
            pragma Unreferenced (Dummy);
         begin
            null;
         end;
      exception
         when Info.Invalid_Status_Info =>
            Raised := True;
         when others =>
            Raised := False;
      end;
      Check (Raised, "MOTD bound 257 fails");
   end;
   declare
      Ok256  : String (1 .. 256) := (others => 'y');
      Raised : Boolean := False;
   begin
      begin
         declare
            Dummy : constant Info.Status_Info := Info.Create (Ok256);
            pragma Unreferenced (Dummy);
         begin
            null;
         end;
      exception
         when others =>
            Raised := True;
      end;
      Check (not Raised, "MOTD 256 ok");
   end;

   --  Repeated status request: empty payload accepted each time.
   declare
      Empty : constant Protocol.Octets (1 .. 0) := (others => 0);
   begin
      Check (Packets.Is_Empty_Payload (Empty), "request empty ok");
      Check (Packets.Is_Empty_Payload (Empty), "request repeat ok");
      declare
         One : constant Protocol.Octets := (1 => 16#00#);
      begin
         Check (not Packets.Is_Empty_Payload (One), "request non-empty rejected");
      end;
   end;

   --  Ping echo: exactly 8 bytes round-trip; short payload rejected.
   declare
      W : Protocol.Buffer.Writer (16);
   begin
      Protocol.Buffer.Put_U64 (W, 16#0102030405060708#);
      declare
         P : constant Packets.Ping :=
           Packets.Decode_Ping (W.Data (1 .. W.Len));
      begin
         Check (P.Status = Protocol.Ok
                and then P.Value = 16#0102030405060708#, "ping echo");
      end;
   end;
   declare
      Short : constant Protocol.Octets :=
        (16#01#, 16#02#, 16#03#, 16#04#, 16#05#, 16#06#, 16#07#);
      P : constant Packets.Ping := Packets.Decode_Ping (Short);
      Empty : constant Protocol.Octets (1 .. 0) := (others => 0);
      P2 : constant Packets.Ping := Packets.Decode_Ping (Empty);
   begin
      Check (P.Status = Protocol.Rejected, "short ping rejected");
      Check (P2.Status = Protocol.Rejected, "empty ping rejected");
   end;

   --  Pong-then-close: encoded pong carries echoed value; response encodes id.
   declare
      W : Protocol.Buffer.Writer (32);
   begin
      Packets.Encode_Pong (W, 16#1122334455667788#);
      Check (not W.Failed and then W.Len = 9, "pong length 9");
      Check (W.Data (1) = 16#01#, "pong id 0x01");
      declare
         Back : constant Packets.Ping :=
           Packets.Decode_Ping (W.Data (2 .. W.Len));
      begin
         Check (Back.Status = Protocol.Ok
                and then Back.Value = 16#1122334455667788#, "pong value echo");
      end;
      declare
         S : constant String := To_Str (W);
      begin
         Check (S'Length = 9, "pong-then-close bytes present");
      end;
   end;

   --  Status response encoder emits clientbound 0x00 with JSON string.
   declare
      W : Protocol.Buffer.Writer (2048);
   begin
      Packets.Encode_Status_Response (W);
      Check (not W.Failed and then W.Len > 0, "status response bytes");
      Check (W.Data (1) = 16#00#, "status response id 0x00");
   end;

   if Failures = 0 then
      Ada.Text_IO.Put_Line ("PASS test_protocol_status");
   else
      Ada.Text_IO.Put_Line ("FAILURES test_protocol_status:"
                            & Natural'Image (Failures));
   end if;
end Test_Protocol_Status;
