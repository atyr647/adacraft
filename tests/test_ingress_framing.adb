with Ada.Command_Line;
with Ada.Streams;
with Ada.Text_IO;
with Adacraft.Ingress;
with Adacraft.Protocol;
with Adacraft.Protocol.Frame;

procedure Test_Ingress_Framing is
   package Ingress renames Adacraft.Ingress;
   package Frame renames Adacraft.Protocol.Frame;
   use type Ada.Streams.Stream_Element_Offset;
   use type Ada.Streams.Stream_Element_Array;
   use type Frame.Encode_Status;

   Failures : Natural := 0;

   Body_Count, Close_Count : Natural := 0;   --  connection 1
   B2, C2                  : Natural := 0;   --  connection 2
   B3, C3                  : Natural := 0;   --  connection 3
   Bodies_At_Close_3       : Natural := 0;

   procedure Check (Cond : Boolean; Name : String) is
   begin
      if not Cond then
         Ada.Text_IO.Put_Line ("FAIL " & Name);
         Failures := Failures + 1;
      end if;
   end Check;

   procedure On_Body (Data : Ingress.Byte_Array) is
      pragma Unreferenced (Data);
   begin
      Body_Count := Body_Count + 1;
   end On_Body;

   procedure On_Close is
   begin
      Close_Count := Close_Count + 1;
   end On_Close;

   procedure Body_2 (Data : Ingress.Byte_Array) is
      pragma Unreferenced (Data);
   begin
      B2 := B2 + 1;
   end Body_2;

   procedure Close_2 is
   begin
      C2 := C2 + 1;
   end Close_2;

   procedure Body_3 (Data : Ingress.Byte_Array) is
      pragma Unreferenced (Data);
   begin
      B3 := B3 + 1;
   end Body_3;

   procedure Close_3 is
   begin
      C3 := C3 + 1;
      Bodies_At_Close_3 := B3;
   end Close_3;

   --  Decoders embed a large body buffer, so connections live on the heap.
   type Conn_Access is access Ingress.Connection_Type;
   Conn_1 : constant Conn_Access := new Ingress.Connection_Type;
   Conn_2 : constant Conn_Access := new Ingress.Connection_Type;
   Conn_3 : constant Conn_Access := new Ingress.Connection_Type;

   Bad     : constant Ingress.Byte_Array (1 .. 4) := (16#80#, 16#80#, 16#80#, 16#80#);
   Empty   : constant Ingress.Byte_Array (1 .. 0) := (others => 0);
   Payload : constant Ingress.Byte_Array (1 .. 3) := (1, 2, 3);
   Wire    : Ingress.Byte_Array (1 .. 16);
   Last    : Ada.Streams.Stream_Element_Offset;
   Status  : Frame.Encode_Status;
begin
   Check (Ingress.Is_Closed (Conn_1.all), "default closed");

   Ingress.Initialize (Conn_1.all, On_Body'Unrestricted_Access, On_Close'Unrestricted_Access);
   Ingress.Initialize (Conn_2.all, Body_2'Unrestricted_Access, Close_2'Unrestricted_Access);
   Ingress.Initialize (Conn_3.all, Body_3'Unrestricted_Access, Close_3'Unrestricted_Access);
   Check (not Ingress.Is_Closed (Conn_1.all), "open after init");

   Frame.Encode (Payload, Wire, Last, Status);
   Check (Status = Frame.Ok and then Last = 4, "encode valid frame");

   --  (1) Framing error closes the connection.
   Ingress.Receive (Conn_1.all, Bad);
   Check (Ingress.Is_Closed (Conn_1.all), "closed on framing error");
   Check (Close_Count = 1, "close once");
   Check (Body_Count = 0, "no body on error");

   --  (2) Closed connection discards everything.
   Ingress.Receive (Conn_1.all, Wire (1 .. Last));
   Ingress.Receive (Conn_1.all, Bad);
   Ingress.Receive (Conn_1.all, Empty);
   Check (Body_Count = 0, "closed discards bodies");
   Check (Close_Count = 1, "close not repeated");
   Check (Ingress.Is_Closed (Conn_1.all), "stays closed");

   --  (3) Split frame with an empty chunk, delivered exactly once.
   Ingress.Receive (Conn_2.all, Empty);
   Ingress.Receive (Conn_2.all, Wire (1 .. 2));
   Ingress.Receive (Conn_2.all, Empty);
   Check (B2 = 0, "partial frame not delivered");
   Ingress.Receive (Conn_2.all, Wire (3 .. Last));
   Check (B2 = 1, "split frame delivered once");
   Ingress.Receive (Conn_2.all, Empty);
   Check (B2 = 1, "empty chunk adds nothing");

   --  Isolation: connection 2 still works after connection 1 closed.
   Ingress.Receive (Conn_2.all, Wire (1 .. Last));
   Check (B2 = 2, "second connection still delivers");
   Check (not Ingress.Is_Closed (Conn_2.all) and then C2 = 0, "isolation");

   --  Body before a framing error in the same chunk is kept; close after it.
   declare
      Mixed : constant Ingress.Byte_Array (1 .. Last + 4) := Wire (1 .. Last) & Bad;
   begin
      Ingress.Receive (Conn_3.all, Mixed);
   end;
   Check (B3 = 1, "pre-error body handed off");
   Check (C3 = 1, "close fired once");
   Check (Bodies_At_Close_3 = 1, "close after body hand-off");
   Check (Ingress.Is_Closed (Conn_3.all), "closed after mixed chunk");
   Ingress.Receive (Conn_3.all, Wire (1 .. Last));
   Check (B3 = 1 and then C3 = 1, "mixed connection discards later input");
   Check (not Ingress.Is_Closed (Conn_2.all), "others unaffected");

   --  (4) Zero-length frame (00 prefix) is a protocol error with no
   --  packet, identically for Feed and Decode_Frame (shared core).
   declare
      use type Adacraft.Protocol.Status_Kind;
      use type Frame.Feed_Status;
      Zero_Chunk : constant Frame.Byte_Array (1 .. 1) := (1 => 16#00#);
      Zero_Buf   : constant Adacraft.Protocol.Octets (1 .. 1) := (1 => 16#00#);
      D          : Frame.Decoder_Type;
      Got_Body   : Natural := 0;
      FS         : Frame.Feed_Status;
      R          : Frame.Frame_Decode;
      procedure No_Body (F : Frame.Byte_Array) is
         pragma Unreferenced (F);
      begin
         Got_Body := Got_Body + 1;
      end No_Body;
   begin
      Frame.Feed (D, Zero_Chunk, No_Body'Access, FS);
      R := Frame.Decode_Frame (Zero_Buf, 1);
      Check (FS = Frame.Framing_Error, "feed zero-length is error");
      Check (Got_Body = 0, "feed zero-length no packet");
      Check (R.Status = Adacraft.Protocol.Rejected, "decode zero-length is error");
      Check (R.Packet_Id = 0 and then R.Next = 1, "decode zero-length no packet");
      Check ((FS = Frame.Framing_Error) = (R.Status = Adacraft.Protocol.Rejected)
             and then Got_Body = 0, "zero-length same outcome");
   end;

   if Failures = 0 then
      Ada.Text_IO.Put_Line ("ingress framing tests passed");
   else
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
   end if;
end Test_Ingress_Framing;
