package Adacraft.Protocol.State.Table
  with SPARK_Mode => On
is
   --  Rows for protocol 777, derived from the pinned 26.3 packet report via
   --  Adacraft.Protocol.Ids. Pending states copy the parent's serverbound
   --  rows and have no clientbound rows.
   type Row is record
      State      : Connection_State;
      Direction  : Packet_Direction;
      Id         : Packet_Id;
      Name_First : Natural;
      Name_Last  : Natural;
   end record;

   function Row_Count return Positive;
   function Row_At (I : Positive) return Row;
   function Find
     (State : Connection_State;
      Dir   : Packet_Direction;
      Id    : Packet_Id) return Natural;
   function Is_Known_Id (Id : Packet_Id) return Boolean;
   function Name (I : Positive) return String;

   --  LOGIN dispatch helpers (protocol 777, pinned 26.3 report).
   --  Direction + state check per section 19: a LOGIN id is routed to
   --  the login handlers only when it is table-valid serverbound in
   --  its own LOGIN state (Login for Start, Login_Awaiting_Ack for
   --  Acknowledged). No STATUS / HANDSHAKE / CONFIGURATION rows are
   --  affected.
   function Is_Login_Start_Id (Id : Packet_Id) return Boolean;
   function Is_Login_Ack_Id (Id : Packet_Id) return Boolean;
   function Is_Serverbound_Login
     (State : Connection_State;
      Id    : Packet_Id) return Boolean;
end Adacraft.Protocol.State.Table;
