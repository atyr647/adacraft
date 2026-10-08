package Adacraft.Protocol.State.Table
  with SPARK_Mode => On
is
   --  Rows for protocol 777, derived from the pinned 26.3 packet report via
   --  Adacraft.Protocol.Ids. Pending states copy the parent's serverbound
   --  rows and have no clientbound rows.
   --
   --  LOGIN serverbound rows cover the pinned 26.3 login state, including
   --  Login Start (minecraft:hello, id 0) and Login Acknowledged
   --  (minecraft:login_acknowledged, id 3). Handshake, status,
   --  configuration and unknown ids have no LOGIN row and are therefore
   --  invalid in LOGIN. CONFIGURATION rows exist so that post-Ack inbound
   --  decodes against the configuration table and the connection rests
   --  there (successor items own configuration-phase logic).
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
end Adacraft.Protocol.State.Table;
