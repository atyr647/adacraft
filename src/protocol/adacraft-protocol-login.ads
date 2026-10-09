with Adacraft.Auth;
with Adacraft.Protocol.Buffer;

package Adacraft.Protocol.Login is

   --  Provenance: protocol 777 (26.3) packet report
   --  generated/26.3/reports/packets.json via
   --  generated/adacraft-protocol-ids.ads:
   --  serverbound minecraft:hello = 0 (Login Start),
   --  clientbound minecraft:login_finished = 2 (Login Success),
   --  serverbound minecraft:login_acknowledged = 3,
   --  clientbound minecraft:login_disconnect = 0.

   Max_Name_Length   : constant := 16;
   Max_Reason_Length : constant := 256;

   Invalid_Name_Reason : constant String := "invalid name";
   Malformed_Start_Reason : constant String := "malformed login start";
   Online_Not_Yet_Supported_Reason : constant String :=
     "online mode not yet supported";
   Default_Disconnect_Reason : constant String := "Login not yet supported";

   function Is_Valid_Name_Char (Ch : Character) return Boolean is
     (Character'Pos (Ch) in 16#21# .. 16#7E#);

   function Is_Valid_Name (Name : String) return Boolean;

   type Login_Start_Status is (Ok, Malformed, Invalid_Name);

   type Login_Start is record
      Status      : Login_Start_Status := Malformed;
      Name        : String (1 .. Max_Name_Length) := (others => ' ');
      Name_Len    : Natural := 0;
      Client_Uuid : Octets (1 .. 16) := (others => 0);
   end record;

   function Decode_Login_Start (Payload : Octets) return Login_Start;

   function Offline_UUID (Name : String) return Auth.Digest;

   function Offline_Identity (Name : String) return Auth.Player_Identity;

   function Is_Login_Acknowledged (Payload : Octets) return Boolean;

   type Login_State is
     (Await_Start, Success_Sent, Acknowledged, Configuration, Closed);

   function Initial_Session return Login_State is (Await_Start);

   type Login_Session is record
      State        : Login_State := Await_Start;
      Success_Sent : Boolean := False;
      Has_Identity : Boolean := False;
      Identity     : Auth.Player_Identity :=
        (Kind => Auth.Offline, UUID => (others => 0),
         Name_Length => 0, Name => (others => ' '));
   end record;

   type Start_Outcome is
     (Ready_Success, Need_Disconnect_Close, Protocol_Error_Close,
      Refuse_Online);

   type Start_Result is record
      Outcome    : Start_Outcome := Protocol_Error_Close;
      Session    : Login_Session;
      Identity   : Auth.Player_Identity :=
        (Kind => Auth.Offline, UUID => (others => 0),
         Name_Length => 0, Name => (others => ' '));
      Reason     : String (1 .. Max_Reason_Length) := (others => ' ');
      Reason_Len : Natural := 0;
   end record;

   type Ack_Outcome is (To_Configuration, Protocol_Error_Close);

   type Ack_Result is record
      Outcome : Ack_Outcome := Protocol_Error_Close;
      Session : Login_Session;
   end record;

   function To_Reason (R : String) return Start_Result;

   function Handle_Start
     (S : Login_Session; Payload : Octets;
      Mode : Auth.Server_Auth_Mode) return Start_Result;

   function Handle_Acknowledged
     (S : Login_Session; Payload : Octets) return Ack_Result;

   procedure Encode_Login_Success
     (W : in out Buffer.Writer; Identity : Auth.Player_Identity);

   procedure Encode_Login_Disconnect
     (W : in out Buffer.Writer; Reason : String);

   function Build_Login_Disconnect
     (Reason : String := Default_Disconnect_Reason) return Octets;

end Adacraft.Protocol.Login;
