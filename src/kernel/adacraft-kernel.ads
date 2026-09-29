with Interfaces;

package Adacraft.Kernel
  with SPARK_Mode
is
   type Attempt is (Rejected, Accepted);

   type Block_Pos is record
      X, Y, Z : Interfaces.Integer_32 := 0;
   end record;

   type Residency is (Unloaded, Loading, Loaded, Active, Inactive, Saving);

   type Command_Id is
     (Teleport, Gamemode, Give, Kill, Time_Set, Weather, Difficulty,
      Set_World_Spawn, Unknown);

   subtype Permission_Level is Natural range 0 .. 4;
   subtype Stack_Count is Natural range 0 .. 99;

   type Item_Id is new Natural;

   type Stack is record
      Item      : Item_Id := 0;
      Count     : Stack_Count := 0;
      Max_Count : Stack_Count := 64;
   end record;

   type Entity_Index is range 0 .. 1023;

   type Entity_Handle is record
      ID         : Entity_Index := 0;
      Generation : Interfaces.Unsigned_32 := 0;
   end record;

   type Entity_Slot is record
      Live       : Boolean := False;
      Generation : Interfaces.Unsigned_32 := 0;
   end record;

   type Entity_Pool is array (Entity_Index) of Entity_Slot;

   type Save_Step is (Take_Snapshot, Commit);

   type Save_Phase is (Idle, Snapshot_Ready);

   type Authority is record
      Position             : Block_Pos := (0, 0, 0);
      Chunk                : Residency := Unloaded;
      Permission           : Permission_Level := 0;
      Breaks               : Natural := 0;
      Drops                : Natural := 0;
      Placements           : Natural := 0;
      Last_Command         : Command_Id := Unknown;
      Commands_Accepted    : Natural := 0;
      Committed_Generation : Natural := 0;
      Save                 : Save_Phase := Idle;
      Entities             : Entity_Pool := (others => (False, 0));
   end record;

   type Move_Request is record
      Player_Live    : Boolean := False;
      Chunk_Active   : Boolean := False;
      Collision_Free : Boolean := False;
      Within_Rules   : Boolean := False;
      Target         : Block_Pos := (0, 0, 0);
   end record;

   type Break_Request is record
      Player_Live : Boolean := False;
      Chunk_Active : Boolean := False;
      In_Reach    : Boolean := False;
      Legal       : Boolean := False;
      Drop_Count  : Natural := 0;
   end record;

   type Place_Request is record
      Player_Live : Boolean := False;
      Chunk_Active : Boolean := False;
      In_Reach    : Boolean := False;
      Legal       : Boolean := False;
      Collision_Free : Boolean := False;
   end record;

   procedure Try_Move
     (State : in out Authority; Request : Move_Request; Result : out Attempt)
     with Post => (if Result = Rejected then State = State'Old);

   procedure Try_Break_Block
     (State : in out Authority; Request : Break_Request; Result : out Attempt)
     with Post =>
       (if Result = Rejected then State = State'Old)
       and then (if Result = Accepted
                 then State.Drops = State'Old.Drops + Request.Drop_Count);

   procedure Try_Place_Block
     (State : in out Authority; Request : Place_Request; Result : out Attempt)
     with Post => (if Result = Rejected then State = State'Old);

   procedure Try_Inventory_Move
     (Source : in out Stack;
      Destination : in out Stack;
      Amount : Stack_Count;
      Result : out Attempt)
     with Post =>
       (if Result = Rejected
        then Source = Source'Old and Destination = Destination'Old)
       and then (if Result = Accepted
                 then Integer (Source.Count) + Integer (Destination.Count)
                      = Integer (Source'Old.Count) + Integer (Destination'Old.Count));

   procedure Try_Execute_Command
     (State : in out Authority; Command : Command_Id; Result : out Attempt)
     with Post => (if Result = Rejected then State = State'Old);

   procedure Try_Chunk_Transition
     (State : in out Authority; Target : Residency; Result : out Attempt)
     with Post => (if Result = Rejected then State = State'Old);

   function Handle_Valid (Pool : Entity_Pool; Handle : Entity_Handle) return Boolean;

   procedure Try_Retire_Handle
     (Pool : in out Entity_Pool; Handle : Entity_Handle; Result : out Attempt)
     with Post =>
       (if Result = Rejected then Pool = Pool'Old)
       and then (if Result = Accepted then not Handle_Valid (Pool, Handle));

   procedure Try_Save
     (State : in out Authority;
      Step : Save_Step;
      Durable : Boolean;
      Result : out Attempt)
     with Post =>
       (if Result /= Accepted
        then State.Committed_Generation = State'Old.Committed_Generation);

   procedure Try_Set_Permission
     (State : in out Authority;
      Actor_May_Set : Boolean;
      New_Level : Permission_Level;
      Result : out Attempt)
     with Post => (if Result = Rejected then State = State'Old);
end Adacraft.Kernel;
