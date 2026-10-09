with Adacraft.Protocol.Ids;

package body Adacraft.Protocol.State.Table
  with SPARK_Mode => On
is
   subtype Packet_Name is Ids.Packet_Name;
   use type Ids.Packet_Name;

   subtype Cb_Configuration_Names is Packet_Name range
     Ids.Cb_Configuration_Clear_Dialog .. Ids.Cb_Configuration_Update_Tags;
   subtype Cb_Login_Names is Packet_Name range
     Ids.Cb_Login_Cookie_Request .. Ids.Cb_Login_Login_Finished;
   subtype Cb_Play_Names is Packet_Name range
     Ids.Cb_Play_Add_Entity .. Ids.Cb_Play_Waypoint;
   subtype Cb_Status_Names is Packet_Name range
     Ids.Cb_Status_Pong_Response .. Ids.Cb_Status_Status_Response;
   subtype Sb_Configuration_Names is Packet_Name range
     Ids.Sb_Configuration_Accept_Code_Of_Conduct
       .. Ids.Sb_Configuration_Select_Known_Packs;
   subtype Sb_Login_Names is Packet_Name range
     Ids.Sb_Login_Cookie_Response .. Ids.Sb_Login_Login_Acknowledged;
   subtype Sb_Play_Names is Packet_Name range
     Ids.Sb_Play_Accept_Teleportation .. Ids.Sb_Play_Use_Item_On;
   subtype Sb_Status_Names is Packet_Name range
     Ids.Sb_Status_Ping_Request .. Ids.Sb_Status_Status_Request;

   Sb_Login_Count : constant :=
     Sb_Login_Names'Pos (Sb_Login_Names'Last)
     - Sb_Login_Names'Pos (Sb_Login_Names'First) + 1;
   Sb_Configuration_Count : constant :=
     Sb_Configuration_Names'Pos (Sb_Configuration_Names'Last)
     - Sb_Configuration_Names'Pos (Sb_Configuration_Names'First) + 1;
   Sb_Play_Count : constant :=
     Sb_Play_Names'Pos (Sb_Play_Names'Last)
     - Sb_Play_Names'Pos (Sb_Play_Names'First) + 1;

   Total : constant :=
     Packet_Name'Pos (Packet_Name'Last) + 1
     + Sb_Login_Count + Sb_Configuration_Count + Sb_Play_Count;

   type Row_Array is array (Positive range 1 .. Total) of Row;

   Blank : constant Row :=
     (State      => Handshake,
      Direction  => Serverbound,
      Id         => 0,
      Name_First => 1,
      Name_Last  => 0);

   function State_Of (N : Packet_Name) return Parent_State is
     (if N in Cb_Configuration_Names | Sb_Configuration_Names then Configuration
      elsif N in Cb_Login_Names | Sb_Login_Names then Login
      elsif N in Cb_Play_Names | Sb_Play_Names then Play
      elsif N in Cb_Status_Names | Sb_Status_Names then Status
      else Handshake);

   function Direction_Of (N : Packet_Name) return Packet_Direction is
     (if N >= Ids.Sb_Configuration_Accept_Code_Of_Conduct
      then Serverbound else Clientbound);

   function Pending_Of (S : Parent_State) return Connection_State is
     (case S is
         when Login         => Login_Awaiting_Ack,
         when Configuration => Configuration_Awaiting_Ack,
         when Play          => Play_Awaiting_Config_Ack,
         when others        => S);

   --  Names_Text holds the images of all packet names back to back, in
   --  Packet_Name order. Ends (N) is the index of the last character of N.
   type Offset_Array is array (Packet_Name) of Natural;

   function Build_Ends return Offset_Array is
      Result : Offset_Array := (others => 0);
      Sum    : Natural := 0;
   begin
      for N in Packet_Name loop
         Sum := Sum + Packet_Name'Image (N)'Length;
         Result (N) := Sum;
      end loop;
      return Result;
   end Build_Ends;

   Ends        : constant Offset_Array := Build_Ends;
   Names_Total : constant Natural := Ends (Packet_Name'Last);

   function Build_Names return String is
      Result : String (1 .. Names_Total) := (others => ' ');
   begin
      for N in Packet_Name loop
         declare
            Img   : constant String := Packet_Name'Image (N);
            Last  : constant Natural := Ends (N);
            First : constant Natural := Last - Img'Length + 1;
         begin
            Result (First .. Last) := Img;
         end;
      end loop;
      return Result;
   end Build_Names;

   Names_Text : constant String := Build_Names;

   function Make
     (S : Connection_State;
      D : Packet_Direction;
      N : Packet_Name) return Row
   is
      Last : constant Natural := Ends (N);
   begin
      return (State      => S,
              Direction  => D,
              Id         => Packet_Id (Ids.Protocol_Id (N)),
              Name_First => Last - Packet_Name'Image (N)'Length + 1,
              Name_Last  => Last);
   end Make;

   function Less (A, B : Row) return Boolean is
     (A.State < B.State
      or else (A.State = B.State
               and then (A.Direction < B.Direction
                         or else (A.Direction = B.Direction
                                  and then A.Id < B.Id))));

   function Build_Rows return Row_Array is
      Result : Row_Array := (others => Blank);
      Count  : Natural := 0;
   begin
      for N in Packet_Name loop
         declare
            S : constant Parent_State := State_Of (N);
            D : constant Packet_Direction := Direction_Of (N);
         begin
            Count := Count + 1;
            Result (Count) := Make (S, D, N);
            if D = Serverbound and then S in Login | Configuration | Play then
               Count := Count + 1;
               Result (Count) := Make (Pending_Of (S), D, N);
            end if;
         end;
      end loop;

      for I in 2 .. Total loop
         declare
            Cur : constant Row := Result (I);
            J   : Natural := I - 1;
         begin
            while J >= 1 and then Less (Cur, Result (J)) loop
               Result (J + 1) := Result (J);
               J := J - 1;
            end loop;
            Result (J + 1) := Cur;
         end;
      end loop;
      return Result;
   end Build_Rows;

   Rows : constant Row_Array := Build_Rows;

   type Bounds is record
      First : Positive;
      Last  : Natural;
   end record;

   type Slice_Array is array (Connection_State, Packet_Direction) of Bounds;

   function Build_Slices return Slice_Array is
      Result : Slice_Array :=
        (others => (others => (First => 1, Last => 0)));
   begin
      for I in Rows'Range loop
         declare
            S : constant Connection_State := Rows (I).State;
            D : constant Packet_Direction := Rows (I).Direction;
         begin
            if Result (S, D).Last = 0 then
               Result (S, D) := (First => I, Last => I);
            else
               Result (S, D).Last := I;
            end if;
         end;
      end loop;
      return Result;
   end Build_Slices;

   Slices : constant Slice_Array := Build_Slices;

   function Row_Count return Positive is (Total);

   function Row_At (I : Positive) return Row is (Rows (I));

   function Find
     (State : Connection_State;
      Dir   : Packet_Direction;
      Id    : Packet_Id) return Natural
   is
      B : constant Bounds := Slices (State, Dir);
   begin
      for I in B.First .. B.Last loop
         if Rows (I).Id = Id then
            return I;
         end if;
      end loop;
      return 0;
   end Find;

   function Is_Known_Id (Id : Packet_Id) return Boolean is
   begin
      for I in Rows'Range loop
         if Rows (I).Id = Id then
            return True;
         end if;
      end loop;
      return False;
   end Is_Known_Id;

   function Name (I : Positive) return String is
     (Names_Text (Rows (I).Name_First .. Rows (I).Name_Last));

   function Is_Login_Start_Id (Id : Packet_Id) return Boolean is
     (Id = Packet_Id (Ids.Protocol_Id (Ids.Sb_Login_Hello)));

   function Is_Login_Ack_Id (Id : Packet_Id) return Boolean is
     (Id = Packet_Id (Ids.Protocol_Id (Ids.Sb_Login_Login_Acknowledged)));

   function Is_Serverbound_Login
     (State : Connection_State;
      Id    : Packet_Id) return Boolean
   is
   begin
      if State /= Login and then State /= Login_Awaiting_Ack then
         return False;
      end if;
      return Find (State, Serverbound, Id) /= 0
        and then (Is_Login_Start_Id (Id) or else Is_Login_Ack_Id (Id));
   end Is_Serverbound_Login;
end Adacraft.Protocol.State.Table;
