with Ada.Command_Line;
with Ada.Streams;
with Ada.Text_IO;
with Adacraft.Ingress;
with Adacraft.Protocol.Frame;

procedure Test_Ingress_Framing is
   package Ingress renames Adacraft.Ingress;
   package Frame renames Adacraft.Protocol.Frame;
   use type Ada.Streams.Stream_Element_Offset;

   Failures : Natural := 0;
   B1, C1, B2, C2 : Natural := 0;

   procedure Check (Cond : Boolean; Name : String) is
   begin
      if not Cond then
         Ada.Text_IO.Put_Line ("FAIL " & Name);
         Failures := Failures + 1;
      end if;
   end Check;

   procedure Body_1 (Data : Ingress.Byte_Array) is
      pragma Unreferenced (Data);
   begin
      B1 := B1 + 1;
   end Body_1;

   procedure Close_1 is
   begin
      C1 := C1 + 1;
   end Close_1;

   procedure Body_2 (Data : Ingress.Byte_Array) is
      pragma Unreferenced (Data);
   begin
      B2 := B2 + 1;
   end Body_2;

   procedure Close_2 is
   begin
      C2 := C2 + 1;
   end Close_2;

   Conn_1 : Ingress.Connection_Type;
   Conn_2 : Ingress.Connection_Type;

   Bad     : constant Ingress.Byte_Array (1 .. 4) := (16#80#, 16#80#, 16#80#, 16#80#);
   Empty   : constant Ingress.Byte_Array (1 .. 0) := (others => 0);
   Payload : constant Ingress.Byte_Array (1 .. 3) := (1, 2, 3);
   Wire    : Ingress.Byte_Array (1 .. 16);
   Last    : Ada.Streams.Stream_Element_Offset;
   Status  : Frame.Encode_Status;
   use type Frame.Encode_Status;
begin
   Check (Ingress.Is_Closed (Conn_1), "default closed");

   Ingress.Initialize (Conn_1, Body_1'Unrestricted_Access, Close_1'Unrestricted_Access);
   Ingress.Initialize (Conn_2, Body_2'Unrestricted_Access, Close_2'Unrestricted_Access);
   Check (not Ingress.Is_Closed (Conn_1), "open after init");

   Frame.Encode (Payload, Wire, Last, Status);
   Check (Status = Frame.Ok and then Last = 4, "encode valid frame");

   Ingress.Receive (Conn_1, Bad);
   Check (Ingress.Is_Closed (Conn_1), "closed on framing error");
   Check (C1 = 1, "close once");
   Check (B1 = 0, "no body on error");

   Ingress.Receive (Conn_1, Wire (1 .. Last));
   Ingress.Receive (Conn_1, Bad);
   Check (B1 = 0, "closed discards bodies");
   Check (C1 = 1, "close not repeated");

   Ingress.Receive (Conn_2, Empty);
   Ingress.Receive (Conn_2, Wire (1 .. 2));
   Check (B2 = 0, "partial frame not delivered");
   Ingress.Receive (Conn_2, Wire (3 .. Last));
   Check (B2 = 1, "split frame delivered once");
   Check (not Ingress.Is_Closed (Conn_2) and then C2 = 0, "isolation");

   if Failures = 0 then
      Ada.Text_IO.Put_Line ("ingress framing tests passed");
   else
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
   end if;
end Test_Ingress_Framing;
