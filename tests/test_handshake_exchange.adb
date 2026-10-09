with Ada.Command_Line;
with Ada.Text_IO;
with Interfaces;
with Adacraft.Protocol;
with Adacraft.Protocol.Buffer;
with Adacraft.Protocol.State;
with Adacraft.Protocol.Handshake_Exchange;

procedure Test_Handshake_Exchange is
   use Adacraft.Protocol;
   package HE renames Adacraft.Protocol.Handshake_Exchange;
   package S renames Adacraft.Protocol.State;
   use type S.Connection_State;
   use type HE.Handle_Result;

   Failures : Natural := 0;

   procedure Check (Cond : Boolean; Name : String) is
   begin
      if not Cond then
         Failures := Failures + 1;
         Ada.Text_IO.Put_Line ("FAIL: " & Name);
      end if;
   end Check;

   function Build (Version : Interfaces.Unsigned_32; Addr : String;
                   Port : Interfaces.Unsigned_16;
                   Intent : Interfaces.Unsigned_32) return Octets
   is
      W : Buffer.Writer (1024);
   begin
      Buffer.Put_Varint (W, Version);
      Buffer.Put_String (W, Addr);
      Buffer.Put_U16 (W, Port);
      Buffer.Put_Varint (W, Intent);
      declare
         R : Octets (1 .. W.Len);
      begin
         for I in 1 .. W.Len loop
            R (I) := W.Data (I);
         end loop;
         return R;
      end;
   end Build;

   procedure Case_Intent (Intent : Interfaces.Unsigned_32;
                          Expect : HE.Handle_Result;
                          Expect_State : S.Connection_State;
                          Name : String)
   is
      P : constant Octets := Build (777, "localhost", 25565, Intent);
      Cur : S.Connection_State := S.Handshake;
      Stored : HE.Connection_Data;
      Res : HE.Handle_Result;
   begin
      HE.Handle (0, P, Cur, Stored, Res);
      Check (Res = Expect, Name & " result");
      Check (Cur = Expect_State, Name & " state");
   end Case_Intent;

begin
   Case_Intent (1, HE.Accepted_Status, S.Status, "intent 1");
   Case_Intent (2, HE.Accepted_Login, S.Login, "intent 2");
   Case_Intent (3, HE.Accepted_Login, S.Login, "intent 3");
   Case_Intent (0, HE.Rejected_No_Change, S.Handshake, "intent 0 invalid");
   Case_Intent (4, HE.Rejected_No_Change, S.Handshake, "intent 4 invalid");
   Case_Intent (255, HE.Rejected_No_Change, S.Handshake, "intent 255 invalid");

   --  Overlong VarInt (6 continuation bytes for version).
   declare
      P : constant Octets (1 .. 8) :=
        (16#80#, 16#80#, 16#80#, 16#80#, 16#80#, 16#01#,
         16#00#, 16#00#);
      Cur : S.Connection_State := S.Handshake;
      Stored : HE.Connection_Data;
      Res : HE.Handle_Result;
   begin
      HE.Handle (0, P, Cur, Stored, Res);
      Check (Res = HE.Rejected_No_Change, "overlong varint result");
      Check (Cur = S.Handshake, "overlong varint state");
   end;

   --  256-char address.
   declare
      Long_Addr : String (1 .. 256) := (others => 'a');
      P : constant Octets := Build (777, Long_Addr, 25565, 1);
      Cur : S.Connection_State := S.Handshake;
      Stored : HE.Connection_Data;
      Res : HE.Handle_Result;
   begin
      HE.Handle (0, P, Cur, Stored, Res);
      Check (Res = HE.Rejected_No_Change, "256-char address result");
      Check (Cur = S.Handshake, "256-char address state");
   end;

   --  Truncated payload (drop last byte).
   declare
      Full : constant Octets := Build (777, "localhost", 25565, 1);
      P : constant Octets := Full (Full'First .. Full'Last - 1);
      Cur : S.Connection_State := S.Handshake;
      Stored : HE.Connection_Data;
      Res : HE.Handle_Result;
   begin
      HE.Handle (0, P, Cur, Stored, Res);
      Check (Res = HE.Rejected_No_Change, "truncated result");
      Check (Cur = S.Handshake, "truncated state");
   end;

   --  Trailing byte.
   declare
      Full : constant Octets := Build (777, "localhost", 25565, 1);
      P : Octets (1 .. Full'Length + 1);
      Cur : S.Connection_State := S.Handshake;
      Stored : HE.Connection_Data;
      Res : HE.Handle_Result;
   begin
      for I in Full'Range loop
         P (I - Full'First + 1) := Full (I);
      end loop;
      P (P'Last) := 16#00#;
      HE.Handle (0, P, Cur, Stored, Res);
      Check (Res = HE.Rejected_No_Change, "trailing result");
      Check (Cur = S.Handshake, "trailing state");
   end;

   --  Wrong packet ID.
   declare
      P : constant Octets := Build (777, "mc.example.com", 25565, 1);
      Cur : S.Connection_State := S.Handshake;
      Stored : HE.Connection_Data;
      Res : HE.Handle_Result;
   begin
      HE.Handle (1, P, Cur, Stored, Res);
      Check (Res = HE.Rejected_No_Change, "wrong id result");
      Check (Cur = S.Handshake, "wrong id state");
   end;

   --  Retention of version, address, port.
   declare
      P : constant Octets := Build (777, "mc.example.com", 19132, 2);
      Cur : S.Connection_State := S.Handshake;
      Stored : HE.Connection_Data;
      Stored2 : HE.Connection_Data;
      Res : HE.Handle_Result;
      Res2 : HE.Handle_Result;
      Cur2 : S.Connection_State := S.Handshake;
      P2 : constant Octets := Build (760, "other.example", 25566, 1);
   begin
      HE.Handle (0, P, Cur, Stored, Res);
      Check (Res = HE.Accepted_Login, "retention result");
      Check (HE.Last_Protocol_Version (Stored) = 777, "retention version");
      Check (HE.Last_Server_Address (Stored) = "mc.example.com", "retention address");
      Check (HE.Last_Server_Port (Stored) = 19132, "retention port");
      HE.Handle (0, P2, Cur2, Stored2, Res2);
      Check (HE.Last_Protocol_Version (Stored2) = 760, "isolation version");
      Check (HE.Last_Server_Address (Stored2) = "other.example", "isolation address");
      Check (HE.Last_Protocol_Version (Stored) = 777, "isolation first kept");
   end;

   if Failures = 0 then
      Ada.Text_IO.Put_Line ("PASS test_handshake_exchange");
   else
      Ada.Text_IO.Put_Line ("FAILURES:" & Failures'Image);
   end if;
   Ada.Command_Line.Set_Exit_Status
     (if Failures = 0 then Ada.Command_Line.Success else Ada.Command_Line.Failure);
end Test_Handshake_Exchange;
