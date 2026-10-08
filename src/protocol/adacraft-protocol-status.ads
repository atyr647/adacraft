with Interfaces;
with Adacraft.Protocol;
with Adacraft.Protocol.Buffer;
with Adacraft.Protocol.Status_Info;

package Adacraft.Protocol.Status is

   --  STATUS-state packet codecs.
   --  Serverbound 0x00 Status Request: empty payload.
   --  Serverbound 0x01 Ping Request: exactly 8 bytes (signed 64-bit BE).
   --  Clientbound 0x00 Status Response: String containing JSON.
   --  Clientbound 0x01 Pong Response: exactly 8 bytes echoed.
   --  Decode paths never raise on wire input.

   type Decode_Status is (Ok, Violation);

   type Ping_Result (Status : Decode_Status := Violation) is record
      case Status is
         when Ok =>
            Value : Interfaces.Unsigned_64 := 0;
         when Violation =>
            null;
      end case;
   end record;

   function Decode_Request (Payload : Octets) return Decode_Status
   with Global => null;
   --  Ok iff payload is empty.

   function Decode_Ping (Payload : Octets) return Ping_Result
   with Global => null;
   --  Ok iff payload is exactly 8 bytes; Value is big-endian long.

   procedure Encode_Response
     (W : in out Buffer.Writer; Info : Status_Info.Status_Info);
   --  Encodes packet id 0x00 + String(JSON). Sets W.Failed on overflow.

   procedure Encode_Pong
     (W : in out Buffer.Writer; Value : Interfaces.Unsigned_64);
   --  Encodes packet id 0x01 + 8-byte big-endian value.

end Adacraft.Protocol.Status;
