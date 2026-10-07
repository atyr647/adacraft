with Ada.Streams;
with Ada.Strings.Unbounded;

package body Test_Fake_Server is

   use Ada.Streams;
   use GNAT.Sockets;
   use Ada.Strings.Unbounded;

   protected body Flag is
      procedure Stop is
      begin
         Flagged := True;
      end Stop;

      function Stopped return Boolean is (Flagged);
   end Flag;

   protected body Counter is
      procedure Inc is
      begin
         N := N + 1;
      end Inc;

      function Value return Natural is (N);
   end Counter;

   function Send (Data : String) return Action is
     ((Kind => Send_Bytes, Data => To_Unbounded_String (Data)));
   function Raw (Data : String) return Action is
     ((Kind => Send_Raw, Data => To_Unbounded_String (Data)));
   function Close_Now return Action is
     ((Kind => Close, Data => Null_Unbounded_String));
   function Hold_Silent return Action is
     ((Kind => Silence, Data => Null_Unbounded_String));
   function Refuse_All return Action is
     ((Kind => Refuse, Data => Null_Unbounded_String));

   procedure Put_Bytes (C : Socket_Type; Data : String) is
      Arr  : Stream_Element_Array (1 .. Stream_Element_Offset (Data'Length));
      Last : Stream_Element_Offset;
   begin
      if Data'Length = 0 then
         return;
      end if;
      for K in Arr'Range loop
         Arr (K) := Stream_Element
           (Character'Pos (Data (Data'First + Natural (K) - 1)));
      end loop;
      Send_Socket (C, Arr, Last);
   exception
      when others => null;
   end Put_Bytes;

   procedure Run_Script (I : Instance_Access; C : in out Socket_Type) is
   begin
      for A of I.Script loop
         case A.Kind is
            when Send_Bytes | Send_Raw =>
               Put_Bytes (C, To_String (A.Data));
            when Close | Refuse =>
               exit;
            when Silence =>
               declare
                  R, W : Socket_Set_Type;
                  St   : Selector_Status;
                  Buf  : Stream_Element_Array (1 .. 256);
                  Last : Stream_Element_Offset;
               begin
                  while not I.Stop_Flag.Stopped loop
                     Empty (R);
                     Empty (W);
                     Set (R, C);
                     Check_Selector (R, W, St, 0.05);
                     if St = Completed then
                        Receive_Socket (C, Buf, Last);
                        exit when Last < 1;
                     end if;
                  end loop;
                  Empty (R);
                  Empty (W);
               exception
                  when others => null;
               end;
               exit;
         end case;
      end loop;
      begin
         Close_Socket (C);
      exception
         when others => null;
      end;
   end Run_Script;

   task body Worker is
      Inst : Instance_Access;
   begin
      select
         accept Go (I : Instance_Access) do
            Inst := I;
         end Go;
      or
         terminate;
      end select;

      while not Inst.Stop_Flag.Stopped loop
         declare
            R, W : Socket_Set_Type;
            St   : Selector_Status;
            C    : Socket_Type;
            Addr : Sock_Addr_Type;
         begin
            Empty (R);
            Empty (W);
            Set (R, Inst.Listener);
            Check_Selector (R, W, St, 0.05);
            Empty (R);
            Empty (W);
            if St = Completed then
               Accept_Socket (Inst.Listener, C, Addr);
               Inst.Count.Inc;
               Run_Script (Inst, C);
            end if;
         exception
            when others => null;
         end;
      end loop;
   end Worker;

   procedure Start (S : in out Server; Script : Action_Vectors.Vector) is
      Addr : Sock_Addr_Type :=
        (Family => Family_Inet, Addr => Loopback_Inet_Addr, Port => 0);
   begin
      S.Impl := new Instance;
      S.Impl.Script := Script;
      Create_Socket (S.Impl.Listener);
      Set_Socket_Option
        (S.Impl.Listener, Socket_Level, (Reuse_Address, True));
      Bind_Socket (S.Impl.Listener, Addr);
      Listen_Socket (S.Impl.Listener);
      S.Impl.Bound := Natural (Get_Socket_Name (S.Impl.Listener).Port);
      if not Script.Is_Empty and then Script.First_Element.Kind = Refuse then
         --  Port number stays reserved in the test, nothing listens.
         Close_Socket (S.Impl.Listener);
         S.Impl.Listener := No_Socket;
      else
         S.Impl.Started := True;
         S.Impl.W.Go (S.Impl);
      end if;
   end Start;

   function Port (S : Server) return Natural is (S.Impl.Bound);

   function Accepts (S : Server) return Natural is
     (S.Impl.Count.Value);

   procedure Stop (S : in out Server) is
   begin
      if S.Impl = null then
         return;
      end if;
      S.Impl.Stop_Flag.Stop;
      if S.Impl.Started then
         while not S.Impl.W'Terminated loop
            delay 0.01;
         end loop;
         begin
            Close_Socket (S.Impl.Listener);
         exception
            when others => null;
         end;
      end if;
   end Stop;

end Test_Fake_Server;
