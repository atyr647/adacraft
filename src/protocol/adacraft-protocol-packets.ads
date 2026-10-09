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

   --  Login Start view (serverbound minecraft:hello, id 0).
   --  Same wire layout as Login_Hello; provided under the Login
   --  name so LOGIN-state code reads the report name directly.
   type Login_Start is record
      Status : Status_Kind := Rejected;
      Name   : String (1 .. 16) := (others => ' ');
      Name_Len : Natural := 0;
      Uuid   : Octets (1 .. 16) := (others => 0);
   end record;

   function Decode_Login_Start (Payload : Octets) return Login_Start;

   --  Login Success view (clientbound minecraft:login_finished, id 2):
   --  offline UUID + validated name + empty properties array.
   type Login_Success is record
      Uuid       : Octets (1 .. 16) := (others => 0);
      Name       : String (1 .. 16) := (others => ' ');
      Name_Len   : Natural := 0;
      Properties : Natural := 0;
   end record;

   --  Login Acknowledged view (serverbound minecraft:login_acknowledged,
   --  id 3): empty body. Ok only when the payload is zero-length.
   type Login_Acknowledged is record
      Status : Status_Kind := Rejected;
   end record;

   function Decode_Login_Acknowledged
     (Payload : Octets) return Login_Acknowledged;

   --  Login Disconnect view (clientbound minecraft:login_disconnect,
   --  id 0): single JSON text component encoded as a protocol String.
   --  Minimal record needed for FR-5.5; reason text without JSON wrapper.
   Max_Disconnect_Reason : constant := 256;

   type Login_Disconnect is record
      Reason     : String (1 .. Max_Disconnect_Reason) := (others => ' ');
      Reason_Len : Natural := 0;
   end record;
end Adacraft.Protocol.Packets;
