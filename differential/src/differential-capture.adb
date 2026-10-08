with Ada.Streams;
with GNAT.Sockets;
with Adacraft.Protocol.Frame;

package body Differential.Capture is

   use type Ada.Streams.Stream_Element_Offset;

   function Make_Target (Host : String; Port : Natural) return Target_Info is
   begin
      return (Host => To_Unbounded_String (Host), Port => Port);
   end Make_Target;

   function Scenario_Name (S : Scenario) return String is
   begin
      return To_String (S.Name);
   end Scenario_Name;

   function Empty_Provider return Scenario_List is
   begin
      return Scenario_Vectors.Empty_Vector;
   end Empty_Provider;

   function To_Direction (D : Adacraft.Protocol.State.Packet_Direction)
     return Transcript.Direction_Kind
   is
   begin
      if D = Adacraft.Protocol.State.Serverbound then
         return Transcript.Serverbound;
      else
         return Transcript.Clientbound;
      end if;
   end To_Direction;

   procedure Append_Entry
     (T   : in out Transcript.Transcript;
      St  : Adacraft.Protocol.State.Connection_State;
      Dir : Transcript.Direction_Kind;
      Id  : Natural)
   is
      Item : Transcript.Transcript_Entry;
   begin
      Item.State := St;
      Item.Direction := Dir;
      Item.Packet_Id := Id;
      Transcript.Append (T, Item);
   end Append_Entry;

   function Next_State
     (Current   : Adacraft.Protocol.State.Connection_State;
      Dir       : Adacraft.Protocol.State.Packet_Direction;
      Id        : Natural;
      Intent    : Integer) return Adacraft.Protocol.State.Connection_State
   is
      use Adacraft.Protocol.State;
      Ev : constant Packet_Event :=
        (Direction => Dir,
         Id        => Packet_Id (Id),
         Intent    => Handshake_Intent (Intent));
      R : constant Transition_Result := Transition (Current, Ev);
   begin
      if R.Kind = Rejected then
         return Current;
      else
         return R.Next_State;
      end if;
   end Next_State;

   procedure Capture_For_Target
     (Host     : String;
      Port     : Natural;
      Item     : Scenario;
      Result   : out Transcript.Transcript;
      Initial  : Adacraft.Protocol.State.Connection_State :=
        Adacraft.Protocol.State.Handshake)
   is
      Sock    : GNAT.Sockets.Socket_Type;
      Opened  : Boolean := False;
      Current : Adacraft.Protocol.State.Connection_State := Initial;
      Addr    : GNAT.Sockets.Sock_Addr_Type;
      Sent_Ok : Boolean;
   begin
      Transcript.Clear (Result);
      Result.Outcome := Transcript.Completed;
      begin
         GNAT.Sockets.Create_Socket (Sock);
         Opened := True;
         GNAT.Sockets.Set_Socket_Option
           (Sock, GNAT.Sockets.Socket_Level,
            (GNAT.Sockets.Receive_Timeout, 5.0));
         Addr.Addr := GNAT.Sockets.Inet_Addr (Host);
         Addr.Port := GNAT.Sockets.Port_Type (Port);
         GNAT.Sockets.Connect_Socket (Sock, Addr);
      exception
         when others =>
            if Opened then
               begin
                  GNAT.Sockets.Close_Socket (Sock);
               exception
                  when others =>
                     null;
               end;
            end if;
            Transcript.Set_Outcome (Result, Transcript.Connect_Failure);
            return;
      end;
      --  Send each serverbound packet: minimal body holding the id only.
      --  Real payload encoding lands with the corpus loader (Q1).
      for I in 0 .. Natural (Item.Items.Length) - 1 loop
         declare
            It   : constant Serverbound_Item := Item.Items.Element (I);
            Body : Adacraft.Protocol.Frame.Byte_Array (1 .. 1);
            Wire : Adacraft.Protocol.Frame.Byte_Array (1 .. 8_192);
            Last : Ada.Streams.Stream_Element_Offset;
            Enc  : Adacraft.Protocol.Frame.Encode_Status;
            Sent : Ada.Streams.Stream_Element_Offset;
            From : Ada.Streams.Stream_Element_Offset;
         begin
            Body (1) := Ada.Streams.Stream_Element (It.Packet_Id mod 128);
            Append_Entry (Result, Current, Transcript.Serverbound,
              It.Packet_Id);
            Current := Next_State (Current,
              Adacraft.Protocol.State.Serverbound, It.Packet_Id, It.Intent);
            Adacraft.Protocol.Frame.Encode (Body, Wire, Last, Enc);
            if Enc /= Adacraft.Protocol.Frame.Ok then
               Transcript.Set_Outcome (Result, Transcript.Protocol_Error);
               exit;
            end if;
            From := Wire'First;
            begin
               while From <= Last loop
                  GNAT.Sockets.Send_Socket (Sock, Wire (From .. Last), Sent);
                  exit when Sent <= 0;
                  From := From + Sent;
               end loop;
               Sent_Ok := From > Last;
            exception
               when others =>
                  Sent_Ok := False;
            end;
            if not Sent_Ok then
               Transcript.Set_Outcome (Result, Transcript.Peer_Closed);
               exit;
            end if;
         end;
      end loop;
      --  Read clientbound frames until the peer closes or times out.
      if Result.Outcome = Transcript.Completed then
         declare
            Chunk : Ada.Streams.Stream_Element_Array (1 .. 2_048);
            Last  : Ada.Streams.Stream_Element_Offset;
            Hold  : Adacraft.Protocol.Octets (1 .. 8_192) :=
              (others => 0);
            Used  : Natural := 0;
         begin
            loop
               begin
                  GNAT.Sockets.Receive_Socket (Sock, Chunk, Last);
               exception
                  when GNAT.Sockets.Socket_Error =>
                     Transcript.Set_Outcome (Result, Transcript.Timeout);
                     exit;
                  when others =>
                     Transcript.Set_Outcome
                       (Result, Transcript.Protocol_Error);
                     exit;
               end;
               exit when Last < Chunk'First;
               for K in Chunk'First .. Last loop
                  exit when Used = Hold'Last;
                  Used := Used + 1;
                  Hold (Used) :=
                    Adacraft.Protocol.Octet (Chunk (K));
               end loop;
               while Used > 0 loop
                  declare
                     D : constant Adacraft.Protocol.Frame.Frame_Decode :=
                       Adacraft.Protocol.Frame.Decode_Frame
                         (Hold (1 .. Used), 1);
                  begin
                     if D.Status = Adacraft.Protocol.Need_More then
                        exit;
                     elsif D.Status /= Adacraft.Protocol.Ok then
                        Transcript.Set_Outcome
                          (Result, Transcript.Protocol_Error);
                        Used := 0;
                        exit;
                     else
                        Append_Entry (Result, Current,
                          Transcript.Clientbound, D.Packet_Id);
                        Current := Next_State (Current,
                          Adacraft.Protocol.State.Clientbound,
                          D.Packet_Id, 0);
                        if D.Next > Used then
                           Used := 0;
                        else
                           Hold (1 .. Used - D.Next + 1) :=
                             Hold (D.Next .. Used);
                           Used := Used - D.Next + 1;
                        end if;
                     end if;
                  end;
                  exit when Result.Outcome /= Transcript.Completed;
               end loop;
               exit when Result.Outcome /= Transcript.Completed;
            end loop;
            if Result.Outcome = Transcript.Completed then
               if Used > 0 then
                  Transcript.Set_Outcome (Result, Transcript.Peer_Closed);
               else
                  Transcript.Set_Outcome (Result, Transcript.Completed);
               end if;
            end if;
         end;
      end if;
      begin
         GNAT.Sockets.Close_Socket (Sock);
      exception
         when others =>
            null;
      end;
   exception
      when others =>
         Transcript.Set_Outcome (Result, Transcript.Protocol_Error);
   end Capture_For_Target;

end Differential.Capture;
