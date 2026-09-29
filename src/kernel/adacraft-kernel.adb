package body Adacraft.Kernel
  with SPARK_Mode
is
   use type Interfaces.Unsigned_32;
   function Required_Level (Command : Command_Id) return Permission_Level is
     (case Command is
         when Teleport | Gamemode | Give | Kill | Time_Set | Weather
            | Difficulty | Set_World_Spawn => 2,
         when Unknown => 4);

   function Legal_Chunk (From, To : Residency) return Boolean is
     ((From = Unloaded and then To = Loading)
      or else (From = Loading and then To = Loaded)
      or else (From = Loaded and then To = Active)
      or else (From = Active and then To = Inactive)
      or else (From = Inactive and then To = Saving)
      or else (From = Saving and then To = Unloaded));

   procedure Try_Move (State : in out Authority; Request : Move_Request; Result : out Attempt) is
   begin
      if not (Request.Player_Live and Request.Chunk_Active
              and Request.Collision_Free and Request.Within_Rules)
      then
         Result := Rejected;
         return;
      end if;
      State.Position := Request.Target;
      Result := Accepted;
         return;
   end Try_Move;

   procedure Try_Break_Block
     (State : in out Authority; Request : Break_Request; Result : out Attempt)
   is
   begin
      if not (Request.Player_Live and Request.Chunk_Active
              and Request.In_Reach and Request.Legal)
      then
         Result := Rejected;
         return;
      end if;
      if State.Breaks = Natural'Last
        or else State.Drops > Natural'Last - Request.Drop_Count
      then
         Result := Rejected;
         return;
      end if;
      State.Breaks := State.Breaks + 1;
      State.Drops := State.Drops + Request.Drop_Count;
      Result := Accepted;
         return;
   end Try_Break_Block;

   procedure Try_Place_Block
     (State : in out Authority; Request : Place_Request; Result : out Attempt)
   is
   begin
      if not (Request.Player_Live and Request.Chunk_Active and Request.In_Reach
              and Request.Legal and Request.Collision_Free)
      then
         Result := Rejected;
         return;
      end if;
      if State.Placements = Natural'Last then
         Result := Rejected;
         return;
      end if;
      State.Placements := State.Placements + 1;
      Result := Accepted;
         return;
   end Try_Place_Block;

   procedure Try_Inventory_Move
     (Source : in out Stack;
      Destination : in out Stack;
      Amount : Stack_Count;
      Result : out Attempt)
   is
   begin
      if Amount = 0 or else Amount > Source.Count or else Amount > Source.Max_Count then
         Result := Rejected;
         return;
      end if;
      if Destination.Count = 0 then
         Destination.Item := Source.Item;
         Destination.Max_Count := Source.Max_Count;
         Destination.Count := Amount;
         Source.Count := Source.Count - Amount;
         if Source.Count = 0 then
            Source.Item := 0;
         end if;
         Result := Accepted;
         return;
      end if;
      if Destination.Item /= Source.Item
        or else Destination.Max_Count < Amount
        or else Destination.Count > Destination.Max_Count - Amount
      then
         Result := Rejected;
         return;
      end if;
      Destination.Count := Destination.Count + Amount;
      Source.Count := Source.Count - Amount;
      if Source.Count = 0 then
         Source.Item := 0;
      end if;
      Result := Accepted;
         return;
   end Try_Inventory_Move;

   procedure Try_Execute_Command
     (State : in out Authority; Command : Command_Id; Result : out Attempt)
   is
   begin
      if Command = Unknown or else State.Permission < Required_Level (Command) then
         Result := Rejected;
         return;
      end if;
      if State.Commands_Accepted = Natural'Last then
         Result := Rejected;
         return;
      end if;
      State.Last_Command := Command;
      State.Commands_Accepted := State.Commands_Accepted + 1;
      Result := Accepted;
         return;
   end Try_Execute_Command;

   procedure Try_Chunk_Transition
     (State : in out Authority; Target : Residency; Result : out Attempt)
   is
   begin
      if not Legal_Chunk (State.Chunk, Target) then
         Result := Rejected;
         return;
      end if;
      State.Chunk := Target;
      Result := Accepted;
         return;
   end Try_Chunk_Transition;

   function Handle_Valid (Pool : Entity_Pool; Handle : Entity_Handle) return Boolean is
     (Pool (Handle.ID).Live
      and then Pool (Handle.ID).Generation = Handle.Generation);

   procedure Try_Retire_Handle
     (Pool : in out Entity_Pool; Handle : Entity_Handle; Result : out Attempt)
   is
   begin
      if not Handle_Valid (Pool, Handle) then
         Result := Rejected;
         return;
      end if;
      if Pool (Handle.ID).Generation = Interfaces.Unsigned_32'Last then
         Result := Rejected;
         return;
      end if;
      Pool (Handle.ID).Generation := Pool (Handle.ID).Generation + 1;
      Pool (Handle.ID).Live := False;
      Result := Accepted;
         return;
   end Try_Retire_Handle;

   procedure Try_Save
     (State : in out Authority; Step : Save_Step; Durable : Boolean; Result : out Attempt)
   is
   begin
      case Step is
         when Take_Snapshot =>
            if State.Save /= Idle then
               Result := Rejected;
         return;
            end if;
            State.Save := Snapshot_Ready;
            Result := Accepted;
         return;
         when Commit =>
            if State.Save /= Snapshot_Ready or else not Durable then
               State.Save := Idle;
               Result := Rejected;
         return;
            end if;
            if State.Committed_Generation = Natural'Last then
               State.Save := Idle;
               Result := Rejected;
         return;
            end if;
            State.Committed_Generation := State.Committed_Generation + 1;
            State.Save := Idle;
            Result := Accepted;
         return;
      end case;
   end Try_Save;

   procedure Try_Set_Permission
     (State : in out Authority;
      Actor_May_Set : Boolean;
      New_Level : Permission_Level;
      Result : out Attempt)
   is
   begin
      if not Actor_May_Set then
         Result := Rejected;
         return;
      end if;
      State.Permission := New_Level;
      Result := Accepted;
         return;
   end Try_Set_Permission;
end Adacraft.Kernel;
