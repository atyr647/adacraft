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

   function Decode_Ping (Payload : Octets) return Ping;

   type Login_Hello is record
      Status : Status_Kind := Rejected;
      Name   : String (1 .. 16) := (others => ' ');
      Name_Len : Natural := 0;
      Uuid   : Octets (1 .. 16) := (others => 0);
   end record;

   function Decode_Login_Hello (Payload : Octets) return Login_Hello;

   type Login_Start is record
      Status : Status_Kind := Rejected;
      Name   : String (1 .. 16) := (others => ' ');
      Name_Len : Natural := 0;
      Uuid   : Octets (1 .. 16) := (others => 0);
   end record;

   function Decode_Login_Start (Payload : Octets) return Login_Start;

   procedure Encode_Login_Success
     (W    : in out Buffer.Writer;
      Uuid : Octets;
      Name : String);

   type Login_Acknowledged is record
      Status : Status_Kind := Rejected;
   end record;

   function Decode_Login_Acknowledged (Payload : Octets) return Login_Acknowledged;
end Adacraft.Protocol.Packets;
