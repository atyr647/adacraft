with Ada.Calendar;
with Ada.Directories;
with Ada.Environment_Variables;
with Ada.Strings.Fixed;
with Ada.Text_IO;
with Adacraft.Protocol;
with GNAT.OS_Lib;
with Differential.Client;
with Differential.Extract;
with Differential.Obs;

package body Differential.Target.Oracle is

   package SU renames Ada.Strings.Unbounded;
   package OS renames GNAT.OS_Lib;
   package C renames Differential.Client;
   use type Ada.Calendar.Time;
   use type OS.Process_Id;
   use type OS.String_Access;
   use type GNAT.Sockets.Port_Type;

   function Img (N : Integer) return String is
     (Ada.Strings.Fixed.Trim (Integer'Image (N), Ada.Strings.Left));

   function Infra (Msg : String) return Run_Result is
   begin
      return (Category => Infrastructure,
              Observation => <>,
              Detail => SU.To_Unbounded_String (Msg));
   end Infra;

   ---------------------------------------------------------------- files

   function Properties (Port : GNAT.Sockets.Port_Type) return String is
      LF : constant Character := ASCII.LF;
   begin
      return
        "online-mode=false" & LF
        & "server-ip=127.0.0.1" & LF
        & "server-port=" & Img (Integer (Port)) & LF
        & "network-compression-threshold=-1" & LF
        & "max-players=20" & LF
        & "motd=AdaCraft Differential" & LF
        & "level-name=world" & LF
        & "level-type=minecraft\:flat" & LF
        & "generate-structures=false" & LF
        & "spawn-protection=0" & LF
        & "view-distance=2" & LF
        & "simulation-distance=2" & LF
        & "enable-rcon=false" & LF
        & "enable-query=false" & LF
        & "sync-chunk-writes=false" & LF;
   end Properties;

   procedure Put_File (Path, Text : String) is
      F : Ada.Text_IO.File_Type;
   begin
      Ada.Text_IO.Create (F, Ada.Text_IO.Out_File, Path);
      Ada.Text_IO.Put (F, Text);
      Ada.Text_IO.Close (F);
   end Put_File;

   procedure Write_Server_Files
     (Dir : String; Port : GNAT.Sockets.Port_Type) is
   begin
      Put_File (Ada.Directories.Compose (Dir, "eula.txt"),
                "eula=true" & ASCII.LF);
      Put_File (Ada.Directories.Compose (Dir, "server.properties"),
                Properties (Port));
   end Write_Server_Files;

   ---------------------------------------------------------------- process

   procedure Start
     (Owner : in out Process_Owner;
      Java  : String;
      Jar   : String;
      Dir   : String;
      Log   : String;
      Ok    : out Boolean)
   is
      Old  : constant String := Ada.Directories.Current_Directory;
      Args : OS.Argument_List :=
        (new String'("-Xmx1G"), new String'("-jar"),
         new String'(Jar), new String'("nogui"));
      Pid  : OS.Process_Id;
   begin
      Ok := False;
      Ada.Directories.Set_Directory (Dir);
      Pid := OS.Non_Blocking_Spawn (Java, Args, Log, True);
      Ada.Directories.Set_Directory (Old);
      OS.Free (Args);
      if Pid /= OS.Invalid_Pid then
         Owner.Pid := OS.Pid_To_Integer (Pid);
         Owner.Running := True;
         Ok := True;
      end if;
   exception
      when others =>
         begin
            Ada.Directories.Set_Directory (Old);
         exception
            when others => null;
         end;
         Ok := False;
   end Start;

   procedure Stop (Owner : in out Process_Owner) is
   begin
      if not Owner.Running then
         return;
      end if;
      Owner.Running := False;
      declare
         Pk : OS.String_Access := OS.Locate_Exec_On_Path ("pkill");
      begin
         if Pk /= null then
            declare
               Args : OS.Argument_List :=
                 (new String'("-KILL"), new String'("-P"),
                  new String'(Img (Owner.Pid)));
               Ok   : Boolean;
            begin
               OS.Spawn (Pk.all, Args, Ok);
               OS.Free (Args);
            end;
            OS.Free (Pk);
         end if;
      exception
         when others => null;
      end;
      declare
         Pid  : OS.Process_Id;
         Done : Boolean;
      begin
         OS.Kill (OS.Process_Id'(Pid_Of (Owner.Pid)), True);
         OS.Wait_Process (Pid, Done);
      exception
         when others => null;
      end;
   end Stop;

   function Is_Running (Owner : Process_Owner) return Boolean is
     (Owner.Running);

   overriding procedure Finalize (Owner : in out Process_Owner) is
   begin
      Stop (Owner);
   end Finalize;

   ---------------------------------------------------------------- probe

   function Status_Probe
     (Port    : GNAT.Sockets.Port_Type;
      Timeout : Duration) return Probe_Result
   is
      T      : C.Tcp_Transport;
      Ok     : Boolean;
      Proj   : Differential.Scenario.Projection;
      A1, A2 : Differential.Scenario.Action;
      Output : C.Run_Output;
      Res    : Probe_Result;

      procedure Add (A : in out Differential.Scenario.Action;
                     B : Adacraft.Protocol.Octets) is
      begin
         for X of B loop
            A.Frame.Append (X);
         end loop;
      end Add;
   begin
      C.Connect (T, Port, Ok);
      if not Ok then
         return Res;
      end if;
      Proj.Id := SU.To_Unbounded_String ("oracle-ready");
      A1.Index := 1;
      A1.Timeout := Timeout;
      Add (A1, (16#10#, 16#00#, 16#89#, 16#06#, 16#09#,
                Character'Pos ('l'), Character'Pos ('o'),
                Character'Pos ('c'), Character'Pos ('a'),
                Character'Pos ('l'), Character'Pos ('h'),
                Character'Pos ('o'), Character'Pos ('s'),
                Character'Pos ('t'), 16#63#, 16#DD#, 16#01#));
      A2.Index := 2;
      A2.Timeout := Timeout;
      Add (A2, (16#01#, 16#00#));
      Proj.Actions.Append (A1);
      Proj.Actions.Append (A2);
      C.Execute (T, Proj, Output);
      C.Disconnect (T);
      declare
         Obs : constant Differential.Obs.Observation :=
           Differential.Extract.Extract (Output, "oracle-ready");
      begin
         for S of Obs.Steps loop
            if S.Fields.Contains (Differential.Obs.F_Status_Version_Protocol)
            then
               Res.Ready := True;
               begin
                  Res.Protocol := Natural'Value
                    (S.Fields.Element
                       (Differential.Obs.F_Status_Version_Protocol));
               exception
                  when Constraint_Error => Res.Protocol := 0;
               end;
            end if;
         end loop;
      end;
      return Res;
   exception
      when others =>
         C.Disconnect (T);
         return (others => <>);
   end Status_Probe;

   ---------------------------------------------------------------- helpers

   function Free_Port return GNAT.Sockets.Port_Type is
      use GNAT.Sockets;
      S    : Socket_Type;
      Addr : Sock_Addr_Type :=
        (Family => Family_Inet, Addr => Loopback_Inet_Addr,
         Port   => Any_Port);
      P    : Port_Type;
   begin
      Create_Socket (S);
      Bind_Socket (S, Addr);
      Addr := Get_Socket_Name (S);
      P := Addr.Port;
      Close_Socket (S);
      return P;
   end Free_Port;

   --  Returns the Java major from `java -version` output, 0 if unknown.
   function Java_Major (Java, Dir : String) return Natural is
      Log  : constant String :=
        Ada.Directories.Compose (Dir, "java-version.txt");
      Args : OS.Argument_List := (1 => new String'("-version"));
      Ok   : Boolean;
      Code : Integer;
      F    : Ada.Text_IO.File_Type;
      Major : Natural := 0;
   begin
      OS.Spawn (Java, Args, Log, Ok, Code, True);
      OS.Free (Args);
      if not Ok then
         return 0;
      end if;
      Ada.Text_IO.Open (F, Ada.Text_IO.In_File, Log);
      while not Ada.Text_IO.End_Of_File (F) loop
         declare
            L : constant String := Ada.Text_IO.Get_Line (F);
            I : constant Natural := Ada.Strings.Fixed.Index (L, "version """);
         begin
            if I > 0 then
               declare
                  J : Natural := I + 9;
               begin
                  while J <= L'Last and then L (J) in '0' .. '9' loop
                     Major := Major * 10
                       + (Character'Pos (L (J)) - Character'Pos ('0'));
                     J := J + 1;
                  end loop;
               end;
               exit;
            end if;
         end;
      end loop;
      Ada.Text_IO.Close (F);
      return Major;
   exception
      when others =>
         return 0;
   end Java_Major;

   function Resolve_Java (Name : String) return String is
   begin
      if OS.Is_Executable_File (Name) then
         return Name;
      end if;
      declare
         P : OS.String_Access := OS.Locate_Exec_On_Path (Name);
      begin
         if P = null then
            return "";
         end if;
         return R : constant String := P.all do
            OS.Free (P);
         end return;
      end;
   end Resolve_Java;

   function Run_Inner
     (Cfg      : Config;
      Scenario : Differential.Scenario.Projection;
      Timeout  : Duration;
      Dir      : String;
      Port     : GNAT.Sockets.Port_Type) return Run_Result
   is
      pragma Unreferenced (Timeout);
      Owner : Process_Owner;
      Java  : constant String :=
        Resolve_Java (SU.To_String (Cfg.Java_Path));
      Jar   : constant String :=
        (if Ada.Directories.Exists (SU.To_String (Cfg.Jar_Path))
         then Ada.Directories.Full_Name (SU.To_String (Cfg.Jar_Path))
         else "");
      Probe : constant Probe_Func :=
        (if Cfg.Probe = null then Status_Probe'Access else Cfg.Probe);
      Deadline : constant Ada.Calendar.Time :=
        Ada.Calendar.Clock + Cfg.Ready_Timeout;
      Ok    : Boolean;
      Pr    : Probe_Result;
   begin
      if Java = "" then
         return Infra ("java executable not found");
      end if;
      if Jar = "" then
         return Infra ("server jar not found");
      end if;
      declare
         Major : constant Natural := Java_Major (Java, Dir);
      begin
         if Major /= Required_Java_Major then
            return Infra ("wrong Java major" & Natural'Image (Major)
                          & " (need" & Integer'Image (Required_Java_Major)
                          & ")");
         end if;
      end;
      Start (Owner, Java, Jar, Dir,
             Ada.Directories.Compose (Dir, "server.log"), Ok);
      if not Ok then
         return Infra ("could not start server process");
      end if;

      loop
         Pr := Probe.all (Port, 2.0);
         exit when Pr.Ready;
         if Ada.Calendar.Clock > Deadline then
            return Infra ("readiness timeout");
         end if;
         delay 0.25;
      end loop;
      if Pr.Protocol /= Required_Protocol then
         return Infra ("wrong oracle protocol" & Natural'Image (Pr.Protocol));
      end if;

      declare
         T      : C.Tcp_Transport;
         Output : C.Run_Output;
         Res    : Run_Result;
      begin
         C.Connect (T, Port, Ok);
         if not Ok then
            Res.Category := Failed;
            Res.Detail := SU.To_Unbounded_String ("connect failed");
            return Res;
         end if;
         C.Execute (T, Scenario, Output);
         C.Disconnect (T);
         Res.Observation := Differential.Extract.Extract
           (Output, SU.To_String (Scenario.Id));
         if Output.Failed then
            Res.Category := Failed;
            Res.Detail := Output.Detail;
         else
            Res.Category := Completed;
         end if;
         return Res;
      end;
   end Run_Inner;

   overriding function Run_Scenario
     (T        : in out Oracle_Target;
      Scenario : Differential.Scenario.Projection;
      Timeout  : Duration) return Run_Result
   is
      Root : constant String :=
        (if SU.Length (T.Cfg.Work_Root) > 0
         then SU.To_String (T.Cfg.Work_Root)
         elsif Ada.Environment_Variables.Exists ("TMPDIR")
         then Ada.Environment_Variables.Value ("TMPDIR")
         else "/tmp");
      Result  : Run_Result;
      Port    : GNAT.Sockets.Port_Type := 0;
      Dir     : SU.Unbounded_String;
      Created : Boolean := False;
   begin
      begin
         Port := Free_Port;
         Dir := SU.To_Unbounded_String
           (Ada.Directories.Compose
              (Root, "adacraft-oracle-" & Img (Integer (Port))));
         Ada.Directories.Create_Path (SU.To_String (Dir));
         Created := True;
         Write_Server_Files (SU.To_String (Dir), Port);
         Result := Run_Inner (T.Cfg, Scenario, Timeout,
                              SU.To_String (Dir), Port);
      exception
         when others =>
            Result := Infra ("oracle run raised an exception");
      end;
      if Created then
         begin
            Ada.Directories.Delete_Tree (SU.To_String (Dir));
         exception
            when others => null;
         end;
      end if;
      return Result;
   end Run_Scenario;

end Differential.Target.Oracle;
