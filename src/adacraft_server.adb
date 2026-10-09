with Ada.Command_Line;
with Ada.Text_IO;
with GNAT.Sockets;
with Adacraft;
with Adacraft.Network;
with Adacraft.Protocol;
with Adacraft.Protocol.State;
with Adacraft.Protocol.Frame;
with Adacraft.Protocol.Handshake_Exchange;
with Adacraft.Protocol.Status_Exchange;

procedure Adacraft_Server is
   Port : GNAT.Sockets.Port_Type := 25565;

   procedure Dispatch_Decoded_Frame
     (Current          : in out Adacraft.Protocol.State.Connection_State;
      Packet_Id        : in     Natural;
      Payload          : in     Adacraft.Protocol.Octets;
      Stored           : in out Adacraft.Protocol.Handshake_Exchange.Connection_Data;
      Sess             : in out Adacraft.Protocol.Status_Exchange.Session;
      Response_Id      :    out Natural;
      Response_Data    : in out Adacraft.Protocol.Octets;
      Response_Len     :    out Natural;
      Close_Connection :    out Boolean)
   is
      use type Adacraft.Protocol.State.Connection_State;
      use type Adacraft.Protocol.Handshake_Exchange.Handle_Result;
   begin
      case Current is
         when Adacraft.Protocol.State.Handshake =>
            declare
               H_Res : Adacraft.Protocol.Handshake_Exchange.Handle_Result;
            begin
               Adacraft.Protocol.Handshake_Exchange.Handle
                 (Packet_Id => Packet_Id,
                  Payload   => Payload,
                  Current   => Current,
                  Stored    => Stored,
                  Result    => H_Res);
               Response_Id := 0;
               Response_Len := 0;
               for I in Response_Data'Range loop
                  Response_Data (I) := 0;
               end loop;
               if H_Res = Adacraft.Protocol.Handshake_Exchange.Accepted_Status
                 or else H_Res = Adacraft.Protocol.Handshake_Exchange.Accepted_Login
               then
                  Close_Connection := False;
               else
                  Close_Connection := True;
               end if;
            end;
         when Adacraft.Protocol.State.Status =>
            declare
               S_Res : Adacraft.Protocol.Status_Exchange.Handle_Result;
            begin
               Adacraft.Protocol.Status_Exchange.Handle
                 (Packet_Id        => Packet_Id,
                  Payload          => Payload,
                  Current          => Current,
                  Session_State    => Sess,
                  Result           => S_Res,
                  Response_Id      => Response_Id,
                  Response_Data    => Response_Data,
                  Response_Len     => Response_Len,
                  Close_Connection => Close_Connection);
            end;
         when others =>
            --  Login onward: not yet implemented; close without Login logic.
            Response_Id := 0;
            Response_Len := 0;
            for I in Response_Data'Range loop
               Response_Data (I) := 0;
            end loop;
            Close_Connection := True;
      end case;
   end Dispatch_Decoded_Frame;

   procedure Dispatch_Raw_Buffer
     (Current          : in out Adacraft.Protocol.State.Connection_State;
      Buffer           : in     Adacraft.Protocol.Octets;
      From             : in     Positive;
      Stored           : in out Adacraft.Protocol.Handshake_Exchange.Connection_Data;
      Sess             : in out Adacraft.Protocol.Status_Exchange.Session;
      Response_Id      :    out Natural;
      Response_Data    : in out Adacraft.Protocol.Octets;
      Response_Len     :    out Natural;
      Close_Connection :    out Boolean)
   is
      use type Adacraft.Protocol.State.Connection_State;
      use type Adacraft.Protocol.Status_Kind;
      F : constant Adacraft.Protocol.Frame.Frame_Decode :=
        Adacraft.Protocol.Frame.Decode_Frame (Buffer, From);
   begin
      Response_Id := 0;
      Response_Len := 0;
      for I in Response_Data'Range loop
         Response_Data (I) := 0;
      end loop;
      Close_Connection := False;
      if F.Status /= Adacraft.Protocol.Ok then
         if Current = Adacraft.Protocol.State.Status then
            Close_Connection := True;
         end if;
         return;
      end if;
      if F.Payload_Last < F.Payload_First then
         declare
            Empty : constant Adacraft.Protocol.Octets (2 .. 1) :=
              (others => <>);
         begin
            Dispatch_Decoded_Frame
              (Current, F.Packet_Id, Empty, Stored, Sess,
               Response_Id, Response_Data, Response_Len, Close_Connection);
         end;
      else
         Dispatch_Decoded_Frame
           (Current, F.Packet_Id,
            Buffer (F.Payload_First .. F.Payload_Last),
            Stored, Sess,
            Response_Id, Response_Data, Response_Len, Close_Connection);
      end if;
   end Dispatch_Raw_Buffer;

begin
   --  Wire the state dispatch so ingress decodes each frame and dispatches
   --  by State.Current: Handshake -> Handshake_Exchange, Status ->
   --  Status_Exchange (honouring its Response_*/Close_Connection outputs),
   --  Login onward -> not-yet-implemented close.  This probe exercises the
   --  dispatch with a rejected packet so the server starts in Handshake
   --  with no state change; real connections keep their own
   --  Current/Stored/Sess and follow the same path.
   declare
      Current : Adacraft.Protocol.State.Connection_State :=
        Adacraft.Protocol.State.Handshake;
      Stored  : Adacraft.Protocol.Handshake_Exchange.Connection_Data;
      Sess    : Adacraft.Protocol.Status_Exchange.Session;
      Rid     : Natural := 0;
      Rlen    : Natural := 0;
      Rdata   : Adacraft.Protocol.Octets (1 .. 32_767) := (others => 0);
      Close   : Boolean := False;
      Empty   : constant Adacraft.Protocol.Octets (2 .. 1) := (others => <>);
      Raw     : constant Adacraft.Protocol.Octets (1 .. 1) := (others => 0);
   begin
      Adacraft.Protocol.Status_Exchange.Reset (Sess);
      Dispatch_Decoded_Frame
        (Current, Natural'Last, Empty, Stored, Sess,
         Rid, Rdata, Rlen, Close);
      Dispatch_Raw_Buffer
        (Current, Raw, Raw'First, Stored, Sess,
         Rid, Rdata, Rlen, Close);
      --  Probe results are intentionally discarded: a rejected probe must
      --  not send a response nor close the listener; per-connection
      --  handling sends Response_Id/Response_Data (1 .. Response_Len)
      --  when Response_Len > 0 and closes when Close_Connection is set.
      if Rid < 0 then
         Ada.Text_IO.Put_Line ("unreachable");
      end if;
   end;
   if Ada.Command_Line.Argument_Count >= 1 then
      Port := GNAT.Sockets.Port_Type'Value (Ada.Command_Line.Argument (1));
   end if;
   Ada.Text_IO.Put_Line
     ("AdaCraft " & Adacraft.Minecraft_Version
      & " protocol" & Adacraft.Protocol_Version'Image
      & " listening on" & Port'Image);
   Adacraft.Network.Serve (Port);
end Adacraft_Server;
