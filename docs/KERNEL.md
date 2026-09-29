# KERNEL.md

Normative signatures for the v1 authority boundary.
Under [CONSTITUTION.md](../CONSTITUTION.md). The closed set is not extended here.

Packet admission is not an eighth-or-tenth `Try_*`. It is the decoder in `Adacraft.Protocol`: a rejected frame changes no authority state. The nine operations below are the only procedures that commit authority state.

Collision, reach, and legality are inputs computed by the simulation owner. The kernel does not simulate them, and it does not read a world array. Protocol and network packages cannot name `Adacraft.Kernel`.

Results are `Rejected` or `Accepted`. On `Rejected`, the postcondition named on each procedure holds. Checks are enabled (`-gnata`).

## Types

```ada
type Attempt is (Rejected, Accepted);
type Block_Pos is record
   X, Y, Z : Interfaces.Integer_32;
end record;
type Residency is (Unloaded, Loading, Loaded, Active, Inactive, Saving);
type Command_Id is
  (Teleport, Gamemode, Give, Kill, Time_Set, Weather, Difficulty,
   Set_World_Spawn, Unknown);
subtype Permission_Level is Natural range 0 .. 4;
subtype Stack_Count is Natural range 0 .. 99;
type Item_Id is new Natural;

type Stack is record
   Item      : Item_Id;
   Count     : Stack_Count;
   Max_Count : Stack_Count;
end record;

type Entity_Handle is record
   ID         : Entity_Index;          -- 0 .. 1023
   Generation : Interfaces.Unsigned_32;
end record;
```

`Handle_Valid` is true only when the pool slot is live and its generation equals the handle. A handle is not a pointer.

## Operations

```ada
procedure Try_Move
  (State : in out Authority; Request : Move_Request; Result : out Attempt);
-- Accepts only when Player_Live, Chunk_Active, Collision_Free, and Within_Rules.
-- On accept, Position becomes Request.Target.
-- On reject, State is unchanged.

procedure Try_Break_Block
  (State : in out Authority; Request : Break_Request; Result : out Attempt);
-- Accepts only when Player_Live, Chunk_Active, In_Reach, and Legal,
-- and the drop count fits.
-- On accept, Breaks increases by one and Drops increases by Request.Drop_Count.
-- The drops are part of this operation. There is no Try_Spawn_Item.
-- On reject, State is unchanged.

procedure Try_Place_Block
  (State : in out Authority; Request : Place_Request; Result : out Attempt);
-- Accepts only when Player_Live, Chunk_Active, In_Reach, Legal, and Collision_Free.
-- On accept, Placements increases by one. Block and item changes are one result.
-- On reject, State is unchanged.

procedure Try_Inventory_Move
  (Source, Destination : in out Stack; Amount : Stack_Count; Result : out Attempt);
-- Rejects a zero amount, an amount above the source count or source max,
-- a different item already in the destination, or a destination that cannot
-- hold Amount. An empty destination takes the source item and its max.
-- On accept, source count + destination count is unchanged.
-- On reject, both stacks are unchanged.
-- Max_Count comes from the stack, never from a literal 64 assumption in the check.

procedure Try_Execute_Command
  (State : in out Authority; Command : Command_Id; Result : out Attempt);
-- Unknown is rejected. Every named v1 command requires permission level 2.
-- On reject, State is unchanged.

procedure Try_Chunk_Transition
  (State : in out Authority; Target : Residency; Result : out Attempt);
-- The only edges are Unloaded→Loading→Loaded→Active→Inactive→Saving→Unloaded.
-- Any other edge is rejected and Chunk is unchanged.

procedure Try_Retire_Handle
  (Pool : in out Entity_Pool; Handle : Entity_Handle; Result : out Attempt);
-- Rejects a stale or dead handle.
-- Rejects retirement when the generation is already Unsigned_32'Last,
-- so a generation cannot wrap onto a live object.
-- On accept, the generation increments and the slot is not live,
-- and Handle_Valid is false for the retired handle.
-- On reject, the pool is unchanged.

procedure Try_Save
  (State : in out Authority; Step : Save_Step; Durable : Boolean; Result : out Attempt);
-- Take_Snapshot moves Idle → Snapshot_Ready. It does not increment
-- Committed_Generation.
-- Commit with Durable moves Snapshot_Ready → Idle and increments
-- Committed_Generation.
-- Commit without Durable, or any failed commit, returns to Idle and does
-- not increment Committed_Generation. A failed save is not a successful commit.

procedure Try_Set_Permission
  (State : in out Authority;
   Actor_May_Set : Boolean;
   New_Level : Permission_Level;
   Result : out Attempt);
-- Rejected when Actor_May_Set is false. Permission is unchanged.
```

## Proofs

These postconditions are the section 72 obligations for classified writes, handles, inventory conservation, and the save generation. They are checked at runtime. `gnatprove` discharge is Phase 6 and is not claimed.

The simulation packages (`World`, `Physics`, `AI`, `Redstone`, `Fluids`, `Lighting`) are not part of this kernel and are not proved.
