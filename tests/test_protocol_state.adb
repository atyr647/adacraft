with Ada.Command_Line;
with Ada.Text_IO;
with Adacraft.Protocol.Ids;
with Adacraft.Protocol.State;
with Adacraft.Protocol.State.Table;

procedure Test_Protocol_State is
   package S renames Adacraft.Protocol.State;
   package T renames Adacraft.Protocol.State.Table;
   package Ids renames Adacraft.Protocol.Ids;
   use type S.Connection_State;
   use type S.Packet_Direction;
   use type S.Packet_Id;
   use type S.Handshake_Intent;
   use type Ids.Packet_Name;

   Failures : Natural := 0;

   procedure Check (Condition : Boolean; Name : String) is
   begin
      if not Condition then
         Failures := Failures + 1;
         Ada.Text_IO.Put_Line ("FAIL: " & Name);
      end if;
   end Check;

   function Id_Of (N : Ids.Packet_Name) return S.Packet_Id is
     (S.Packet_Id (Ids.Protocol_Id (N)));

   function Cnt (First, Last : Ids.Packet_Name) return Natural is
     (Ids.Packet_Name'Pos (Last) - Ids.Packet_Name'Pos (First) + 1);

   function Expected_Count
     (St : S.Connection_State; D : S.Packet_Direction) return Natural is
     (case St is
         when S.Handshake =>
           (if D = S.Serverbound
            then Cnt (Ids.Sb_Handshake_Intention, Ids.Sb_Handshake_Intention)
            else 0),
         when S.Status =>
           (if D = S.Serverbound
            then Cnt (Ids.Sb_Status_Ping_Request, Ids.Sb_Status_Status_Request)
            else Cnt (Ids.Cb_Status_Pong_Response,
                      Ids.Cb_Status_Status_Response)),
         when S.Login | S.Login_Awaiting_Ack =>
           (if D = S.Serverbound
            then Cnt (Ids.Sb_Login_Cookie_Response,
                      Ids.Sb_Login_Login_Acknowledged)
            elsif St = S.Login
            then Cnt (Ids.Cb_Login_Cookie_Request,
                      Ids.Cb_Login_Login_Finished)
            else 0),
         when S.Configuration | S.Configuration_Awaiting_Ack =>
           (if D = S.Serverbound
            then Cnt (Ids.Sb_Configuration_Accept_Code_Of_Conduct,
                      Ids.Sb_Configuration_Select_Known_Packs)
            elsif St = S.Configuration
            then Cnt (Ids.Cb_Configuration_Clear_Dialog,
                      Ids.Cb_Configuration_Update_Tags)
            else 0),
         when S.Play | S.Play_Awaiting_Config_Ack =>
           (if D = S.Serverbound
            then Cnt (Ids.Sb_Play_Accept_Teleportation,
                      Ids.Sb_Play_Use_Item_On)
            elsif St = S.Play
            then Cnt (Ids.Cb_Play_Add_Entity, Ids.Cb_Play_Waypoint)
            else 0));

   function Pending_Of (St : S.Connection_State) return S.Connection_State is
     (case St is
         when S.Login         => S.Login_Awaiting_Ack,
         when S.Configuration => S.Configuration_Awaiting_Ack,
         when S.Play          => S.Play_Awaiting_Config_Ack,
         when others          => St);

   function Rows_In
     (St : S.Connection_State; D : S.Packet_Direction) return Natural
   is
      N : Natural := 0;
   begin
      for I in 1 .. T.Row_Count loop
         if T.Row_At (I).State = St and then T.Row_At (I).Direction = D then
            N := N + 1;
         end if;
      end loop;
      return N;
   end Rows_In;

   function In_Table
     (St : S.Connection_State; D : S.Packet_Direction; Id : S.Packet_Id)
      return Boolean is
   begin
      for I in 1 .. T.Row_Count loop
         declare
            R : constant T.Row := T.Row_At (I);
         begin
            if R.State = St and then R.Direction = D and then R.Id = Id then
               return True;
            end if;
         end;
      end loop;
      return False;
   end In_Table;

   function Key_Less (A, B : T.Row) return Boolean is
     (A.State < B.State
      or else (A.State = B.State
               and then (A.Direction < B.Direction
                         or else (A.Direction = B.Direction
                                  and then A.Id < B.Id))));

   function Is_Some_Name (Text : String) return Boolean is
   begin
      for N in Ids.Packet_Name loop
         if Ids.Packet_Name'Image (N) = Text then
            return True;
         end if;
      end loop;
      return False;
   end Is_Some_Name;

   Expected_Rows : constant Natural :=
     260
     + Cnt (Ids.Sb_Login_Cookie_Response, Ids.Sb_Login_Login_Acknowledged)
     + Cnt (Ids.Sb_Configuration_Accept_Code_Of_Conduct,
            Ids.Sb_Configuration_Select_Known_Packs)
     + Cnt (Ids.Sb_Play_Accept_Teleportation, Ids.Sb_Play_Use_Item_On);

   Start_Cfg : constant S.Packet_Id := Id_Of (Ids.Cb_Play_Start_Configuration);
   Finished  : constant S.Packet_Id := Id_Of (Ids.Cb_Login_Login_Finished);
   Ack       : constant S.Packet_Id := Id_Of (Ids.Sb_Login_Login_Acknowledged);
   Intention : constant S.Packet_Id := Id_Of (Ids.Sb_Handshake_Intention);
   Play_Ack  : constant S.Packet_Id :=
     Id_Of (Ids.Sb_Play_Configuration_Acknowledged);
begin
   --  Initial state and state type shape.
   Check (S.Initial_State = S.Handshake, "initial state is Handshake");
   Check (S.Parent_State'Last = S.Play, "parents end at Play");
   Check (S.Connection_State'Pos (S.Pending_State'First)
          = S.Connection_State'Pos (S.Play) + 1, "pending contiguous after parents");
   Check (S.Pending_State'First = S.Login_Awaiting_Ack
          and then S.Pending_State'Last = S.Play_Awaiting_Config_Ack,
          "pending range");
   Check (S.Connection_State'Pos (S.Handshake) = 0
          and then S.Connection_State'Pos (S.Status) = 1
          and then S.Connection_State'Pos (S.Login) = 2
          and then S.Connection_State'Pos (S.Configuration) = 3
          and then S.Connection_State'Pos (S.Play) = 4, "parent order");

   --  Provenance.
   Check (S.Protocol_Number = 777, "protocol number");
   Check (S.Minecraft_Version = "26.3", "minecraft version");
   Check (S.Report_Source = "vanilla 26.3 server.jar packet report (packets.json)",
          "report source");
   Check (S.Report_SHA256
          = "2f0486311f18b7d3ec232028f3bff82c657d2f0240d2d65a3df40408db926886",
          "report sha256");
   Check (S.Server_Jar_SHA256
          = "d052f14d7a173734fba553711e5b570162e2f2a313267ee31a21b975a679be64",
          "server jar sha256");

   --  Table integrity.
   Check (Ids.Packet_Name'Pos (Ids.Packet_Name'Last) + 1 = 260,
          "generated packet count");
   Check (T.Row_Count = Expected_Rows, "row count");
   declare
      Sorted : Boolean := True;
   begin
      for I in 2 .. T.Row_Count loop
         if not Key_Less (T.Row_At (I - 1), T.Row_At (I)) then
            Sorted := False;
         end if;
      end loop;
      Check (Sorted, "rows strictly sorted by (state, direction, id)");
   end;

   declare
      Counts_Ok : Boolean := True;
   begin
      for St in S.Connection_State loop
         for D in S.Packet_Direction loop
            if Rows_In (St, D) /= Expected_Count (St, D) then
               Counts_Ok := False;
               Ada.Text_IO.Put_Line
                 ("count mismatch " & S.Connection_State'Image (St) & " "
                  & S.Packet_Direction'Image (D));
            end if;
         end loop;
      end loop;
      Check (Counts_Ok, "rows per (state, direction)");
   end;

   declare
      Hits_Ok  : Boolean := True;
      Names_Ok : Boolean := True;
      Valid_Ok : Boolean := True;
   begin
      for I in 1 .. T.Row_Count loop
         declare
            R : constant T.Row := T.Row_At (I);
         begin
            if T.Find (R.State, R.Direction, R.Id) /= I then
               Hits_Ok := False;
            end if;
            if not S.Is_Packet_Valid (R.State, R.Direction, R.Id) then
               Valid_Ok := False;
            end if;
            if R.Name_First > R.Name_Last
              or else not Is_Some_Name (T.Name (I))
              or else T.Name (I)'Length /= R.Name_Last - R.Name_First + 1
            then
               Names_Ok := False;
            end if;
            if not T.Is_Known_Id (R.Id) then
               Hits_Ok := False;
            end if;
         end;
      end loop;
      Check (Hits_Ok, "Find hits every row index and Is_Known_Id");
      Check (Valid_Ok, "Is_Packet_Valid true for every table triple");
      Check (Names_Ok, "Name slices are packet names");
   end;

   --  Find misses.
   declare
      Miss_Ok : Boolean := True;
   begin
      for St in S.Connection_State loop
         for D in S.Packet_Direction loop
            if T.Find (St, D, S.Packet_Id'First) /= 0
              or else T.Find (St, D, S.Packet_Id'Last) /= 0
              or else T.Find (St, D, -1) /= 0
              or else T.Find (St, D, 100_000) /= 0
            then
               Miss_Ok := False;
            end if;
         end loop;
      end loop;
      Check (Miss_Ok, "Find misses return 0 for out-of-range ids");
   end;
   Check (not T.Is_Known_Id (S.Packet_Id'First), "Is_Known_Id first");
   Check (not T.Is_Known_Id (S.Packet_Id'Last), "Is_Known_Id last");
   Check (not T.Is_Known_Id (-1), "Is_Known_Id negative");

   --  Names.
   Check (T.Name (T.Find (S.Handshake, S.Serverbound, Intention))
          = Ids.Packet_Name'Image (Ids.Sb_Handshake_Intention),
          "name of Intention");
   Check (T.Name (T.Find (S.Login_Awaiting_Ack, S.Serverbound, Ack))
          = Ids.Packet_Name'Image (Ids.Sb_Login_Login_Acknowledged),
          "name of pending acknowledgement row");
   Check (T.Name (T.Find (S.Play, S.Clientbound, Start_Cfg))
          = Ids.Packet_Name'Image (Ids.Cb_Play_Start_Configuration),
          "name of Start Configuration");
   Check (T.Name (T.Find (S.Login, S.Clientbound, Finished))
          = Ids.Packet_Name'Image (Ids.Cb_Login_Login_Finished),
          "name of Login Finished");

   --  Is_Packet_Valid: exact against an oracle over the table.
   declare
      Exact_Ok : Boolean := True;
   begin
      for St in S.Connection_State loop
         for D in S.Packet_Direction loop
            for V in -3 .. 400 loop
               if S.Is_Packet_Valid (St, D, S.Packet_Id (V))
                 /= In_Table (St, D, S.Packet_Id (V))
               then
                  Exact_Ok := False;
               end if;
            end loop;
            if S.Is_Packet_Valid (St, D, S.Packet_Id'First)
              or else S.Is_Packet_Valid (St, D, S.Packet_Id'Last)
            then
               Exact_Ok := False;
            end if;
         end loop;
      end loop;
      Check (Exact_Ok, "Is_Packet_Valid is exact table membership");
   end;

   --  Spot checks: same id valid in one state or direction, not another.
   Check (S.Is_Packet_Valid (S.Handshake, S.Serverbound, Intention),
          "Intention valid in Handshake serverbound");
   Check (not S.Is_Packet_Valid (S.Handshake, S.Clientbound, Intention),
          "Intention id invalid in Handshake clientbound");
   Check (S.Is_Packet_Valid (S.Play, S.Clientbound, Start_Cfg),
          "Start Configuration valid in Play clientbound");
   Check (not S.Is_Packet_Valid (S.Play, S.Serverbound, Start_Cfg),
          "Start Configuration id invalid in Play serverbound");
   Check (not S.Is_Packet_Valid (S.Handshake, S.Serverbound, Start_Cfg),
          "Start Configuration id invalid in Handshake");
   Check (not S.Is_Packet_Valid (S.Play_Awaiting_Config_Ack, S.Clientbound,
                                 Start_Cfg),
          "Start Configuration id invalid in pending Play clientbound");
   Check (S.Is_Packet_Valid (S.Login, S.Clientbound, Finished),
          "Login Finished valid in Login clientbound");
   Check (not S.Is_Packet_Valid (S.Status, S.Clientbound, Finished)
          and then not S.Is_Packet_Valid (S.Status, S.Serverbound, Finished),
          "Login Finished id invalid in Status");
   Check (not S.Is_Packet_Valid (S.Login_Awaiting_Ack, S.Clientbound, Finished),
          "Login Finished invalid in Login_Awaiting_Ack clientbound");
   Check (S.Is_Packet_Valid (S.Login, S.Serverbound, Ack),
          "Login Acknowledged is table-valid in Login (no ordering rule here)");
   Check (S.Is_Packet_Valid (S.Login_Awaiting_Ack, S.Serverbound, Ack),
          "Login Acknowledged valid in Login_Awaiting_Ack serverbound");
   Check (S.Is_Packet_Valid (S.Play, S.Serverbound, Play_Ack)
          and then S.Is_Packet_Valid (S.Play_Awaiting_Config_Ack, S.Serverbound,
                                      Play_Ack),
          "Configuration Acknowledged valid in Play and pending");

   --  Pending sub-states: serverbound copy of parent, no clientbound rows.
   declare
      Copy_Ok : Boolean := True;
      CB_Ok   : Boolean := True;
   begin
      for I in 1 .. T.Row_Count loop
         declare
            R : constant T.Row := T.Row_At (I);
         begin
            if R.Direction = S.Serverbound
              and then R.State in S.Login | S.Configuration | S.Play
              and then not S.Is_Packet_Valid
                             (Pending_Of (R.State), S.Serverbound, R.Id)
            then
               Copy_Ok := False;
            end if;
            if R.State in S.Pending_State
              and then R.Direction = S.Clientbound
            then
               CB_Ok := False;
            end if;
         end;
      end loop;
      Check (Copy_Ok, "pending states copy parent serverbound rows");
      Check (CB_Ok, "pending states have no clientbound rows");
      for St in S.Pending_State loop
         for V in -1 .. 400 loop
            if S.Is_Packet_Valid (St, S.Clientbound, S.Packet_Id (V)) then
               CB_Ok := False;
            end if;
         end loop;
      end loop;
      Check (CB_Ok, "no clientbound id valid in any pending state");
   end;

   --  Transition function.
   declare
      use type S.Result_Kind;
      use type S.Rejection_Reason;

      Fin_CB : constant S.Packet_Id :=
        Id_Of (Ids.Cb_Configuration_Finish_Configuration);
      Fin_SB : constant S.Packet_Id :=
        Id_Of (Ids.Sb_Configuration_Finish_Configuration);

      function Step
        (Cur    : S.Connection_State;
         D      : S.Packet_Direction;
         Id     : S.Packet_Id;
         Intent : S.Handshake_Intent := 0) return S.Transition_Result is
        (S.Transition (Cur, (Direction => D, Id => Id, Intent => Intent)));

      procedure Expect_Move
        (Name   : String;
         Cur    : S.Connection_State;
         D      : S.Packet_Direction;
         Id     : S.Packet_Id;
         Intent : S.Handshake_Intent;
         Target : S.Connection_State)
      is
         Res : constant S.Transition_Result := Step (Cur, D, Id, Intent);
      begin
         Check (Res.Kind = S.Accepted_Transition
                and then Res.Next_State = Target
                and then Res.Reason = S.No_Rejection, Name);
      end Expect_Move;

      procedure Expect_Reject
        (Name   : String;
         Cur    : S.Connection_State;
         D      : S.Packet_Direction;
         Id     : S.Packet_Id;
         Intent : S.Handshake_Intent;
         Reason : S.Rejection_Reason)
      is
         Res : constant S.Transition_Result := Step (Cur, D, Id, Intent);
      begin
         Check (Res.Kind = S.Rejected
                and then Res.Reason = Reason
                and then Res.Next_State = Cur, Name);
      end Expect_Reject;

      function Same (A, B : S.Transition_Result) return Boolean is
        (A.Kind = B.Kind and then A.Next_State = B.Next_State
         and then A.Reason = B.Reason);
   begin
      --  One test per transition row.
      Expect_Move ("Handshake intent 1 -> Status",
                   S.Handshake, S.Serverbound, Intention, 1, S.Status);
      Expect_Move ("Handshake intent 2 -> Login",
                   S.Handshake, S.Serverbound, Intention, 2, S.Login);
      Expect_Move ("Handshake intent 3 -> Login",
                   S.Handshake, S.Serverbound, Intention, 3, S.Login);
      Expect_Move ("Login Finished -> Login_Awaiting_Ack",
                   S.Login, S.Clientbound, Finished, 0,
                   S.Login_Awaiting_Ack);
      Expect_Move ("Login Acknowledged -> Configuration",
                   S.Login_Awaiting_Ack, S.Serverbound, Ack, 0,
                   S.Configuration);
      Expect_Move ("Finish Configuration -> Configuration_Awaiting_Ack",
                   S.Configuration, S.Clientbound, Fin_CB, 0,
                   S.Configuration_Awaiting_Ack);
      Expect_Move ("Finish Configuration ack -> Play",
                   S.Configuration_Awaiting_Ack, S.Serverbound, Fin_SB, 0,
                   S.Play);
      Expect_Move ("Start Configuration -> Play_Awaiting_Config_Ack",
                   S.Play, S.Clientbound, Start_Cfg, 0,
                   S.Play_Awaiting_Config_Ack);
      Expect_Move ("Configuration Acknowledged -> Configuration",
                   S.Play_Awaiting_Config_Ack, S.Serverbound, Play_Ack, 0,
                   S.Configuration);

      --  D6: table validity versus ordering.
      Check (S.Is_Packet_Valid (S.Login, S.Serverbound, Ack),
             "D6: Login Acknowledged table-valid in Login");
      Expect_Reject ("D6: Login Acknowledged in Login is Invalid_Transition",
                     S.Login, S.Serverbound, Ack, 0, S.Invalid_Transition);

      --  Triggers outside their From state.
      Expect_Reject ("Finish Configuration ack in Configuration",
                     S.Configuration, S.Serverbound, Fin_SB, 0,
                     S.Invalid_Transition);
      Expect_Reject ("Configuration Acknowledged in Play",
                     S.Play, S.Serverbound, Play_Ack, 0,
                     S.Invalid_Transition);
      Expect_Reject ("Login Finished is not repeated in Login_Awaiting_Ack",
                     S.Login_Awaiting_Ack, S.Clientbound, Finished, 0,
                     S.Packet_Not_Valid_In_State);

      --  Rejection reasons.
      Expect_Reject ("Unknown id (large)", S.Play, S.Serverbound, 100_000, 0,
                     S.Unknown_Packet_Id);
      Expect_Reject ("Unknown id (negative)", S.Login, S.Clientbound, -1, 0,
                     S.Unknown_Packet_Id);
      Expect_Reject ("Unknown id (first)", S.Status, S.Serverbound,
                     S.Packet_Id'First, 0, S.Unknown_Packet_Id);
      Expect_Reject ("Unknown id (last)", S.Status, S.Clientbound,
                     S.Packet_Id'Last, 0, S.Unknown_Packet_Id);
      Expect_Reject ("Wrong direction", S.Handshake, S.Clientbound,
                     Intention, 1, S.Wrong_Direction);
      Expect_Reject ("Not valid in state", S.Handshake, S.Serverbound,
                     Start_Cfg, 0, S.Packet_Not_Valid_In_State);
      Expect_Reject ("Intent 0 invalid", S.Handshake, S.Serverbound,
                     Intention, 0, S.Invalid_Handshake_Intent);
      Expect_Reject ("Intent 4 invalid", S.Handshake, S.Serverbound,
                     Intention, 4, S.Invalid_Handshake_Intent);
      Expect_Reject ("Intent -1 invalid", S.Handshake, S.Serverbound,
                     Intention, -1, S.Invalid_Handshake_Intent);
      Expect_Reject ("Intent first invalid", S.Handshake, S.Serverbound,
                     Intention, S.Handshake_Intent'First,
                     S.Invalid_Handshake_Intent);
      Expect_Reject ("Intent last invalid", S.Handshake, S.Serverbound,
                     Intention, S.Handshake_Intent'Last,
                     S.Invalid_Handshake_Intent);

      --  Status has no outgoing transitions.
      declare
         Status_Ok : Boolean := True;
         Seen      : Natural := 0;
      begin
         for I in 1 .. T.Row_Count loop
            declare
               R   : constant T.Row := T.Row_At (I);
               Res : S.Transition_Result;
            begin
               if R.State = S.Status then
                  Seen := Seen + 1;
                  Res := Step (S.Status, R.Direction, R.Id);
                  if Res.Kind /= S.Accepted_No_Transition
                    or else Res.Next_State /= S.Status
                    or else Res.Reason /= S.No_Rejection
                  then
                     Status_Ok := False;
                  end if;
               end if;
            end;
         end loop;
         Check (Seen > 0 and then Status_Ok,
                "valid Status packets accepted without transition");
      end;
      Expect_Reject ("Login Finished in Status", S.Status, S.Clientbound,
                     Finished, 0, S.Packet_Not_Valid_In_State);
      Expect_Reject ("Start Configuration in Status", S.Status, S.Clientbound,
                     Start_Cfg, 0, S.Packet_Not_Valid_In_State);
      Expect_Reject ("Configuration Acknowledged in Status", S.Status,
                     S.Serverbound, Play_Ack, 0,
                     S.Packet_Not_Valid_In_State);

      --  Accepted-no-transition returns the current state.
      declare
         Res : constant S.Transition_Result :=
           Step (S.Play, S.Serverbound, Id_Of (Ids.Sb_Play_Use_Item));
      begin
         Check (Res.Kind = S.Accepted_No_Transition
                and then Res.Next_State = S.Play
                and then Res.Reason = S.No_Rejection,
                "non-trigger Play packet leaves state unchanged");
      end;

      --  Intent is irrelevant for everything except Intention, and the
      --  result is consistent for every state, direction and id.
      declare
         Irrelevant_Ok : Boolean := True;
         Shape_Ok      : Boolean := True;
         Valid_Gate_Ok : Boolean := True;
      begin
         for St in S.Connection_State loop
            for D in S.Packet_Direction loop
               for V in -3 .. 400 loop
                  declare
                     Id  : constant S.Packet_Id := S.Packet_Id (V);
                     Res : constant S.Transition_Result :=
                       Step (St, D, Id, 0);
                  begin
                     if not (St = S.Handshake and then D = S.Serverbound
                             and then Id = Intention)
                     then
                        for K in -3 .. 5 loop
                           if not Same (Res,
                                        Step (St, D, Id,
                                              S.Handshake_Intent (K)))
                             or else not Same
                               (Res,
                                Step (St, D, Id,
                                      S.Handshake_Intent'Last))
                             or else not Same
                               (Res,
                                Step (St, D, Id,
                                      S.Handshake_Intent'First))
                           then
                              Irrelevant_Ok := False;
                           end if;
                        end loop;
                     end if;
                     case Res.Kind is
                        when S.Accepted_Transition =>
                           if Res.Reason /= S.No_Rejection then
                              Shape_Ok := False;
                           end if;
                        when S.Accepted_No_Transition =>
                           if Res.Reason /= S.No_Rejection
                             or else Res.Next_State /= St
                           then
                              Shape_Ok := False;
                           end if;
                        when S.Rejected =>
                           if Res.Reason = S.No_Rejection
                             or else Res.Next_State /= St
                           then
                              Shape_Ok := False;
                           end if;
                     end case;
                     if not S.Is_Packet_Valid (St, D, Id)
                       and then Res.Kind /= S.Rejected
                     then
                        Valid_Gate_Ok := False;
                     end if;
                     if S.Is_Packet_Valid (St, D, Id)
                       and then Res.Kind = S.Rejected
                       and then Res.Reason in S.Unknown_Packet_Id
                                            | S.Wrong_Direction
                                            | S.Packet_Not_Valid_In_State
                     then
                        Valid_Gate_Ok := False;
                     end if;
                  end;
               end loop;
            end loop;
         end loop;
         Check (Irrelevant_Ok, "intent irrelevant for non-Intention packets");
         Check (Shape_Ok, "result shape: next state and reason consistent");
         Check (Valid_Gate_Ok, "table-invalid is rejected, table-valid is not");
      end;

      --  Full ordered handshake-to-play-and-back walk.
      declare
         Cur : S.Connection_State := S.Initial_State;
      begin
         Cur := Step (Cur, S.Serverbound, Intention, 2).Next_State;
         Cur := Step (Cur, S.Clientbound, Finished).Next_State;
         Cur := Step (Cur, S.Serverbound, Ack).Next_State;
         Cur := Step (Cur, S.Clientbound, Fin_CB).Next_State;
         Cur := Step (Cur, S.Serverbound, Fin_SB).Next_State;
         Check (Cur = S.Play, "walk reaches Play");
         Cur := Step (Cur, S.Clientbound, Start_Cfg).Next_State;
         Cur := Step (Cur, S.Serverbound, Play_Ack).Next_State;
         Check (Cur = S.Configuration, "reconfiguration returns to Configuration");
      end;
   end;

   if Failures = 0 then
      Ada.Text_IO.Put_Line ("test_protocol_state: ok");
   else
      Ada.Text_IO.Put_Line ("test_protocol_state: failures" & Natural'Image (Failures));
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
   end if;
end Test_Protocol_State;
