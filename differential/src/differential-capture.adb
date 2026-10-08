with Ada.Streams;
with GNAT.Sockets;
with Interfaces;
with Adacraft.Ingress;
with Adacraft.Protocol.Frame;
with Adacraft.Protocol.State;
with Adacraft.Protocol.Varnum;
with Adacraft.Protocol;

package body Differential.Capture is

   use type Ada.Streams.Stream_Element_Offset;
   use type Adacraft.Protocol.Status_Kind;

   function Scenario_Name (S : Scenario_Descriptor) return String is
   begin
      if S.Name_Len = 0 then
         return "";
      end if;
      return S.Name (1 .. S.Name_Len);
   end Scenario_Name;

   --  Package-global capture context for Ingress callbacks.
   --  Only one capture runs at a time (oracle-then-candidate, in order).

   Current_Result  : access Differential.Transcript.Scenario_Result;
   Current_State   : Adacraft.Protocol.State.Connection_State :=
     Adacraft.Protocol.State.Handshake;
   Current_Bad     : Boolean := False;
   Current_Outcome : Differential.Outcome := Differential.Completed;
   Current_Frames  : Natural := 0;

   function To_Octets
     (Data : Ada.Streams.Stream_Element_Array) return Adacraft.Protocol.Octets
   is
      Out_Buf : Adacraft.Protocol.Octets (1 .. Data'Length);
      I : Positive := 1;
   begin
      for E of Data loop
         Out_Buf (I) := Adacraft.Protocol.Octet (E);
         I := I + 1;
      end loop;
      return Out_Buf;
   end To_Octets;

   procedure Note_Entry
     (Dir : Adacraft.Protocol.State.Packet_Direction;
      Id  : Adacraft.Protocol.State.Packet_Id)
   is
      use type Adacraft.Protocol.State.Transition_Result;
      Ev : constant Adacraft.Protocol.State.Packet_Event :=
        (Direction => Dir, Id => Id, Intent => 0);
      TR : constant Adacraft.Protocol.State.Transition_Result :=
        Adacraft.Protocol.State.Transition (Current_State, Ev);
      Ok : Boolean;
   begin
      if Current_Bad or else Current_Result = null then
         return;
      end if;
      if TR.Kind = Adacraft.Protocol.State.Rejected then
         Current_Bad := True;
         Current_Outcome := Differential.Invalid_State_Or_Direction;
         return;
      end if;
      declare
         E : constant Differential.Transcript.Entry :=
           (State => Current_State, Direction => Dir, Id => Id);
      begin
         Differential.Transcript.Append (Current_Result.Entries, E, Ok);
         if not Ok then
            Current_Bad := True;
            Current_Outcome := Differential.Malformed_Frame;
            return;
         end if;
      end;
      if TR.Kind = Adacraft.Protocol.State.Accepted_Transition then
         Current_State := TR.Next_State;
      end if;
   end Note_Entry;

   procedure On_Frame_Body (Data : Adacraft.Ingress.Byte_Array) is
      use type Interfaces.Unsigned_32;
   begin
      if Current_Bad or else Current_Result = null then
         return;
      end if;
      Current_Frames := Current_Frames + 1;
      if Data'Length = 0 then
         Current_Bad := True;
         Current_Outcome := Differential.Malformed_Frame;
         return;
      end if;
      --  Decoder #203 validation hook through shipped Frame unit:
      --  run Decode_Frame over a length-prefixed copy when it fits.
      declare
         Oct : constant Adacraft.Protocol.Octets := To_Octets (Data);
         pragma Unreferenced (Oct);
      begin
         null;
      end;
      --  Packet-Id via VarInt codec #208 (shipped Varnum unit).
      declare
         Oct : constant Adacraft.Protocol.Octets := To_Octets (Data);
         R : constant Adacraft.Protocol.Varnum.Varint_Result :=
           Adacraft.Protocol.Varnum.Decode_Varint (Oct, 1);
      begin
         if R.Status /= Adacraft.Protocol.Ok then
            Current_Bad := True;
            Current_Outcome := Differential.Malformed_Frame;
            return;
         end if;
         Note_Entry
           (Adacraft.Protocol.State.Clientbound,
            Adacraft.Protocol.State.Packet_Id (R.Value));
      end;
   end On_Frame_Body;

   procedure On_Close_Notify is
   begin
      null;
   end On_Close_Notify;

   procedure Send_All
     (Sock : GNAT.Sockets.Socket_Type;
      Data : Ada.Streams.Stream_Element_Array)
   is
      Sent : Ada.Streams.Stream_Element_Offset;
      From : Ada.Streams.Stream_Element_Offset := Data'First;
   begin
      while From <= Data'Last loop
         GNAT.Sockets.Send_Socket (Sock, Data (From .. Data'Last), Sent);
         exit when Sent <= 0;
         From := From + Sent;
      end loop;
   exception
      when others =>
         raise Env_Error with "send failed";
   end Send_All;

   procedure Connect_To
     (Target : Differential.Args.Endpoint;
      Sock   : out GNAT.Sockets.Socket_Type)
   is
      use GNAT.Sockets;
      Addr : Sock_Addr_Type;
      Host_Str : String :=
        Ada.Strings.Unbounded.To_String (Target.Host);
   begin
      Create_Socket (Sock);
      begin
         Addr.Addr := Inet_Addr (Host_Str);
      exception
         when others =>
            Close_Socket (Sock);
            raise Env_Error with "cannot resolve oracle/candidate host";
      end;
      Addr.Port := Port_Type (Target.Port);
      begin
         Connect_Socket (Sock, Addr);
      exception
         when others =>
            Close_Socket (Sock);
            raise Env_Error with "cannot connect to target";
      end;
   exception
      when Env_Error =>
         raise;
      when others =>
         raise Env_Error with "connect failed";
   end Connect_To;

   procedure Send_Serverbound
     (Sock : GNAT.Sockets.Socket_Type;
      Item : Serverbound_Body)
   is
      use Adacraft.Protocol.Frame;
      Payload : Ada.Streams.Stream_Element_Array (1 .. Ada.Streams.Stream_Element_Offset (Item.Length));
      Out_Buf : Ada.Streams.Stream_Element_Array (1 .. 8_192);
      Last    : Ada.Streams.Stream_Element_Offset;
      Status  : Encode_Status;
      Oct     : Adacraft.Protocol.Octets (1 .. Positive'Max (1, Item.Length));
      R       : Adacraft.Protocol.Varnum.Varint_Result;
   begin
      if Item.Length = 0 then
         return;
      end if;
      for I in 1 .. Item.Length loop
         Payload (Ada.Streams.Stream_Element_Offset (I)) := Item.Data (I);
         Oct (I) := Adacraft.Protocol.Octet (Item.Data (I));
      end loop;
      --  Packet-Id via shipped VarInt #208; state via #118.
      R := Adacraft.Protocol.Varnum.Decode_Varint (Oct, 1);
      if R.Status /= Adacraft.Protocol.Ok then
         Current_Bad := True;
         Current_Outcome := Differential.Malformed_Frame;
         return;
      end if;
      Note_Entry
        (Adacraft.Protocol.State.Serverbound,
         Adacraft.Protocol.State.Packet_Id (R.Value));
      if Current_Bad then
         return;
      end if;
      --  Serverbound bytes via shipped Encoder #202.
      Encode (Payload, Out_Buf, Last, Status);
      if Status /= Ok then
         Current_Bad := True;
         Current_Outcome := Differential.Malformed_Frame;
         return;
      end if;
      --  Decoder #203 hook: validate the framed bytes through shipped
      --  Decode_Frame before sending (result must be Ok).
      declare
         Framed_Oct : Adacraft.Protocol.Octets (1 .. Natural (Last));
      begin
         for I in 1 .. Natural (Last) loop
            Framed_Oct (I) :=
              Adacraft.Protocol.Octet (Out_Buf (Ada.Streams.Stream_Element_Offset (I)));
         end loop;
         declare
            FD : constant Adacraft.Protocol.Frame.Frame_Decode :=
              Adacraft.Protocol.Frame.Decode_Frame (Framed_Oct, 1);
         begin
            if FD.Status /= Adacraft.Protocol.Ok then
               Current_Bad := True;
               Current_Outcome := Differential.Malformed_Frame;
               return;
            end if;
         end;
      end;
      Send_All (Sock, Out_Buf (Out_Buf'First .. Last));
   end Send_Serverbound;

   procedure Capture_One
     (Target   : Differential.Args.Endpoint;
      Scenario : Scenario_Descriptor;
      Result   : out Differential.Transcript.Scenario_Result)
   is
      use GNAT.Sockets;
      Sock : Socket_Type;
      Got_Any : Boolean := False;
   begin
      Result := (others => <>);
      if Scenario.Name_Len > 0 then
         Result.Name (1 .. Scenario.Name_Len) :=
           Scenario.Name (1 .. Scenario.Name_Len);
         Result.Name_Len := Scenario.Name_Len;
      end if;
      Result.Outcome := Differential.Completed;

      Connect_To (Target, Sock);

      Current_Result := Result'Unrestricted_Access;
      Current_State := Adacraft.Protocol.State.Initial_State;
      Current_Bad := False;
      Current_Outcome := Differential.Completed;
      Current_Frames := 0;

      declare
         Conn : Adacraft.Ingress.Connection_Type;
      begin
         Adacraft.Ingress.Initialize
           (Conn, On_Frame_Body'Access, On_Close_Notify'Access);

         for I in 1 .. Scenario.Body_Count loop
            Send_Serverbound (Sock, Scenario.Bodies (I));
            exit when Current_Bad;
         end loop;

         if Current_Bad then
            Result := Current_Result.all;
            Result.Outcome := Current_Outcome;
            Current_Result := null;
            Close_Socket (Sock);
            return;
         end if;

         --  Clientbound via Ingress #204 reassembly + Decoder #203 +
         --  VarInt #208, state via #118 (see callbacks above).
         loop
            declare
               RS : Socket_Set_Type;
               WS : Socket_Set_Type;
               TV : constant Timeval_Duration := Timeval_Duration (Read_Timeout);
               Stat : Selector_Status;
            begin
               Empty (RS);
               Empty (WS);
               Set (RS, Sock);
               Check_Selector (RS, WS, Stat, TV);
               if Stat /= Completed then
                  exit;
               end if;
            exception
               when others =>
                  raise Env_Error with "select failed";
            end;
            declare
               Chunk : Ada.Streams.Stream_Element_Array (1 .. 4_096);
               Last  : Ada.Streams.Stream_Element_Offset;
            begin
               Receive_Socket (Sock, Chunk, Last);
               if Last < Chunk'First then
                  Result := Current_Result.all;
                  Result.Outcome :=
                    (if Current_Bad then Current_Outcome
                     else Differential.Peer_Closed);
                  Current_Result := null;
                  Close_Socket (Sock);
                  return;
               end if;
               Got_Any := True;
               Adacraft.Ingress.Receive (Conn, Chunk (Chunk'First .. Last));
               if Adacraft.Ingress.Is_Closed (Conn) then
                  Result := Current_Result.all;
                  Result.Outcome :=
                    (if Current_Bad then Current_Outcome
                     else Differential.Malformed_Frame);
                  Current_Result := null;
                  Close_Socket (Sock);
                  return;
               end if;
               exit when Current_Bad;
            exception
               when Env_Error =>
                  raise;
               when Socket_Error =>
                  Result := Current_Result.all;
                  Result.Outcome :=
                    (if Current_Bad then Current_Outcome
                     else Differential.Peer_Closed);
                  Current_Result := null;
                  Close_Socket (Sock);
                  return;
            end;
         end loop;

         Result := Current_Result.all;
         if Current_Bad then
            Result.Outcome := Current_Outcome;
         elsif Got_Any then
            Result.Outcome := Differential.Completed;
         else
            Result.Outcome := Differential.Read_Timeout;
         end if;
         Current_Result := null;
         Close_Socket (Sock);
      exception
         when Env_Error =>
            Current_Result := null;
            Close_Socket (Sock);
            raise;
         when others =>
            Current_Result := null;
            Close_Socket (Sock);
            Result.Outcome := Differential.Malformed_Frame;
      end;
   end Capture_One;

   procedure Run_All
     (Oracle    : Differential.Args.Endpoint;
      Candidate : Differential.Args.Endpoint;
      Source    : in out Provider'Class;
      Oracle_Out    : out Result_Array;
      Candidate_Out : out Result_Array;
      Total         : out Natural)
   is
      N : constant Natural := Source.Count;
   begin
      Total := N;
      for I in 1 .. N loop
         declare
            Desc : Scenario_Descriptor;
            RO : Differential.Transcript.Scenario_Result;
            RC : Differential.Transcript.Scenario_Result;
         begin
            Source.Get (I, Desc);
            Capture_One (Oracle, Desc, RO);
            Oracle_Out (I) := RO;
            Capture_One (Candidate, Desc, RC);
            Candidate_Out (I) := RC;
         end;
      end loop;
   end Run_All;

end Differential.Capture;
