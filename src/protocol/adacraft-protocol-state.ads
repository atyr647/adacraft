package Adacraft.Protocol.State
  with SPARK_Mode => On
is
   type Connection_State is
     (Handshake, Status, Login, Configuration, Play,
      Login_Awaiting_Ack, Configuration_Awaiting_Ack,
      Play_Awaiting_Config_Ack);

   subtype Parent_State is Connection_State range Handshake .. Play;
   subtype Pending_State is Connection_State range
     Login_Awaiting_Ack .. Play_Awaiting_Config_Ack;

   function Initial_State return Connection_State is (Handshake);

   type Packet_Direction is (Serverbound, Clientbound);

   type Packet_Id is new Integer;
   type Handshake_Intent is new Integer;

   type Packet_Event is record
      Direction : Packet_Direction;
      Id        : Packet_Id;
      Intent    : Handshake_Intent := 0;
   end record;

   type Result_Kind is
     (Accepted_Transition, Accepted_No_Transition, Rejected);

   type Rejection_Reason is
     (No_Rejection, Unknown_Packet_Id, Wrong_Direction,
      Packet_Not_Valid_In_State, Invalid_Transition,
      Invalid_Handshake_Intent);

   type Transition_Result is record
      Kind       : Result_Kind;
      Next_State : Connection_State;
      Reason     : Rejection_Reason;
   end record;

   function Is_Packet_Valid
     (State : Connection_State;
      Dir   : Packet_Direction;
      Id    : Packet_Id) return Boolean;

   function Transition
     (Current : Connection_State;
      Event   : Packet_Event) return Transition_Result;

   --  Per-connection login state for the encryption handshake.
   --  No framing or state-machine change; the token is issued per
   --  login attempt and stored here until the Encryption Response
   --  is verified.

   subtype Token_Index is Positive range 1 .. 4;
   type Verify_Token_Bytes is array (Token_Index) of Octet;

   type Login_Session is record
      Verify_Token : Verify_Token_Bytes := (others => 0);
      Token_Valid  : Boolean := False;
   end record;

   function Initial_Login_Session return Login_Session
   is ((Verify_Token => (others => 0), Token_Valid => False));

   procedure Issue_Token
     (Session : in out Login_Session;
      Token   : Verify_Token_Bytes);

   procedure Invalidate_Token (Session : in out Login_Session);

   function Get_Verify_Token
     (Session : Login_Session) return Verify_Token_Bytes;

   function Has_Valid_Token (Session : Login_Session) return Boolean;

   Protocol_Number   : constant := 777;
   Minecraft_Version : constant String := "26.3";
   Report_Source     : constant String :=
     "vanilla 26.3 server.jar packet report (packets.json)";
   Report_SHA256     : constant String :=
     "2f0486311f18b7d3ec232028f3bff82c657d2f0240d2d65a3df40408db926886";
   Server_Jar_SHA256 : constant String :=
     "d052f14d7a173734fba553711e5b570162e2f2a313267ee31a21b975a679be64";
end Adacraft.Protocol.State;
