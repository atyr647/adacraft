with Ada.Calendar;
with Ada.Streams;
with GNAT.Sockets;
with Adacraft.Protocol;
with Adacraft.Protocol.Frame;
with Adacraft.Protocol.Handshake_Exchange;
with Adacraft.Protocol.State;
with Adacraft.Protocol.Status_Exchange;

package Adacraft.Network is
   Read_Timeout : constant Duration := 30.0;
   Selector_Tick : constant Duration := 0.5;
   Max_Conns : constant := 64;
   Send_Capacity : constant := 40_000;
   Recv_Capacity : constant := 8_192;

   Default_Compression_Threshold : constant Integer := 256;

   type Conn is record
      Sock          : GNAT.Sockets.Socket_Type;
      Has_Sock      : Boolean := False;
      Fd_Key        : Integer := -1;
      Recv_Buf      : Ada.Streams.Stream_Element_Array (1 .. 8_192);
      Recv_Len      : Natural := 0;
      Frame_State   : Adacraft.Protocol.Frame.Decoder_Type;
      Proto_State   : Adacraft.Protocol.State.Connection_State :=
        Adacraft.Protocol.State.Initial_State;
      Stored        : Adacraft.Protocol.Handshake_Exchange.Connection_Data;
      Sess          : Adacraft.Protocol.Status_Exchange.Session;
      Last_Activity : Ada.Calendar.Time := Ada.Calendar.Clock;
      Send_Buf      : Ada.Streams.Stream_Element_Array (1 .. 40_000);
      Send_Pos      : Positive := 1;
      Send_Len      : Natural := 0;
      Closing       : Boolean := False;
      In_Use        : Boolean := False;
      Compression_Threshold : Integer := Default_Compression_Threshold;
      Compression_Active  : Boolean := False;
      Compression_Sent    : Boolean := False;
   end record;

   type Conn_Access is access Conn;
   Conn_Table : array (1 .. Max_Conns) of Conn_Access := (others => null);

   procedure Initialize_Listener
     (Port     : GNAT.Sockets.Port_Type;
      Listener : out GNAT.Sockets.Socket_Type);

   procedure Run_Event_Loop (Listener : GNAT.Sockets.Socket_Type);

   procedure Accept_Ready (Listener : GNAT.Sockets.Socket_Type);

   procedure Service_Readable (Idx : Positive);

   procedure Service_Writable (Idx : Positive);

   procedure Close_Conn (Idx : Positive; Reason : String := "");

   procedure Parse_Port (Image : String; Port : out GNAT.Sockets.Port_Type);

   procedure Configure_Compression
     (C         : Conn_Access;
      Threshold : Integer := Default_Compression_Threshold);
   --  Single constructor/config parameter for compression (A1).
   --  Negative disables compression. Per-connection only, no globals.

   procedure Send_Set_Compression (C : Conn_Access);
   --  LOGIN-only, exactly-once Set Compression send. Guard: skip when
   --  Threshold < 0 or Compression_Sent or Proto_State /= LOGIN.
   --  The Set Compression frame itself uses uncompressed framing
   --  (still through CFB8 when active); on success flips
   --  Compression_Active so the next egress (Login Success) is the
   --  first compressed frame. Persists until close.

   procedure Serve (Port : GNAT.Sockets.Port_Type);
end Adacraft.Network;
