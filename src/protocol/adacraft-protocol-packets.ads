with Interfaces;
with Adacraft.Protocol.Buffer;

package Adacraft.Protocol.Packets is
   type Handshake is record
      Status   : Status_Kind := Rejected;
      Version  : Interfaces.Unsigned_32 := 0;
      Address  : String (1 .. 255) := (others => ' ');
      Addr_Len : Natural := 0;
      Port     : Interfaces.Unsigned_16 := 0;
      Intent   : Interfaces.Unsigned_32 := 0;
      Next     : Natural := 0;
   end record;

   function Decode_Handshake (Payload : Octets) return Handshake;

   procedure Encode_Status_Response (W : in out Buffer.Writer);
   procedure Encode_Pong (W : in out Buffer.Writer; Payload : Interfaces.Unsigned_64);
   procedure Encode_Login_Disconnect (W : in out Buffer.Writer; Reason : String);

   function Frame (W : in out Buffer.Writer; Payload : Buffer.Writer) return Boolean;

   type Ping is record
      Status : Status_Kind := Rejected;
      Value  : Interfaces.Unsigned_64 := 0;
   end record;

   --  Exact-consumption foundation (Phase 2): after decoding any
   --  serverbound packet, the payload cursor must equal the end of the
   --  payload. Next is the cursor returned by the decoder (first
   --  unconsumed index; Payload'Last + 1 when fully consumed).
   --  This single check yields trailing-byte rejection on handshake,
   --  empty-payload enforcement on Status Request, and exactly-8-bytes
   --  on Ping Request.
   function Is_Fully_Consumed (Payload : Octets; Next : Natural) return Boolean
   with Global => null;

   function Is_Empty_Payload (Payload : Octets) return Boolean
   with Global => null;

   function Decode_Ping (Payload : Octets) return Ping;

   type Login_Hello is record
      Status : Status_Kind := Rejected;
      Name   : String (1 .. 16) := (others => ' ');
      Name_Len : Natural := 0;
      Uuid   : Octets (1 .. 16) := (others => 0);
   end record;

   function Decode_Login_Hello (Payload : Octets) return Login_Hello;
end Adacraft.Protocol.Packets;
