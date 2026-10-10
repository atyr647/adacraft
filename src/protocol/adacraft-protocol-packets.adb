with Adacraft.Protocol.Ids;
with Adacraft.Protocol.Status_Exchange;
with Adacraft.Protocol.Varnum;

package body Adacraft.Protocol.Packets is
   function Decode_Handshake (Payload : Octets) return Handshake is
      Result  : Handshake;
      Version : Varnum.Varint_Result;
      Address : Buffer.String_Decode;
      Intent  : Varnum.Varint_Result;
   begin
      if Payload'Length = 0 then
         Result.Status := Rejected;
         return Result;
      end if;
      Version := Varnum.Decode_Varint (Payload, Payload'First);
      if Version.Status /= Ok then
         Result.Status := Version.Status;
         return Result;
      end if;
      Address := Buffer.Decode_String (Payload, Version.Next, 255);
      if Address.Status /= Ok then
         Result.Status := Rejected;
         return Result;
      end if;
      if Address.Next > Payload'Last or else Payload'Last - Address.Next < 1 then
         Result.Status := Rejected;
         return Result;
      end if;
      if Address.Next > Natural'Last - 2
        or else Address.Next + 2 > Payload'Last + 1
      then
         Result.Status := Rejected;
         return Result;
      end if;
      Intent := Varnum.Decode_Varint (Payload, Address.Next + 2);
      if Intent.Status /= Ok or else Intent.Next /= Payload'Last + 1 then
         Result.Status := Rejected;
         return Result;
      end if;
      Result.Status := Ok;
      Result.Version := Version.Value;
      Result.Addr_Len := Address.Length;
      Result.Address (1 .. Address.Length) := Address.Text (1 .. Address.Length);
      Result.Port := Buffer.Decode_U16 (Payload, Address.Next);
      Result.Intent := Intent.Value;
      Result.Next := Intent.Next;
      return Result;
   end Decode_Handshake;

   procedure Encode_Status_Response (W : in out Buffer.Writer) is
      JSON : constant String :=
        Adacraft.Protocol.Status_Exchange.Build_Response;
   begin
      Buffer.Put_Varint (W, Interfaces.Unsigned_32 (Ids.Protocol_Id (Ids.Cb_Status_Status_Response)));
      Buffer.Put_String (W, JSON);
   end Encode_Status_Response;

   procedure Encode_Pong (W : in out Buffer.Writer; Payload : Interfaces.Unsigned_64) is
   begin
      Buffer.Put_Varint (W, Interfaces.Unsigned_32 (Ids.Protocol_Id (Ids.Cb_Status_Pong_Response)));
      Buffer.Put_U64 (W, Payload);
   end Encode_Pong;

   procedure Encode_Login_Disconnect (W : in out Buffer.Writer; Reason : String) is
      JSON : constant String := "{""text"":""" & Reason & """}";
   begin
      Buffer.Put_Varint
        (W, Interfaces.Unsigned_32 (Ids.Protocol_Id (Ids.Cb_Login_Login_Disconnect)));
      Buffer.Put_String (W, JSON);
   end Encode_Login_Disconnect;

   function Frame (W : in out Buffer.Writer; Payload : Buffer.Writer) return Boolean is
   begin
      if Payload.Failed or else Payload.Len = 0 then
         return False;
      end if;
      Buffer.Reset (W);
      Buffer.Put_Varint (W, Interfaces.Unsigned_32 (Payload.Len));
      Buffer.Put_Bytes (W, Payload.Data (1 .. Payload.Len));
      return not W.Failed;
   end Frame;

   function Decode_Ping (Payload : Octets) return Ping is
   begin
      if not Buffer.U64_Ok (Payload, Payload'First) or else Payload'Length /= 8 then
         return (Status => Rejected, Value => 0);
      end if;
      return (Status => Ok, Value => Buffer.Decode_U64 (Payload, Payload'First));
   end Decode_Ping;

   function Decode_Login_Hello (Payload : Octets) return Login_Hello is
      Result : Login_Hello;
      Name   : Buffer.String_Decode;
   begin
      if Payload'Length = 0 then
         Result.Status := Rejected;
         return Result;
      end if;
      Name := Buffer.Decode_String (Payload, Payload'First, 16);
      if Name.Status /= Ok or else Name.Length = 0 then
         Result.Status := Rejected;
         return Result;
      end if;
      if Name.Next > Payload'Last or else Payload'Last - Name.Next + 1 /= 16 then
         Result.Status := Rejected;
         return Result;
      end if;
      Result.Status := Ok;
      Result.Name_Len := Name.Length;
      Result.Name (1 .. Name.Length) := Name.Text (1 .. Name.Length);
      for I in 1 .. 16 loop
         Result.Uuid (I) := Payload (Name.Next + I - 1);
      end loop;
      return Result;
   end Decode_Login_Hello;

   function Decode_Login_Start (Payload : Octets) return Login_Start is
      Hello  : constant Login_Hello := Decode_Login_Hello (Payload);
      Result : Login_Start;
   begin
      Result.Status := Hello.Status;
      Result.Name := Hello.Name;
      Result.Name_Len := Hello.Name_Len;
      Result.Uuid := Hello.Uuid;
      return Result;
   end Decode_Login_Start;

   function Decode_Login_Acknowledged
     (Payload : Octets) return Login_Acknowledged
   is
   begin
      if Payload'Length = 0 then
         return (Status => Ok);
      else
         return (Status => Rejected);
      end if;
   end Decode_Login_Acknowledged;
end Adacraft.Protocol.Packets;
