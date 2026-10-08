with Adacraft.Protocol.Status_Json;

package body Adacraft.Protocol.Status is

   function Decode_Request (Payload : Octets) return Decode_Status is
   begin
      if Payload'Length = 0 then
         return Ok;
      else
         return Violation;
      end if;
   end Decode_Request;

   function Decode_Ping (Payload : Octets) return Ping_Result is
   begin
      if Payload'Length /= 8 then
         return (Status => Violation);
      end if;
      if not Buffer.U64_Ok (Payload, Payload'First) then
         return (Status => Violation);
      end if;
      --  Exact-consumption: U64 occupies the whole payload.
      if Payload'First + 7 /= Payload'Last then
         return (Status => Violation);
      end if;
      declare
         V : constant Interfaces.Unsigned_64 :=
           Buffer.Decode_U64 (Payload, Payload'First);
      begin
         return (Status => Ok, Value => V);
      end;
   exception
      when others =>
         return (Status => Violation);
   end Decode_Ping;

   procedure Encode_Response
     (W : in out Buffer.Writer; Info : Status_Info.Status_Info)
   is
      Json : constant String := Status_Json.To_Json (Info);
   begin
      Buffer.Put_Varint (W, 16#00#);
      Buffer.Put_String (W, Json);
   end Encode_Response;

   procedure Encode_Pong
     (W : in out Buffer.Writer; Value : Interfaces.Unsigned_64)
   is
   begin
      Buffer.Put_Varint (W, 16#01#);
      Buffer.Put_U64 (W, Value);
   end Encode_Pong;

end Adacraft.Protocol.Status;
