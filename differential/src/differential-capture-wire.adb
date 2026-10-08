with Ada.Streams;
with Adacraft.Protocol;

package body Differential.Capture.Wire is

   use type Ada.Streams.Stream_Element_Offset;

   procedure Open
     (Host : String;
      Port : Natural;
      Sock : out GNAT.Sockets.Socket_Type;
      Ok   : out Boolean)
   is
      Addr : GNAT.Sockets.Sock_Addr_Type;
   begin
      Ok := False;
      GNAT.Sockets.Create_Socket (Sock);
      GNAT.Sockets.Set_Socket_Option
        (Sock, GNAT.Sockets.Socket_Level,
         (GNAT.Sockets.Receive_Timeout, Read_Timeout));
      Addr.Addr := GNAT.Sockets.Inet_Addr (Host);
      Addr.Port := GNAT.Sockets.Port_Type (Port);
      GNAT.Sockets.Connect_Socket (Sock, Addr);
      Ok := True;
   exception
      when others =>
         Ok := False;
   end Open;

   procedure Close (Sock : in out GNAT.Sockets.Socket_Type) is
   begin
      GNAT.Sockets.Close_Socket (Sock);
   exception
      when others =>
         null;
   end Close;

   procedure Send_Body
     (Sock      : GNAT.Sockets.Socket_Type;
      Current   : Adacraft.Protocol.State.Connection_State;
      Packet_Id : Natural;
      Body      : Adacraft.Protocol.Frame.Byte_Array;
      Ok        : out Boolean)
   is
      pragma Unreferenced (Current, Packet_Id);
      Wire : Adacraft.Protocol.Frame.Byte_Array (1 .. 8_192);
      Last : Ada.Streams.Stream_Element_Offset;
      Enc  : Adacraft.Protocol.Frame.Encode_Status;
      Sent : Ada.Streams.Stream_Element_Offset;
      From : Ada.Streams.Stream_Element_Offset;
   begin
      Ok := False;
      Adacraft.Protocol.Frame.Encode (Body, Wire, Last, Enc);
      if Enc /= Adacraft.Protocol.Frame.Ok then
         return;
      end if;
      From := Wire'First;
      while From <= Last loop
         GNAT.Sockets.Send_Socket (Sock, Wire (From .. Last), Sent);
         exit when Sent <= 0;
         From := From + Sent;
      end loop;
      Ok := From > Last;
   exception
      when others =>
         Ok := False;
   end Send_Body;

   function Body_Packet_Id
     (Body : Adacraft.Protocol.Frame.Byte_Array) return Natural
   is
      Buf : Adacraft.Protocol.Octets (1 .. Body'Length);
      Res : Adacraft.Protocol.Varnum.Varint_Result;
   begin
      if Body'Length = 0 then
         return 0;
      end if;
      for I in 1 .. Body'Length loop
         Buf (I) := Adacraft.Protocol.Octet (Body (Body'First + I - 1));
      end loop;
      Res := Adacraft.Protocol.Varnum.Decode_Varint (Buf, 1);
      if Res.Status /= Adacraft.Protocol.Ok then
         return 0;
      end if;
      if Res.Value > Adacraft.Protocol.Varnum.Varint_Result'(Res).Value'Last then
         return 0;
      end if;
      return Natural (Res.Value);
   end Body_Packet_Id;

   procedure Dummy_Body (Data : Adacraft.Protocol.Frame.Byte_Array) is
      pragma Unreferenced (Data);
   begin
      null;
   end Dummy_Body;

   procedure Dummy_Close is
   begin
      null;
   end Dummy_Close;

   procedure Recv_Until_Terminal
     (Sock : GNAT.Sockets.Socket_Type;
      Data : out Recv_Data)
   is
      Conn   : Adacraft.Ingress.Connection_Type;
      Chunk  : Ada.Streams.Stream_Element_Array (1 .. 2_048);
      Last   : Ada.Streams.Stream_Element_Offset;
      Hold   : Adacraft.Protocol.Octets (1 .. 8_192) := (others => 0);
      Used   : Natural := 0;
      Feed_St : Adacraft.Protocol.Frame.Feed_Status;
      procedure On_Frame (Frame : Adacraft.Protocol.Frame.Byte_Array) is
         pragma Unreferenced (Frame);
      begin
         null;
      end On_Frame;
      Decoder : Adacraft.Protocol.Frame.Decoder_Type;
   begin
      Data := (others => <>);
      Adacraft.Ingress.Initialize
        (Conn, Dummy_Body'Access, Dummy_Close'Access);
      loop
         begin
            GNAT.Sockets.Receive_Socket (Sock, Chunk, Last);
         exception
            when GNAT.Sockets.Socket_Error =>
               Data.Outcome := Differential.Transcript.Timeout;
               return;
         end;
         exit when Last < Chunk'First;
         declare
            Bytes : Adacraft.Protocol.Frame.Byte_Array (1 .. Last - Chunk'First + 1);
         begin
            for I in Bytes'Range loop
               Bytes (Positive (I)) :=
                 Chunk (Chunk'First + Ada.Streams.Stream_Element_Offset (I) - 1);
            end loop;
            Adacraft.Ingress.Receive (Conn, Bytes);
            if Adacraft.Ingress.Is_Closed (Conn) then
               Data.Outcome := Differential.Transcript.Protocol_Error;
               return;
            end if;
            Adacraft.Protocol.Frame.Feed (Decoder, Bytes, On_Frame'Access, Feed_St);
            if Feed_St /= Adacraft.Protocol.Frame.Success then
               Data.Outcome := Differential.Transcript.Protocol_Error;
               return;
            end if;
            for I in Bytes'Range loop
               exit when Used = Hold'Last;
               Used := Used + 1;
               Hold (Used) := Adacraft.Protocol.Octet (Bytes (I));
            end loop;
         end;
         while Used > 0 loop
            declare
               D : constant Adacraft.Protocol.Frame.Frame_Decode :=
                 Adacraft.Protocol.Frame.Decode_Frame (Hold (1 .. Used), 1);
            begin
               if D.Status = Adacraft.Protocol.Need_More then
                  exit;
               elsif D.Status /= Adacraft.Protocol.Ok then
                  Data.Outcome := Differential.Transcript.Protocol_Error;
                  return;
               else
                  if Data.Count < Max_Packets_Per_Read then
                     Data.Count := Data.Count + 1;
                     Data.Ids (Data.Count) := D.Packet_Id;
                  end if;
                  if D.Next > Used then
                     Used := 0;
                  else
                     Hold (1 .. Used - D.Next + 1) := Hold (D.Next .. Used);
                     Used := Used - D.Next + 1;
                  end if;
               end if;
            end;
         end loop;
      end loop;
      if Used > 0 then
         Data.Outcome := Differential.Transcript.Peer_Closed;
      else
         Data.Outcome := Differential.Transcript.Completed;
      end if;
   exception
      when others =>
         Data.Outcome := Differential.Transcript.Protocol_Error;
   end Recv_Until_Terminal;

end Differential.Capture.Wire;
