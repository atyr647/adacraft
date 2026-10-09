with Ada.Command_Line;
with Ada.Text_IO;
with Interfaces;
with Adacraft.Protocol;
with Adacraft.Protocol.Buffer;
with Adacraft.Protocol.State;
with Adacraft.Protocol.Status_Exchange;

procedure Test_Status_Exchange is
   use Adacraft.Protocol;
   package SE renames Adacraft.Protocol.Status_Exchange;
   package S renames Adacraft.Protocol.State;
   use type S.Connection_State;
   use type SE.Handle_Result;
   use type Interfaces.Unsigned_8;

   Failures : Natural := 0;

   procedure Check (Cond : Boolean; Name : String) is
   begin
      if not Cond then
         Failures := Failures + 1;
         Ada.Text_IO.Put_Line ("FAIL: " & Name);
      end if;
   end Check;

   function Contains (Hay : String; Needle : String) return Boolean is
   begin
      if Needle'Length = 0 or else Hay'Length < Needle'Length then
         return False;
      end if;
      for I in Hay'First .. Hay'Last - Needle'Length + 1 loop
         if Hay (I .. I + Needle'Length - 1) = Needle then
            return True;
         end if;
      end loop;
      return False;
   end Contains;

   Empty : constant Octets (1 .. 0) := (others => <>);

   procedure Do_Handle
     (Id : Natural; Payload : Octets; Cur : in out S.Connection_State;
      Sess : in out SE.Session;
      Res : out SE.Handle_Result; Rid : out Natural;
      Rbuf : out Octets; Rlen : out Natural; Close_F : out Boolean)
   is
   begin
      SE.Handle (Id, Payload, Cur, Sess, Res, Rid, Rbuf, Rlen, Close_F);
   end Do_Handle;

   function To_Payload (V : Interfaces.Unsigned_64) return Octets is
      W : Buffer.Writer (16);
   begin
      Buffer.Put_U64 (W, V);
      declare
         R : Octets (1 .. W.Len);
      begin
         for I in 1 .. W.Len loop
            R (I) := W.Data (I);
         end loop;
         return R;
      end;
   end To_Payload;

begin
   --  Request -> Response JSON fields present.
   declare
      Cur : S.Connection_State := S.Status;
      Sess : SE.Session;
      Res : SE.Handle_Result;
      Rid : Natural := 99;
      Rlen : Natural := 0;
      Rbuf : Octets (1 .. 33_000) := (others => 0);
      Close_F : Boolean := True;
   begin
      SE.Reset (Sess);
      SE.Handle (16#00#, Empty, Cur, Sess, Res, Rid, Rbuf, Rlen, Close_F);
      Check (Res = SE.Responded, "request result");
      Check (Rid = 16#00#, "request response id");
      Check (Close_F = False, "request no close");
      Check (Rlen > 0, "request response len");
      declare
         View : Octets (1 .. Rlen);
      begin
         for I in 1 .. Rlen loop
            View (I) := Rbuf (I);
         end loop;
         declare
            Dec : constant Buffer.String_Decode :=
              Buffer.Decode_String (View, View'First, 32_767);
         begin
            Check (Dec.Status = Ok, "request json decode");
            if Dec.Status = Ok then
               declare
                  J : constant String := Dec.Text (1 .. Dec.Length);
               begin
                  Check (Contains (J, """version"""), "json version");
                  Check (Contains (J, """26.3"""), "json name 26.3");
                  Check (Contains (J, "777"), "json protocol 777");
                  Check (Contains (J, """players"""), "json players");
                  Check (Contains (J, """max"""), "json max");
                  Check (Contains (J, """online"""), "json online");
                  Check (Contains (J, """description"""), "json description");
                  Check (Contains (J, "AdaCraft"), "json AdaCraft");
                  Check (not Contains (J, "favicon"), "json no favicon");
                  Check (Dec.Length <= 32_767, "json cap");
               end;
            end if;
         end;
      end;
   end;

   --  Ping identity for 0, -1 (all 1s), Long'Last.
   declare
      Vals : constant array (1 .. 3) of Interfaces.Unsigned_64 :=
        (0, 16#FFFF_FFFF_FFFF_FFFF#, 16#7FFF_FFFF_FFFF_FFFF#);
   begin
      for K in Vals'Range loop
         declare
            P : constant Octets := To_Payload (Vals (K));
            Cur : S.Connection_State := S.Status;
            Sess : SE.Session;
            Res : SE.Handle_Result;
            Rid : Natural := 99;
            Rlen : Natural := 0;
            Rbuf : Octets (1 .. 33_000) := (others => 0);
            Close_F : Boolean := False;
         begin
            SE.Reset (Sess);
            SE.Handle (16#01#, P, Cur, Sess, Res, Rid, Rbuf, Rlen, Close_F);
            Check (Res = SE.Pong_Ready_Close, "pong result" & K'Image);
            Check (Rid = 16#01#, "pong id" & K'Image);
            Check (Rlen = 8, "pong len" & K'Image);
            Check (Close_F = True, "pong close" & K'Image);
            if Rlen = 8 then
               for I in 0 .. 7 loop
                  Check (Rbuf (Rbuf'First + I) = P (P'First + I),
                         "pong byte" & K'Image & I'Image);
               end loop;
            end if;
         end;
      end loop;
   end;

   --  Duplicate request rejected+close.
   declare
      Cur : S.Connection_State := S.Status;
      Sess : SE.Session;
      Res : SE.Handle_Result;
      Rid : Natural := 0;
      Rlen : Natural := 0;
      Rbuf : Octets (1 .. 33_000) := (others => 0);
      Close_F : Boolean := False;
   begin
      SE.Reset (Sess);
      SE.Handle (16#00#, Empty, Cur, Sess, Res, Rid, Rbuf, Rlen, Close_F);
      Check (Res = SE.Responded, "dup first ok");
      SE.Handle (16#00#, Empty, Cur, Sess, Res, Rid, Rbuf, Rlen, Close_F);
      Check (Res = SE.Rejected_Close, "dup second rejected");
      Check (Close_F = True, "dup close");
   end;

   --  Non-empty request rejected+close.
   declare
      Cur : S.Connection_State := S.Status;
      Sess : SE.Session;
      Res : SE.Handle_Result;
      Rid : Natural := 0;
      Rlen : Natural := 0;
      Rbuf : Octets (1 .. 33_000) := (others => 0);
      Close_F : Boolean := False;
      P : constant Octets (1 .. 1) := (others => 16#00#);
   begin
      SE.Reset (Sess);
      SE.Handle (16#00#, P, Cur, Sess, Res, Rid, Rbuf, Rlen, Close_F);
      Check (Res = SE.Rejected_Close, "nonempty request rejected");
      Check (Close_F = True, "nonempty close");
   end;

   --  Bad ping lengths 0, 7, 9.
   declare
      P0 : constant Octets (1 .. 0) := (others => <>);
      P7 : constant Octets (1 .. 7) := (others => 16#AB#);
      P9 : constant Octets (1 .. 9) := (others => 16#AB#);
   begin
      for J in 0 .. 2 loop
         declare
            Cur : S.Connection_State := S.Status;
            Sess : SE.Session;
            Res : SE.Handle_Result;
            Rid : Natural := 0;
            Rlen : Natural := 0;
            Rbuf : Octets (1 .. 33_000) := (others => 0);
            Close_F : Boolean := False;
         begin
            SE.Reset (Sess);
            if J = 0 then
               SE.Handle (16#01#, P0, Cur, Sess, Res, Rid, Rbuf, Rlen, Close_F);
            elsif J = 1 then
               SE.Handle (16#01#, P7, Cur, Sess, Res, Rid, Rbuf, Rlen, Close_F);
            else
               SE.Handle (16#01#, P9, Cur, Sess, Res, Rid, Rbuf, Rlen, Close_F);
            end if;
            Check (Res = SE.Rejected_Close, "bad ping rejected" & J'Image);
            Check (Close_F = True, "bad ping close" & J'Image);
         end;
      end loop;
   end;

   --  Unknown ID rejected+close.
   declare
      Cur : S.Connection_State := S.Status;
      Sess : SE.Session;
      Res : SE.Handle_Result;
      Rid : Natural := 0;
      Rlen : Natural := 0;
      Rbuf : Octets (1 .. 33_000) := (others => 0);
      Close_F : Boolean := False;
   begin
      SE.Reset (Sess);
      SE.Handle (16#05#, Empty, Cur, Sess, Res, Rid, Rbuf, Rlen, Close_F);
      Check (Res = SE.Rejected_Close, "unknown id rejected");
      Check (Close_F = True, "unknown id close");
   end;

   --  Wrong-state: Status 0x00 in Handshake, Login rejected.
   declare
      Cur : S.Connection_State := S.Handshake;
      Sess : SE.Session;
      Res : SE.Handle_Result;
      Rid : Natural := 0;
      Rlen : Natural := 0;
      Rbuf : Octets (1 .. 33_000) := (others => 0);
      Close_F : Boolean := False;
   begin
      SE.Reset (Sess);
      SE.Handle (16#00#, Empty, Cur, Sess, Res, Rid, Rbuf, Rlen, Close_F);
      Check (Res = SE.Rejected_Close, "wrong-state handshake rejected");
      Check (Close_F = True, "wrong-state handshake close");
      Cur := S.Login;
      SE.Reset (Sess);
      SE.Handle (16#01#, To_Payload (0), Cur, Sess, Res, Rid, Rbuf, Rlen, Close_F);
      Check (Res = SE.Rejected_Close, "wrong-state login rejected");
      Check (Close_F = True, "wrong-state login close");
   end;

   if Failures = 0 then
      Ada.Text_IO.Put_Line ("PASS test_status_exchange");
   else
      Ada.Text_IO.Put_Line ("FAILURES:" & Failures'Image);
   end if;
   Ada.Command_Line.Set_Exit_Status
     (if Failures = 0 then Ada.Command_Line.Success else Ada.Command_Line.Failure);
end Test_Status_Exchange;
