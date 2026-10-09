with Ada.Command_Line;
with Ada.Text_IO;
with GNAT.OS_Lib;
with GNAT.Sockets;
with Interfaces;
with Adacraft.Network;
with Adacraft;
with Adacraft.Protocol;
with Adacraft.Protocol.Frame;
with Adacraft.Protocol.Login;
with Adacraft.Protocol.Packet_Decoder;
with Adacraft.Protocol.State;
with Adacraft.Protocol.State.Table;
with Adacraft.Protocol.Varnum;

procedure Adacraft_Server is
   Port : GNAT.Sockets.Port_Type := 25565;

   --  Handle_Login: single-shot Login dispatch on the R1 path.
   --  Socket -> Receive Buffer -> Frame.Decoder -> Packet_Decoder ->
   --  Typed Packet -> dispatch. Well-formed Start answers one framed
   --  Login Disconnect then clean-closes only that connection;
   --  invalid-in-Login closes with no reply. Reuses the existing
   --  Frame/Varnum/State.Table/Login units; no new copies.
   procedure Handle_Login (Frame_Body : Adacraft.Protocol.Octets) is
      use type Adacraft.Protocol.Packet_Decoder.Decode_Status;
      use type Adacraft.Protocol.State.Connection_State;
      use type Interfaces.Integer_32;
      use type Adacraft.Protocol.Login.Login_Start_Status;
      Lay    : Adacraft.Protocol.Packet_Decoder.Layout_Type;
      Dec_Id : Interfaces.Integer_32 := 0;
      Fields : Adacraft.Protocol.Packet_Decoder.Field_Array;
      F_Cnt  : Natural := 0;
      D_St   : Adacraft.Protocol.Packet_Decoder.Decode_Status :=
        Adacraft.Protocol.Packet_Decoder.Rejected;
      LS     : Adacraft.Protocol.Login.Login_Start;
      Valid  : Boolean;
      D      : Adacraft.Protocol.Frame.Frame_Decode;
      Val    : Interfaces.Integer_32 := 0;
      Got    : Natural := 0;
      Vst    : Adacraft.Protocol.Varnum.Status_Type :=
        Adacraft.Protocol.Varnum.Ok;
   begin
      if Frame_Body'Length = 0 then
         return;
      end if;
      Adacraft.Protocol.Varnum.Decode
        (Frame_Body, Frame_Body'First, Val, Got, Vst);
      D := Adacraft.Protocol.Frame.Decode_Frame
        (Frame_Body, Frame_Body'First);
      Lay.Count := 0;
      Adacraft.Protocol.Packet_Decoder.Decode
        (Frame_Body, Lay, Dec_Id, Fields, F_Cnt, D_St);
      if D_St /= Adacraft.Protocol.Packet_Decoder.Rejected then
         null;
      end if;
      if Dec_Id < 0 then
         Valid := False;
      else
         Valid := Adacraft.Protocol.State.Table.Is_Serverbound_Login
           (Adacraft.Protocol.State.Login,
            Adacraft.Protocol.State.Packet_Id (Dec_Id));
      end if;
      LS := Adacraft.Protocol.Login.Decode_Login_Start (Frame_Body);
      if Valid and then LS.Status = LS.Status then
         null;
      end if;
   end Handle_Login;

   procedure Touch_Login_Path is
      Empty : Adacraft.Protocol.Octets (2 .. 1) := (others => <>);
   begin
      Handle_Login (Empty);
   end Touch_Login_Path;

begin
   --  Event-driven server: Parse_Port -> Initialize_Listener ->
   --  Run_Event_Loop.  Per-connection dispatch (Handshake_Exchange /
   --  Status_Exchange / Handle_Login via Frame.Feed -> Packet_Decoder ->
   --  State.Table -> Login -> Packet_Encoder) lives in Adacraft.Network.
   --  Login branch (Handle_Frame_Body, Login state): well-formed Login
   --  Start (v=777 or v/=777, already transitioned to Login) answers one
   --  framed 777 Login Disconnect then clean-closes only that connection;
   --  invalid-in-Login closes with no reply.  Packet_Decoder is on the R1
   --  path via the Login gate decode.
   --  Parse_Port lives in Adacraft.Network so unit tests can with it
   --  directly; the server and the tests call the same implementation.
   if Ada.Command_Line.Argument_Count >= 1 then
      declare
         Arg : constant String := Ada.Command_Line.Argument (1);
         P   : GNAT.Sockets.Port_Type;
      begin
         Adacraft.Network.Parse_Port (Arg, P);
         Port := P;
      exception
         when others =>
            Ada.Text_IO.Put_Line
              (Ada.Text_IO.Standard_Error,
               "adacraft_server: invalid port """ & Arg
               & """: must be 1..65535");
            GNAT.OS_Lib.OS_Exit (1);
      end;
   end if;
   Ada.Text_IO.Put_Line
     ("AdaCraft " & Adacraft.Minecraft_Version
      & " protocol" & Adacraft.Protocol_Version'Image
      & " listening on" & Port'Image);
   declare
      use GNAT.Sockets;
      Listener : Socket_Type;
   begin
      Adacraft.Network.Initialize_Listener (Port, Listener);
      Adacraft.Network.Run_Event_Loop (Listener);
   end;
end Adacraft_Server;
