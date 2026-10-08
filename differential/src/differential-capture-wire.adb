with Ada.Exceptions;
with Ada.Streams;
with GNAT.Sockets;
with Adacraft.Ingress;
with Adacraft.Protocol.Frame;
with Adacraft.Protocol.Varnum;

package body Differential.Capture.Wire is
   use Ada.Streams;
   use GNAT.Sockets;

   procedure Connect
     (Target : in out Connection;
      Host   : String;
      Port   : Positive)
   is
      Address : Sock_Addr_Type;
      Entry   : constant Host_Entry_Type := Get_Host_By_Name (Host);
      Option  : constant Socket_Option_Type :=
        (Name    => Receive_Timeout,
         Enabled => True,
         Timeout => Read_Timeout);
   begin
      if Port > 65_535 then
         raise Socket_Error with "port is outside 1..65535";
      end if;

      Create_Socket (Target.Socket, Family_Inet, Socket_Stream);
      Address.Addr := Addresses (Entry, 1);
      Address.Port := Port_Type (Port);
      Connect_Socket (Target.Socket, Address);
      Set_Socket_Option (Target.Socket, Level_Socket, Option);
      Target.Open := True;
   exception
      when others =>
         if Target.Open then
            Close (Target);
         else
            begin
               Close_Socket (Target.Socket);
            exception
               when others => null;
            end;
         end if;
         raise;
   end Connect;

   procedure Close (Target : in out Connection) is
   begin
      if Target.Open then
         Close_Socket (Target.Socket);
         Target.Open := False;
      end if;
   end Close;

   procedure Send_Packet
     (Target    : in out Connection;
      Packet_Id : Adacraft.Protocol.Packet_Id;
      Payload   : Adacraft.Protocol.Octets)
   is
      use type Ada.Streams.Stream_Element_Offset;
      use type Adacraft.Protocol.Varnum.Status_Type;
      Body_Bytes : Adacraft.Protocol.Octets
        (1 .. Payload'Length + Adacraft.Protocol.Max_Varint_Bytes);
      Written    : Natural;
      Status     : Adacraft.Protocol.Varnum.Status_Type;
   begin
      Adacraft.Protocol.Varnum.Encode
        (Interfaces.Integer_32 (Packet_Id), Body_Bytes, 1, Written, Status);
      if Status /= Adacraft.Protocol.Varnum.Ok then
         raise Socket_Error with "could not encode packet ID";
      end if;

      if Payload'Length > 0 then
         Body_Bytes (Written + 1 .. Written + Payload'Length) := Payload;
      end if;

      declare
         Body_Last : constant Natural := Written + Payload'Length;
         Framed    : Stream_Element_Array
           (1 .. Stream_Element_Offset (Body_Last + 3));
         Last      : Stream_Element_Offset;
         Frame_Status : Adacraft.Protocol.Frame.Encode_Status;
      begin
         Adacraft.Protocol.Frame.Encode
           (Payload => (declare
              Data : Stream_Element_Array (1 .. Stream_Element_Offset (Body_Last));
           begin
              for I in Data'Range loop
                 Data (I) := Stream_Element (Body_Bytes (Positive (I)));
              end loop;
              Data),
            Output => Framed,
            Last   => Last,
            Status => Frame_Status);

         if Frame_Status /= Adacraft.Protocol.Frame.Ok then
            raise Socket_Error with "could not encode frame";
         end if;
         Send_All (Target.Socket, Framed (1 .. Last));
      end;
   end Send_Packet;

   procedure Receive_Packet
     (Target    : in out Connection;
      Packet_Id : out Adacraft.Protocol.Packet_Id)
   is
      Ingress : Adacraft.Ingress.Connection_Type;
      Found   : Boolean := False;
      Failed  : Boolean := False;

      procedure On_Body (Data : Adacraft.Ingress.Byte_Array) is
         Bytes    : Adacraft.Protocol.Octets (1 .. Natural (Data'Length));
         Value    : Interfaces.Integer_32;
         Consumed : Natural;
         Status   : Adacraft.Protocol.Varnum.Status_Type;
      begin
         if Data'Length = 0 then
            Failed := True;
            return;
         end if;

         for I in Data'Range loop
            Bytes (Positive (I - Data'First + 1)) :=
              Adacraft.Protocol.Octet (Data (I));
         end loop;

         Adacraft.Protocol.Varnum.Decode (Bytes, Bytes'First, Value, Consumed, Status);
         if Status /= Adacraft.Protocol.Varnum.Ok then
            Failed := True;
         else
            Packet_Id := Adacraft.Protocol.Packet_Id (Value);
            Found := True;
         end if;
      end On_Body;

      procedure On_Close is
      begin
         Failed := True;
      end On_Close;

      Buffer : Stream_Element_Array (1 .. 4096);
   begin
      if not Target.Open then
         raise Socket_Error with "connection is not open";
      end if;

      Adacraft.Ingress.Initialize (Ingress, On_Body'Access, On_Close'Access);
      while not Found and then not Failed loop
         declare
            Last : Stream_Element_Offset;
         begin
            Receive_Socket (Target.Socket, Buffer, Last);
            if Last < Buffer'First then
               Failed := True;
            else
               Adacraft.Ingress.Receive (Ingress, Buffer (Buffer'First .. Last));
            end if;
         exception
            when Socket_Error =>
               Failed := True;
         end;
      end loop;

      if Failed then
         raise Socket_Error with "peer closed, timed out, or sent an invalid frame";
      end if;
   end Receive_Packet;

   procedure Send_All
     (Socket : Socket_Type;
      Data   : Stream_Element_Array)
   is
      First : Stream_Element_Offset := Data'First;
   begin
      while First <= Data'Last loop
         declare
            Last : Stream_Element_Offset;
         begin
            Send_Socket (Socket, Data (First .. Data'Last), Last);
            if Last < First then
               raise Socket_Error with "socket send made no progress";
            end if;
            First := Last + 1;
         end;
      end loop;
   end Send_All;
end Differential.Capture.Wire;
