--  Handshake tests HS-1..HS-5: valid decode, intent 1/2/3/invalid,
--  double handshake discipline, trailing bytes, and HS-2 failure modes.
--  Uses Adacraft.Protocol.Packets + State (table-driven intent mapping)
--  instead of the Handshake child (name collides with Protocol literal).
with Ada.Text_IO;
with Interfaces;
with Adacraft.Protocol.Buffer;
with Adacraft.Protocol.Packets;
with Adacraft.Protocol.State;

procedure Test_Protocol_Handshake is
   package Protocol renames Adacraft.Protocol;
   package Packets renames Adacraft.Protocol.Packets;
   package S renames Adacraft.Protocol.State;
   use type Interfaces.Unsigned_32;
   use type Interfaces.Unsigned_16;
   use type Protocol.Status_Kind;
   use type S.Result_Kind;

   Failures : Natural := 0;

   procedure Check (Cond : Boolean; Name : String) is
   begin
      if not Cond then
         Ada.Text_IO.Put_Line ("FAIL " & Name);
         Failures := Failures + 1;
      end if;
   end Check;

   --  Build a handshake payload (without packet id): version, address,
   --  port, intention.
   function Build
     (Version : Interfaces.Unsigned_32;
      Address : String;
      Port    : Interfaces.Unsigned_16;
      Intent  : Interfaces.Unsigned_32) return Protocol.Octets
   is
      W : Protocol.Buffer.Writer (512);
   begin
      Protocol.Buffer.Put_Varint (W, Version);
      Protocol.Buffer.Put_String (W, Address);
      Protocol.Buffer.Put_U16 (W, Port);
      Protocol.Buffer.Put_Varint (W, Intent);
      return W.Data (1 .. W.Len);
   end Build;

   function Map_Intent (Intent : Interfaces.Unsigned_32) return S.Transition_Result is
   begin
      return S.Transition
        (S.Handshake,
         (Direction => S.Serverbound,
          Id        => S.Packet_Id (0),
          Intent    => S.Handshake_Intent (Intent)));
   end Map_Intent;

   Valid : constant Protocol.Octets := Build (777, "localhost", 25565, 1);
begin
   --  HS-1: exactly one valid HANDSHAKE accepted.
   declare
      H : constant Packets.Handshake := Packets.Decode_Handshake (Valid);
   begin
      Check (H.Status = Protocol.Ok, "HS-1 valid accepted");
      Check (H.Version = 777, "HS-1 version");
      Check (H.Addr_Len = 9
             and then H.Address (1 .. 9) = "localhost", "HS-1 address");
      Check (H.Port = 25565, "HS-1 port");
      Check (H.Intent = 1, "HS-1 intent");
      Check (Packets.Is_Fully_Consumed (Valid, H.Next), "HS-1 fully consumed");
   end;

   --  Intent mapping 1/2/3/invalid via state table transition.
   Check (Map_Intent (1).Kind = S.Accepted_Transition
          and then Map_Intent (1).Next_State = S.Status, "intent 1 -> STATUS");
   Check (Map_Intent (2).Kind = S.Accepted_Transition
          and then Map_Intent (2).Next_State = S.Login, "intent 2 -> LOGIN");
   Check (Map_Intent (3).Kind = S.Accepted_Transition
          and then Map_Intent (3).Next_State = S.Login, "intent 3 -> LOGIN");
   Check (Map_Intent (0).Kind = S.Rejected, "intent 0 invalid");
   Check (Map_Intent (4).Kind = S.Rejected, "intent 4 invalid");

   --  HS-2 failure modes close with no bytes (decode Rejected).
   declare
      Empty   : constant Protocol.Octets (1 .. 0) := (others => 0);
      E       : constant Packets.Handshake := Packets.Decode_Handshake (Empty);
      Trunc   : constant Protocol.Octets := Valid (Valid'First .. Valid'Last - 1);
      T       : constant Packets.Handshake := Packets.Decode_Handshake (Trunc);
      BadVer  : constant Protocol.Octets := (1 => 16#80#, 2 => 16#80#, 3 => 16#80#,
                                             4 => 16#80#, 5 => 16#80#, 6 => 16#00#);
      Bv      : constant Packets.Handshake := Packets.Decode_Handshake (BadVer);
      BadInt  : constant Protocol.Octets := Build (777, "localhost", 25565, 9);
      Bi      : constant Packets.Handshake := Packets.Decode_Handshake (BadInt);
   begin
      Check (E.Status = Protocol.Rejected, "HS-2 empty rejected");
      Check (T.Status = Protocol.Rejected, "HS-2 truncated rejected");
      Check (Bv.Status = Protocol.Rejected, "HS-2 malformed varint rejected");
      --  Address > 255 bytes rejected at buffer layer.
      Check (Bi.Status = Protocol.Ok, "HS-2 bad intent decodes, mapping rejects");
      Check (Map_Intent (Bi.Intent).Kind = S.Rejected, "HS-2 bad intent transition");
   end;

   --  Oversize address (> 255 bytes) rejected.
   declare
      Long : String (1 .. 300) := (others => 'a');
      W    : Protocol.Buffer.Writer (600);
      H    : Packets.Handshake;
   begin
      Protocol.Buffer.Put_Varint (W, 777);
      Protocol.Buffer.Put_String (W, Long);
      Protocol.Buffer.Put_U16 (W, 25565);
      Protocol.Buffer.Put_Varint (W, 1);
      if W.Failed then
         Check (True, "HS-2 oversize address writer overflow");
      else
         H := Packets.Decode_Handshake (W.Data (1 .. W.Len));
         Check (H.Status = Protocol.Rejected, "HS-2 oversize address rejected");
      end if;
   end;

   --  Trailing bytes rejected (exact-consumption rule).
   declare
      W : Protocol.Buffer.Writer (512);
      H : Packets.Handshake;
   begin
      Protocol.Buffer.Put_Varint (W, Interfaces.Unsigned_32'(777));
      Protocol.Buffer.Put_String (W, "localhost");
      Protocol.Buffer.Put_U16 (W, 25565);
      Protocol.Buffer.Put_Varint (W, 1);
      Protocol.Buffer.Put_Octet (W, 16#FF#);
      H := Packets.Decode_Handshake (W.Data (1 .. W.Len));
      Check (H.Status = Protocol.Rejected, "trailing bytes rejected");
      Check (not Packets.Is_Fully_Consumed (W.Data (1 .. W.Len), H.Next),
             "trailing not fully consumed");
   end;

   --  Double handshake: second handshake invalid under new state's rules.
   --  After STATUS transition, packet id 0x00 is Status Request, not handshake.
   declare
      R : constant S.Transition_Result := Map_Intent (1);
   begin
      Check (R.Next_State = S.Status, "double-hs first moves to STATUS");
      Check (S.Is_Packet_Valid (S.Status, S.Serverbound, 0),
             "status 0x00 valid in STATUS");
      --  A handshake-shaped payload with non-empty body is not a valid
      --  Status Request (must be empty).
      Check (not Packets.Is_Empty_Payload (Valid), "double-hs payload non-empty");
   end;

   if Failures = 0 then
      Ada.Text_IO.Put_Line ("PASS test_protocol_handshake");
   else
      Ada.Text_IO.Put_Line ("FAILURES test_protocol_handshake:"
                            & Natural'Image (Failures));
   end if;
end Test_Protocol_Handshake;
