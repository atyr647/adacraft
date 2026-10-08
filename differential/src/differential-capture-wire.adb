with Ada.Streams;
with GNAT.Sockets;
with Adacraft.Protocol;
with Adacraft.Protocol.Frame;
with Adacraft.Protocol.Packet_Encoder;
with Adacraft.Protocol.Varnum;
with Differential.Transcript;

package body Differential.Capture.Wire is

   use type Ada.Streams.Stream_Element_Offset;
   use type Adacraft.Protocol.Frame.Feed_Status;
   use type Differential.Transcript.Terminal_Outcome;

   procedure Open
     (C       : in out Wire_Connection;
      Host    : in String;
      Port    : in Natural;
      Outcome : out Differential.Transcript.Terminal_Outcome)
   is
      Addr : GNAT.Sockets.Inet_Addr_Type;
   begin
      Outcome := Differential.Transcript.Completed;
      if C.Opened then
         return;
      end if;
      if Host'Length = 0 or else Port < 1 or else Port > 65_535 then
         Outcome := Differential.Transcript.Connect_Failed;
         return;
      end if;
      begin
         Addr := GNAT.Sockets.Inet_Addr (Host);
      exception
         when others =>
            Outcome := Differential.Transcript.Connect_Failed;
            return;
      end;
      begin
         GNAT.Sockets.Create_Socket (C.Sock);
         GNAT.Sockets.Connect_Socket
           (C.Sock, Addr, GNAT.Sockets.Port_Type (Port));
         C.Opened := True;
         Outcome := Differential.Transcript.Completed;
      exception
         when others =>
            begin
               if C.Sock /= GNAT.Sockets.No_Socket then
                  GNAT.Sockets.Close_Socket (C.Sock);
               end if;
            exception
               when others => null;
            end;
            C.Sock := GNAT.Sockets.No_Socket;
            C.Opened := False;
            Outcome := Differential.Transcript.Connect_Failed;
      end;
   end Open;

   function Is_Open (C : Wire_Connection) return Boolean is
   begin
      return C.Opened;
   end Is_Open;

   procedure Send_Packet
     (C         : in out Wire_Connection;
      Packet_Id : in Natural;
      Payload   : in Ada.Streams.Stream_Element_Array;
      Outcome   : out Differential.Transcript.Terminal_Outcome)
   is
      Enc    : Adacraft.Protocol.Packet_Encoder.Encoder_Type;
      Framed : Ada.Streams.Stream_Element_Array (1 .. 2_097_151 + 3);
      Last   : Ada.Streams.Stream_Element_Offset;
      Sent   : Ada.Streams.Stream_Element_Offset;
      First  : Ada.Streams.Stream_Element_Offset;
   begin
      Outcome := Differential.Transcript.Completed;
      if not C.Opened then
         Outcome := Differential.Transcript.Peer_Closed;
         return;
      end if;
      Adacraft.Protocol.Packet_Encoder.Start_Packet (Enc, Packet_Id);
      for I in Payload'Range loop
         Adacraft.Protocol.Packet_Encoder.Write_Byte (Enc, Payload (I));
      end loop;
      if Adacraft.Protocol.Packet_Encoder.Has_Failed (Enc) then
         Outcome := Differential.Transcript.Protocol_Error;
         return;
      end if;
      Adacraft.Protocol.Packet_Encoder.Get_Framed (Enc, Framed, Last);
      if Adacraft.Protocol.Packet_Encoder.Has_Failed (Enc) then
         Outcome := Differential.Transcript.Protocol_Error;
         return;
      end if;
      begin
         First := Framed'First;
         while First <= Last loop
            GNAT.Sockets.Send_Socket (C.Sock, Framed (First .. Last), Sent);
            exit when Sent < First;
            First := Sent + 1;
         end loop;
         Outcome := Differential.Transcript.Completed;
      exception
         when GNAT.Sockets.Socket_Error =>
            Outcome := Differential.Transcript.Peer_Closed;
         when others =>
            Outcome := Differential.Transcript.Protocol_Error;
      end;
   end Send_Packet;

   procedure Receive_Frame
     (C          : in out Wire_Connection;
      Frame_Data : out Ada.Streams.Stream_Element_Array;
      Last       : out Ada.Streams.Stream_Element_Offset;
      Got        : out Boolean;
      Outcome    : out Differential.Transcript.Terminal_Outcome)
   is
      Chunk      : Ada.Streams.Stream_Element_Array (1 .. 4_096);
      Chunk_Last : Ada.Streams.Stream_Element_Offset;
      R_Set      : GNAT.Sockets.Socket_Set_Type;
      W_Set      : GNAT.Sockets.Socket_Set_Type;
      Sel_Status : GNAT.Sockets.Selector_Status;
      Pending    : Boolean := False;
      Feed_Res   : Adacraft.Protocol.Frame.Feed_Status;
      Dummy      : Natural := 0;

      procedure On_Frame (Frame : in Adacraft.Protocol.Frame.Byte_Array) is
         N : constant Ada.Streams.Stream_Element_Offset := Frame'Length;
      begin
         if not Pending and then N <= Frame_Data'Length then
            if N > 0 then
               Frame_Data (Frame_Data'First .. Frame_Data'First + N - 1) :=
                 Frame;
            end if;
            Last := Frame_Data'First + N - 1;
            Pending := True;
         end if;
      end On_Frame;
   begin
      Got := False;
      Last := Frame_Data'First - 1;
      Outcome := Differential.Transcript.Completed;
      if not C.Opened then
         Outcome := Differential.Transcript.Peer_Closed;
         return;
      end if;
      Dummy := Natural (Chunk_Last - Chunk'First + 1);
      loop
         GNAT.Sockets.Empty (R_Set);
         GNAT.Sockets.Empty (W_Set);
         GNAT.Sockets.Set (R_Set, C.Sock);
         GNAT.Sockets.Check_Selector (R_Set, W_Set, Sel_Status, Read_Timeout);
         if Sel_Status /= GNAT.Sockets.Completed then
            Outcome := Differential.Transcript.Timeout;
            return;
         end if;
         begin
            GNAT.Sockets.Receive_Socket (C.Sock, Chunk, Chunk_Last);
         exception
            when GNAT.Sockets.Socket_Error =>
               Outcome := Differential.Transcript.Peer_Closed;
               return;
            when others =>
               Outcome := Differential.Transcript.Protocol_Error;
               return;
         end;
         if Chunk_Last < Chunk'First then
            Outcome := Differential.Transcript.Peer_Closed;
            return;
         end if;
         Adacraft.Protocol.Frame.Feed
           (C.Decoder, Chunk (Chunk'First .. Chunk_Last),
            On_Frame'Access, Feed_Res);
         if Feed_Res = Adacraft.Protocol.Frame.Framing_Error then
            Outcome := Differential.Transcript.Protocol_Error;
            return;
         end if;
         if Pending then
            declare
               N : constant Ada.Streams.Stream_Element_Offset :=
                 Last - Frame_Data'First + 1;
               Octs : Adacraft.Protocol.Octets (1 .. Positive (N));
               Res : Adacraft.Protocol.Varnum.Varint_Result;
            begin
               for I in 1 .. Positive (N) loop
                  Octs (I) := Adacraft.Protocol.Octet
                    (Frame_Data (Frame_Data'First + I - 1));
               end loop;
               --  Validate packet ID via shipped VarInt codec (#208);
               --  decode/framing rejection maps to Protocol_Error.
               --  No own length-VarInt loop, no manual packet-ID parse.
               Res := Adacraft.Protocol.Varnum.Decode_Varint (Octs, 1);
               if Res.Status /= Adacraft.Protocol.Ok then
                  Outcome := Differential.Transcript.Protocol_Error;
                  Got := False;
                  return;
               end if;
            end;
            Got := True;
            Outcome := Differential.Transcript.Completed;
            return;
         end if;
      end loop;
   end Receive_Frame;

   procedure Close (C : in out Wire_Connection) is
   begin
      if C.Sock /= GNAT.Sockets.No_Socket then
         begin
            GNAT.Sockets.Close_Socket (C.Sock);
         exception
            when others => null;
         end;
         C.Sock := GNAT.Sockets.No_Socket;
      end if;
      C.Opened := False;
   end Close;

end Differential.Capture.Wire;
