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
end Adacraft.Protocol.State.Table;
