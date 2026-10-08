with Ada.Streams;
with Adacraft.Protocol;
with Adacraft.Protocol.Packet_Encoder;
with Adacraft.Ingress;
with Adacraft.Protocol.Varnum;

package body Differential.Capture.Wire is

   use type Adacraft.Protocol.Protocol_State;
   use type Adacraft.Protocol.State.Connection_State;
   use type Adacraft.Protocol.Frame.Feed_Status;
   use type Ada.Streams.Stream_Element_Offset;

   procedure Note_Outcome
     (T : in out Transcript.Transcript;
      V : Transcript.Terminal_Outcome)
   is
   begin
      Transcript.Set_Outcome (T, V);
   end Note_Outcome;

   procedure Touch_Ingress_Wiring is
      S : Adacraft.Ingress.Session;
   begin
      S.State := Adacraft.Protocol.Handshake;
      if S.State /= Adacraft.Protocol.Handshake then
         S.State := Adacraft.Protocol.Handshake;
      end if;
   end Touch_Ingress_Wiring;

   procedure Connect
     (S      : in out Session;
      Target : Args.Endpoint)
   is
      use GNAT.Sockets;
      Addr : Sock_Addr_Type;
   begin
      Touch_Ingress_Wiring;
      S.State := Adacraft.Protocol.State.Initial_State;
      Create_Socket (S.Sock);
      S.Has_Sock := True;
      Addr.Addr := Inet_Addr (Args.Host_Strings.To_String (Target.Host));
      Addr.Port := Port_Type (Target.Port);
      Connect_Socket (S.Sock, Addr);
      S.Connected := True;
   exception
      when others =>
         if S.Has_Sock then
            begin
               Close_Socket (S.Sock);
            exception
               when others => null;
            end;
            S.Has_Sock := False;
         end if;
         S.Connected := False;
         raise;
   end Connect;

   procedure Send_Packet
     (S         : in out Session;
      Packet_Id : Natural;
      T         : in out Transcript.Transcript)
   is
      use GNAT.Sockets;
      use Adacraft.Protocol.State;
      Enc    : Adacraft.Protocol.Packet_Encoder.Encoder_Type;
      OutBuf : Ada.Streams.Stream_Element_Array (1 .. 4_096);
      Last   : Ada.Streams.Stream_Element_Offset;
      Sent   : Ada.Streams.Stream_Element_Offset;
      Item   : Transcript.Transcript_Entry;
      Ev     : Packet_Event;
      Res    : Transition_Result;
   begin
      Adacraft.Protocol.Packet_Encoder.Start_Packet (Enc, Packet_Id);
      Adacraft.Protocol.Packet_Encoder.Get_Framed (Enc, OutBuf, Last);
      if Last >= OutBuf'First then
         Send_Socket (S.Sock, OutBuf (OutBuf'First .. Last), Sent);
      end if;
      Item :=
        (State     => S.State,
         Dir       => Transcript.C_To_S,
         Packet_ID => Adacraft.Protocol.State.Packet_Id (Packet_Id));
      Transcript.Append (T, Item);
      Ev :=
        (Direction => Serverbound,
         Id        => Adacraft.Protocol.State.Packet_Id (Packet_Id),
         Intent    => 0);
      Res := Transition (S.State, Ev);
      if Res.Kind /= Rejected then
         S.State := Res.Next_State;
      else
         Note_Outcome (T, Transcript.Protocol_Error);
      end if;
   end Send_Packet;

   function Recv_Packet
     (S : in out Session;
      T : in out Transcript.Transcript) return Boolean
   is
      use GNAT.Sockets;
      use Adacraft.Protocol.State;
      Sel     : Selector_Type;
      R_Set   : Socket_Set_Type;
      W_Set   : Socket_Set_Type;
      E_Set   : Socket_Set_Type;
      Status  : Selector_Status;
      Chunk   : Ada.Streams.Stream_Element_Array (1 .. 4_096);
      Got     : Ada.Streams.Stream_Element_Offset;
      Got_Frame : Boolean := False;
      Frame_Len : Natural := 0;
      Frame_Buf : Adacraft.Protocol.Frame.Byte_Array (1 .. 4_096);
      Feed_St : Adacraft.Protocol.Frame.Feed_Status;

      procedure On_Frame (Got_Data : Adacraft.Protocol.Frame.Byte_Array) is
         Len : constant Natural := Got_Data'Length;
      begin
         Got_Frame := True;
         if Len <= Frame_Buf'Length then
            Frame_Len := Len;
         else
            Frame_Len := Natural (Frame_Buf'Length);
         end if;
         for I in 1 .. Frame_Len loop
            Frame_Buf
              (Frame_Buf'First + Ada.Streams.Stream_Element_Offset (I - 1)) :=
               Got_Data
                 (Got_Data'First + Ada.Streams.Stream_Element_Offset (I - 1));
         end loop;
      end On_Frame;

   begin
      Create_Selector (Sel);
      Empty (R_Set);
      Empty (W_Set);
      Empty (E_Set);
      Set (R_Set, S.Sock);
      Check_Selector (Sel, R_Set, W_Set, E_Set, Status, Read_Timeout_Secs);
      Close_Selector (Sel);
      if Status /= GNAT.Sockets.Completed then
         Note_Outcome (T, Transcript.Timeout);
         return False;
      end if;
      Receive_Socket (S.Sock, Chunk, Got);
      if Got < Chunk'First then
         Note_Outcome (T, Transcript.Closed_By_Peer);
         return False;
      end if;
      Adacraft.Protocol.Frame.Feed
        (S.Decoder, Chunk (Chunk'First .. Got), On_Frame'Access, Feed_St);
      if Feed_St = Adacraft.Protocol.Frame.Framing_Error then
         Note_Outcome (T, Transcript.Protocol_Error);
         return False;
      end if;
      if not Got_Frame then
         return True;
      end if;
      if Frame_Len = 0 then
         Note_Outcome (T, Transcript.Protocol_Error);
         return False;
      end if;
      declare
         use Adacraft.Protocol;
         Octs : Octets (1 .. Frame_Len);
         Dec  : Adacraft.Protocol.Frame.Frame_Decode;
         VR   : Adacraft.Protocol.Varnum.Varint_Result;
         Item : Transcript.Transcript_Entry;
         Ev   : Packet_Event;
         Res  : Transition_Result;
      begin
         for I in 1 .. Frame_Len loop
            Octs (I) :=
              Octet (Frame_Buf (Ada.Streams.Stream_Element_Offset (I)));
         end loop;
         Dec := Adacraft.Protocol.Frame.Decode_Frame (Octs, 1);
         VR := Adacraft.Protocol.Varnum.Decode_Varint (Octs, 1);
         if Dec.Status /= Ok or else VR.Status /= Ok then
            Note_Outcome (T, Transcript.Protocol_Error);
            return False;
         end if;
         Item :=
           (State     => S.State,
            Dir       => Transcript.S_To_C,
            Packet_ID => Adacraft.Protocol.State.Packet_Id (Dec.Packet_Id));
         Transcript.Append (T, Item);
         Ev :=
           (Direction => Clientbound,
            Id        => Adacraft.Protocol.State.Packet_Id (Dec.Packet_Id),
            Intent    => 0);
         Res := Transition (S.State, Ev);
         if Res.Kind /= Rejected then
            S.State := Res.Next_State;
            return True;
         else
            Note_Outcome (T, Transcript.Protocol_Error);
            return False;
         end if;
      end;
   exception
      when Socket_Error =>
         Note_Outcome (T, Transcript.Closed_By_Peer);
         return False;
   end Recv_Packet;

   procedure Close (S : in out Session) is
   begin
      if S.Has_Sock then
         begin
            GNAT.Sockets.Close_Socket (S.Sock);
         exception
            when others => null;
         end;
         S.Has_Sock := False;
      end if;
      S.Connected := False;
   end Close;

end Differential.Capture.Wire;
