with Ada.Streams;
with Ada.Unchecked_Deallocation;
with Interfaces;
with Adacraft.Protocol.Frame;
with Adacraft.Protocol.Packets;
with Adacraft.Protocol.Varnum;

package body Differential.Client is

   package P renames Adacraft.Protocol;
   package Frame renames Adacraft.Protocol.Frame;
   package SU renames Ada.Strings.Unbounded;
   use type Ada.Streams.Stream_Element_Offset;
   use type P.Status_Kind;
   use type Differential.Scenario.Corpus.Direction;
   use type PS.Result_Kind;

   function Hex (Bytes : P.Octets) return String is
      Digits_Map : constant String := "0123456789abcdef";
      R : String (1 .. Bytes'Length * 2);
      J : Natural := 0;
   begin
      for B of Bytes loop
         R (J + 1) := Digits_Map (Natural (B) / 16 + 1);
         R (J + 2) := Digits_Map (Natural (B) mod 16 + 1);
         J := J + 2;
      end loop;
      return R;
   end Hex;

   type Dec_Access is access Frame.Decoder_Type;
   procedure Free is new Ada.Unchecked_Deallocation
     (Frame.Decoder_Type, Dec_Access);

   procedure Execute
     (T        : in out Transport'Class;
      Scenario : Differential.Scenario.Projection;
      Output   : out Run_Output)
   is
      Dec     : Dec_Access := new Frame.Decoder_Type;
      State   : PS.Connection_State := Scenario.Initial_State;
      Current : Step_Log;
      Buffer  : P.Octets (1 .. 4096);

      procedure On_Frame (F : Frame.Byte_Array) is
         Body_Bytes : P.Octets (1 .. Natural (F'Length));
         Value      : Interfaces.Integer_32;
         Consumed   : Natural;
         St         : P.Varnum.Status_Type;
         Pkt        : Received_Packet;
      begin
         for I in Body_Bytes'Range loop
            Body_Bytes (I) :=
              P.Octet (F (F'First + Ada.Streams.Stream_Element_Offset (I - 1)));
         end loop;
         P.Varnum.Decode (Body_Bytes, 1, Value, Consumed, St);
         if St = P.Varnum.Ok and then Value >= 0 then
            Pkt.Id := Natural (Value);
            for I in Consumed + 1 .. Body_Bytes'Last loop
               SU.Append (Pkt.Payload, Character'Val (Natural (Body_Bytes (I))));
            end loop;
         else
            Pkt.Id := Natural'Last;
         end if;
         Current.Packets.Append (Pkt);
      end On_Frame;

      procedure Track_Sent (Bytes : P.Octets) is
         D      : constant Frame.Frame_Decode := Frame.Decode_Frame (Bytes, 1);
         Intent : PS.Handshake_Intent := 0;
      begin
         if D.Status /= P.Ok then
            return;
         end if;
         if State = PS.Handshake and then D.Packet_Id = 0 then
            declare
               Hs : constant P.Packets.Handshake :=
                 P.Packets.Decode_Handshake
                   (Bytes (D.Payload_First .. D.Payload_Last));
            begin
               if Hs.Status = P.Ok then
                  Intent := PS.Handshake_Intent (Hs.Intent);
               end if;
            end;
         end if;
         declare
            R : constant PS.Transition_Result :=
              PS.Transition
                (State, (Direction => PS.Serverbound,
                         Id        => PS.Packet_Id (D.Packet_Id),
                         Intent    => Intent));
         begin
            if R.Kind /= PS.Rejected then
               State := R.Next_State;
            end if;
         end;
      end Track_Sent;

      procedure Drain (Wait : Duration) is
         Last   : Natural;
         Status : Recv_Status;
         Fed    : Frame.Feed_Status;
         First  : Boolean := True;
      begin
         loop
            Receive (T, (if First then Wait else Settle_Time),
                     Buffer, Last, Status);
            First := False;
            case Status is
               when Quiet =>
                  exit;
               when Closed =>
                  Current.Closed := True;
                  exit;
               when Data =>
                  Current.No_Data := False;
                  Current.Raw_Count := Current.Raw_Count + Last;
                  declare
                     Chunk : Frame.Byte_Array
                       (1 .. Ada.Streams.Stream_Element_Offset (Last));
                  begin
                     for I in 1 .. Last loop
                        Chunk (Ada.Streams.Stream_Element_Offset (I)) :=
                          Ada.Streams.Stream_Element (Buffer (I));
                     end loop;
                     Frame.Feed (Dec.all, Chunk, On_Frame'Access, Fed);
                     if Fed = Frame.Framing_Error then
                        Current.Framing_Error := True;
                        exit;
                     end if;
                  end;
            end case;
         end loop;
      end Drain;
   begin
      SU.Append (Output.Transcript,
                 "scenario " & SU.To_String (Scenario.Id) & ASCII.LF);
      for A of Scenario.Actions loop
         Current := (Index => A.Index, State_After => State, others => <>);
         if A.Dir = Differential.Scenario.Corpus.Clientbound then
            SU.Append (Output.Transcript,
                       Natural'Image (A.Index) & " skip" & ASCII.LF);
         else
            declare
               Bytes : P.Octets (1 .. Natural (A.Frame.Length));
               Ok    : Boolean;
            begin
               for I in Bytes'Range loop
                  Bytes (I) := A.Frame (I);
               end loop;
               SU.Append (Output.Transcript,
                          Natural'Image (A.Index) & " send " & Hex (Bytes)
                          & ASCII.LF);
               Send (T, Bytes, Ok);
               Current.Sent := Ok;
               if Ok then
                  Track_Sent (Bytes);
                  Drain (A.Timeout);
               else
                  Output.Failed := True;
                  SU.Append (Output.Detail,
                             "send failed at step" & Natural'Image (A.Index));
               end if;
            end;
         end if;
         Current.State_After := State;
         Output.Steps.Append (Current);
         exit when Output.Failed;
      end loop;
      Free (Dec);
   exception
      when others =>
         Free (Dec);
         raise;
   end Execute;

   procedure Connect
     (T    : in out Tcp_Transport;
      Port : GNAT.Sockets.Port_Type;
      Ok   : out Boolean)
   is
      use GNAT.Sockets;
   begin
      Create_Socket (T.Sock);
      Connect_Socket
        (T.Sock, (Family => Family_Inet, Addr => Loopback_Inet_Addr,
                  Port   => Port));
      T.Connected := True;
      Ok := True;
   exception
      when Socket_Error =>
         Disconnect (T);
         Ok := False;
   end Connect;

   procedure Disconnect (T : in out Tcp_Transport) is
      use GNAT.Sockets;
   begin
      if T.Sock /= No_Socket then
         Close_Socket (T.Sock);
      end if;
      T.Sock := No_Socket;
      T.Connected := False;
   exception
      when Socket_Error =>
         T.Sock := No_Socket;
         T.Connected := False;
   end Disconnect;

   overriding procedure Send
     (T    : in out Tcp_Transport;
      Data : P.Octets;
      Ok   : out Boolean)
   is
      use GNAT.Sockets;
      Item : Ada.Streams.Stream_Element_Array
        (1 .. Ada.Streams.Stream_Element_Offset (Data'Length));
      Pos  : Ada.Streams.Stream_Element_Offset := 0;
      Sent : Ada.Streams.Stream_Element_Offset;
   begin
      Ok := False;
      if not T.Connected then
         return;
      end if;
      for I in Data'Range loop
         Pos := Pos + 1;
         Item (Pos) := Ada.Streams.Stream_Element (Data (I));
      end loop;
      Pos := 1;
      while Pos <= Item'Last loop
         Send_Socket (T.Sock, Item (Pos .. Item'Last), Sent);
         exit when Sent < Pos;
         Pos := Sent + 1;
      end loop;
      Ok := Pos > Item'Last;
   exception
      when Socket_Error =>
         Ok := False;
   end Send;

   overriding procedure Receive
     (T      : in out Tcp_Transport;
      Wait   : Duration;
      Buffer : out P.Octets;
      Last   : out Natural;
      Status : out Recv_Status)
   is
      use GNAT.Sockets;
      R, W : Socket_Set_Type;
      Sel  : Selector_Status;
   begin
      Last := 0;
      Status := Closed;
      if not T.Connected then
         return;
      end if;
      Empty (R);
      Empty (W);
      Set (R, T.Sock);
      Check_Selector (R, W, Sel, Wait);
      if Sel /= Completed then
         Status := Quiet;
         return;
      end if;
      declare
         Item : Ada.Streams.Stream_Element_Array
           (1 .. Ada.Streams.Stream_Element_Offset (Buffer'Length));
         L    : Ada.Streams.Stream_Element_Offset;
      begin
         Receive_Socket (T.Sock, Item, L);
         if L < Item'First then
            return;  --  peer closed
         end if;
         for I in 1 .. Natural (L) loop
            Buffer (Buffer'First + I - 1) :=
              P.Octet (Item (Ada.Streams.Stream_Element_Offset (I)));
         end loop;
         Last := Natural (L);
         Status := Data;
      end;
   exception
      when Socket_Error =>
         Last := 0;
         Status := Closed;
   end Receive;

end Differential.Client;
