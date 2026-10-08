with Ada.Text_IO;
with Interfaces;
with Adacraft.Protocol;
with Adacraft.Protocol.Buffer;
with Adacraft.Protocol.State;
with Adacraft.Protocol.Handshake_Exchange;

procedure Test_Handshake_Exchange is
   use Adacraft.Protocol;
   use type State.Connection_State;

   Failures : Natural := 0;

   procedure Check (Condition : Boolean; Name : String) is
   begin
      if Condition then
         Ada.Text_IO.Put_Line ("PASS: " & Name);
      else
         Failures := Failures + 1;
         Ada.Text_IO.Put_Line ("FAIL: " & Name);
      end if;
   end Check;

   function Build_Payload
     (Version : Interfaces.Unsigned_32;
      Address : String;
      Port    : Interfaces.Unsigned_16;
      Intent  : Interfaces.Unsigned_32) return Octets
   is
      W : Buffer.Writer (Capacity => 512);
   begin
      Buffer.Reset (W);
      Buffer.Put_Varint (W, Version);
      Buffer.Put_String (W, Address);
      Buffer.Put_U16 (W, Port);
      Buffer.Put_Varint (W, Intent);
      if W.Failed or else W.Len = 0 then
         return [1 .. 1 => 0];
      end if;
      declare
         Result : Octets (1 .. W.Len);
      begin
         for I in 1 .. W.Len loop
            Result (I) := W.Data (I);
         end loop;
         return Result;
      end;
   end Build_Payload;

   function Truncated (Payload : Octets) return Octets is
   begin
      if Payload'Length <= 1 then
         return Payload;
      end if;
      declare
         Result : Octets (1 .. Payload'Length - 1);
      begin
         for I in Result'Range loop
            Result (I) := Payload (Payload'First + I - 1);
         end loop;
         return Result;
      end;
   end Truncated;

   Payload_Status : constant Octets :=
     Build_Payload (777, "localhost", 25565, 1);
   Payload_Login : constant Octets :=
     Build_Payload (777, "localhost", 25565, 2);
   Payload_Intent_0 : constant Octets :=
     Build_Payload (777, "localhost", 25565, 0);
   Payload_Intent_3 : constant Octets :=
     Build_Payload (777, "localhost", 25565, 3);
   Payload_Intent_99 : constant Octets :=
     Build_Payload (777, "localhost", 25565, 99);
   R : Handshake_Exchange.Outcome;
begin
   R := Handshake_Exchange.Handle (State.Handshake, 0, Payload_Status);
   Check (R.Accepted and then R.Has_Transition
          and then R.Next_State = State.Status
          and then not R.Close_Requested,
          "intent 1 -> Status");

   R := Handshake_Exchange.Handle (State.Handshake, 0, Payload_Login);
   Check (R.Accepted and then R.Has_Transition
          and then R.Next_State = State.Login
          and then R.Client_Version = 777
          and then not R.Close_Requested,
          "intent 2 -> Login + version");

   R := Handshake_Exchange.Handle (State.Handshake, 0, Payload_Intent_0);
   Check (not R.Accepted and then not R.Has_Transition
          and then R.Close_Requested,
          "intent 0 rejected no transition");

   R := Handshake_Exchange.Handle (State.Handshake, 0, Payload_Intent_3);
   Check (not R.Accepted and then not R.Has_Transition
          and then R.Close_Requested,
          "intent 3 rejected no transition");

   R := Handshake_Exchange.Handle (State.Handshake, 0, Payload_Intent_99);
   Check (not R.Accepted and then not R.Has_Transition
          and then R.Close_Requested,
          "intent 99 rejected no transition");

   declare
      Long_Address : constant String (1 .. 256) := [others => 'a'];
      P : constant Octets :=
        Build_Payload (777, Long_Address, 25565, 1);
      R2 : constant Handshake_Exchange.Outcome :=
        Handshake_Exchange.Handle (State.Handshake, 0, P);
   begin
      Check (not R2.Accepted and then not R2.Has_Transition
             and then R2.Close_Requested,
             "256-char address rejected");
   end;

   declare
      P : constant Octets := Truncated (Payload_Login);
      R2 : constant Handshake_Exchange.Outcome :=
        Handshake_Exchange.Handle (State.Handshake, 0, P);
   begin
      Check (not R2.Accepted and then not R2.Has_Transition
             and then R2.Close_Requested,
             "truncated payload rejected");
   end;

   R := Handshake_Exchange.Handle (State.Handshake, 1, [1 .. 0 => <>]);
   Check (not R.Accepted and then not R.Has_Transition
          and then R.Close_Requested,
          "wrong ID rejected");

   R := Handshake_Exchange.Handle (State.Status, 0, Payload_Status);
   Check (not R.Accepted and then not R.Has_Transition
          and then R.Close_Requested,
          "non-Handshake state rejected");

   R := Handshake_Exchange.Handle (State.Login, 0, Payload_Login);
   Check (not R.Accepted and then not R.Has_Transition
          and then R.Close_Requested,
          "login state rejected");

   if Failures > 0 then
      raise Program_Error with "test failures";
   end if;
   Ada.Text_IO.Put_Line ("ALL PASS");
end Test_Handshake_Exchange;
