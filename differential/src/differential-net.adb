with Ada.Unchecked_Deallocation;
with Interfaces;
with Adacraft.Protocol.Varnum;
with Adacraft.Protocol;

package body Differential.Net is

   use Ada.Streams;
   use GNAT.Sockets;
   namespace_dummy : constant Boolean := True;
   pragma Unreferenced (namespace_dummy);

   package Frame renames Adacraft.Protocol.Frame;

   procedure Free is new Ada.Unchecked_Deallocation
     (Frame.Decoder_Type, Decoder_Access);

   function To_Dur (Ms : Natural) return Duration is
     (Duration (Ms) / 1000.0);

   procedure Close (Conn : in out Connection) is
   begin
      if Conn.Open then
         begin
            Close_Socket (Conn.Sock);
         exception
            when others => null;
         end;
         Conn.Open := False;
      end if;
      if Conn.Decoder /= null then
         Free (Conn.Decoder);
      end if;
   end Close;

   procedure Connect
     (Conn       : out Connection;
      Host       : String;
      Port       : Natural;
      Timeout_Ms : Natural;
      Ok         : out Boolean)
   is
      Addr   : Sock_Addr_Type;
      Status : Selector_Status;
   begin
      Conn.Open := False;
      Conn.Decoder := null;
      Ok := False;
      begin
         if Port > 65_535 then
            return;
         end if;
         begin
            Addr.Addr := Inet_Addr (Host);
         exception
            when others =>
               Addr.Addr := Addresses (Get_Host_By_Name (Host), 1);
         end;
         Addr.Port := Port_Type (Port);
         Create_Socket (Conn.Sock);
         Conn.Open := True;
         Connect_Socket (Conn.Sock, Addr, To_Dur (Timeout_Ms), Status);
         if Status /= Completed then
            Close (Conn);
            return;
         end if;
         Conn.Decoder := new Frame.Decoder_Type;
         Conn.Pos := 1;
         Conn.Last := 0;
         Conn.In_Prefix := True;
         Conn.Pfx_Count := 0;
         Conn.Failed := False;
         Ok := True;
      exception
         when others =>
            Ok := False;
            Close (Conn);
      end;
   end Connect;

   function Send
     (Conn : Connection; Data : Stream_Element_Array) return Boolean
   is
      From : Stream_Element_Offset := Data'First;
      Sent : Stream_Element_Offset;
   begin
      if not Conn.Open then
         return False;
      end if;
      while From <= Data'Last loop
         Send_Socket (Conn.Sock, Data (From .. Data'Last), Sent);
         if Sent < From then
            return False;
         end if;
         From := Sent + 1;
      end loop;
      return True;
   exception
      when others =>
         return False;
   end Send;

   function Id_Of (Data : Frame.Byte_Array; Id : out Natural) return Boolean
   is
      N      : constant Natural := Natural'Min (5, Data'Length);
      Buf    : Adacraft.Protocol.Octets (1 .. 5) := (others => 0);
      Value  : Interfaces.Integer_32;
      Used   : Natural;
      Status : Adacraft.Protocol.Varnum.Status_Type;
      use type Adacraft.Protocol.Varnum.Status_Type;
      use type Interfaces.Integer_32;
   begin
      Id := 0;
      if N = 0 then
         return False;
      end if;
      for I in 1 .. N loop
         Buf (I) :=
           Adacraft.Protocol.Octet (Data (Data'First + Stream_Element_Offset (I - 1)));
      end loop;
      Adacraft.Protocol.Varnum.Decode
        (Buf (1 .. N), 1, Value, Used, Status);
      if Status /= Adacraft.Protocol.Varnum.Ok or else Value < 0 then
         return False;
      end if;
      Id := Natural (Value);
      return True;
   end Id_Of;

   procedure Receive_Frame
     (Conn       : in out Connection;
      Timeout_Ms : Natural;
      Result     : out Receive_Result)
   is
      Got      : Boolean := False;
      Got_Id   : Natural := 0;
      Id_Good  : Boolean := False;

      procedure On_Frame (F : in Frame.Byte_Array) is
      begin
         Got := True;
         Id_Good := Id_Of (F, Got_Id);
      end On_Frame;

      procedure Fill (Done : out Boolean) is
         R, W   : Socket_Set_Type;
         Status : Selector_Status;
      begin
         Done := True;
         Empty (R);
         Empty (W);
         Set (R, Conn.Sock);
         Check_Selector (R, W, Status, To_Dur (Timeout_Ms));
         Empty (R);
         Empty (W);
         if Status = Expired then
            Result := (Kind => Timed_Out);
            return;
         elsif Status /= Completed then
            Result := (Kind => Closed);
            return;
         end if;
         Receive_Socket (Conn.Sock, Conn.Pending, Conn.Last);
         Conn.Pos := 1;
         if Conn.Last < 1 then
            Conn.Last := 0;
            if Conn.In_Prefix and then Conn.Pfx_Count = 0 then
               Result := (Kind => Closed);
            else
               Result := (Kind => Bad_Frame, Reason => Obs.Truncated_Frame);
            end if;
            return;
         end if;
         Done := False;
      exception
         when others =>
            Conn.Last := 0;
            Done := True;
            if Conn.In_Prefix and then Conn.Pfx_Count = 0 then
               Result := (Kind => Closed);
            else
               Result := (Kind => Bad_Frame, Reason => Obs.Truncated_Frame);
            end if;
      end Fill;

   begin
      Result := (Kind => Closed);
      if not Conn.Open or else Conn.Decoder = null then
         return;
      end if;
      if Conn.Failed then
         Result := (Kind => Bad_Frame, Reason => Conn.Fail_Why);
         return;
      end if;

      loop
         while Conn.Pos <= Conn.Last loop
            declare
               B      : constant Stream_Element := Conn.Pending (Conn.Pos);
               One    : constant Frame.Byte_Array (1 .. 1) := (1 => B);
               Status : Frame.Feed_Status;
               Cont   : constant Boolean := (B and 16#80#) /= 0;
            begin
               Conn.Pos := Conn.Pos + 1;
               Got := False;
               Frame.Feed (Conn.Decoder.all, One, On_Frame'Access, Status);
               if Status = Frame.Framing_Error then
                  Conn.Failed := True;
                  if Cont and then Conn.Pfx_Count + 1 >= Frame.Max_Frame_Prefix_Bytes
                  then
                     Conn.Fail_Why := Obs.Overlong_Length;
                  else
                     Conn.Fail_Why := Obs.Oversized_Length;
                  end if;
                  Result := (Kind => Bad_Frame, Reason => Conn.Fail_Why);
                  return;
               end if;
               if Got then
                  Conn.In_Prefix := True;
                  Conn.Pfx_Count := 0;
                  if Id_Good then
                     Result := (Kind => Frame_Received, Packet_Id => Got_Id);
                  else
                     Result :=
                       (Kind => Bad_Frame, Reason => Obs.Bad_Packet_Id);
                  end if;
                  return;
               elsif Conn.In_Prefix then
                  if Cont then
                     Conn.Pfx_Count := Conn.Pfx_Count + 1;
                  else
                     Conn.In_Prefix := False;
                  end if;
               end if;
            end;
         end loop;

         declare
            Done : Boolean;
         begin
            Fill (Done);
            exit when Done;
         end;
      end loop;
   exception
      when others =>
         Result := (Kind => Closed);
   end Receive_Frame;

end Differential.Net;
