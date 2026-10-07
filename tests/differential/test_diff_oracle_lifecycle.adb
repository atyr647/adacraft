with Ada.Directories;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;
with Ada.Text_IO;
with GNAT.OS_Lib;
with GNAT.Sockets;
with Differential.Scenario;
with Differential.Target.Oracle;

--  DR-4 offline: a stub "java" shell script stands in for the JVM. Covers
--  ready-timeout, protocol mismatch, wrong Java, exception and error paths,
--  and that the subprocess is dead after each.
procedure Test_Diff_Oracle_Lifecycle is
   package O renames Differential.Target.Oracle;
   package T renames Differential.Target;
   package SU renames Ada.Strings.Unbounded;
   use type T.Run_Category;

   Failures : Natural := 0;
   Root : constant String :=
     Ada.Directories.Compose
       (Ada.Directories.Current_Directory, "obj/oracle-test");
   Counter : Natural := 0;

   procedure Check (Cond : Boolean; Name : String) is
   begin
      if not Cond then
         Ada.Text_IO.Put_Line ("FAIL " & Name);
         Failures := Failures + 1;
      end if;
   end Check;

   procedure Put_File (Path, Text : String) is
      F : Ada.Text_IO.File_Type;
   begin
      Ada.Text_IO.Create (F, Ada.Text_IO.Out_File, Path);
      Ada.Text_IO.Put (F, Text);
      Ada.Text_IO.Close (F);
   end Put_File;

   function Script (Ver, Pid_File : String) return String is
     ("#!/bin/sh" & ASCII.LF
      & "if [ ""$1"" = ""-version"" ]; then echo 'openjdk version """""
      & Ver & """"' >&2; exit 0; fi" & ASCII.LF
      & "echo $$ > " & Pid_File & ASCII.LF
      & "exec sleep 30" & ASCII.LF);

   function Read_Pid (Pid_File : String) return String is
      F : Ada.Text_IO.File_Type;
   begin
      Ada.Text_IO.Open (F, Ada.Text_IO.In_File, Pid_File);
      declare
         L : constant String := Ada.Text_IO.Get_Line (F);
      begin
         Ada.Text_IO.Close (F);
         return Ada.Strings.Fixed.Trim (L, Ada.Strings.Both);
      end;
   exception
      when others => return "";
   end Read_Pid;

   function Alive (Pid : String) return Boolean is
      Args : GNAT.OS_Lib.Argument_List :=
        (new String'("-0"), new String'(Pid));
      Ok   : Boolean;
   begin
      GNAT.OS_Lib.Spawn ("/bin/kill", Args, Ok);
      return Ok;
   end Alive;

   function P_Never
     (Port : GNAT.Sockets.Port_Type; Timeout : Duration)
      return O.Probe_Result is
      pragma Unreferenced (Port, Timeout);
   begin
      delay 0.1;
      return (others => <>);
   end P_Never;

   function P_Wrong
     (Port : GNAT.Sockets.Port_Type; Timeout : Duration)
      return O.Probe_Result is
      pragma Unreferenced (Port, Timeout);
   begin
      delay 0.6;
      return (Ready => True, Protocol => 123, Detail => <>);
   end P_Wrong;

   function P_Ok
     (Port : GNAT.Sockets.Port_Type; Timeout : Duration)
      return O.Probe_Result is
      pragma Unreferenced (Port, Timeout);
   begin
      delay 0.6;
      return (Ready => True, Protocol => 777, Detail => <>);
   end P_Ok;

   function P_Raise
     (Port : GNAT.Sockets.Port_Type; Timeout : Duration)
      return O.Probe_Result is
      pragma Unreferenced (Port, Timeout);
   begin
      delay 0.6;
      raise Program_Error;
      return (others => <>);
   end P_Raise;

   procedure Run_Case
     (Name       : String;
      Java_Ver   : String;
      Probe      : O.Probe_Func;
      Expect     : T.Run_Category;
      Detail_Has : String;
      Expect_Pid : Boolean)
   is
      N        : constant String :=
        Ada.Strings.Fixed.Trim (Natural'Image (Counter), Ada.Strings.Left);
      Pid_File : constant String := Root & "/pid-" & N;
      Java     : constant String := Root & "/java-" & N;
      Jar      : constant String := Root & "/server-" & N & ".jar";
      Tgt      : O.Oracle_Target;
      Proj     : Differential.Scenario.Projection;
      R        : T.Run_Result;
   begin
      Counter := Counter + 1;
      Put_File (Java, Script (Java_Ver, Pid_File));
      GNAT.OS_Lib.Set_Executable (Java);
      Put_File (Jar, "stub");
      Tgt.Cfg.Java_Path := SU.To_Unbounded_String (Java);
      Tgt.Cfg.Jar_Path := SU.To_Unbounded_String (Jar);
      Tgt.Cfg.Work_Root := SU.To_Unbounded_String (Root);
      Tgt.Cfg.Ready_Timeout := 1.0;
      Tgt.Cfg.Probe := Probe;
      R := Tgt.Run_Scenario (Proj, 1.0);
      Check (R.Category = Expect, Name & ": category");
      Check (Ada.Strings.Fixed.Index (SU.To_String (R.Detail), Detail_Has) > 0
             or else Detail_Has = "", Name & ": detail");
      declare
         Pid : constant String := Read_Pid (Pid_File);
      begin
         if Expect_Pid then
            Check (Pid /= "", Name & ": process was started");
         else
            Check (Pid = "", Name & ": no process started");
         end if;
         if Pid /= "" then
            Check (not Alive (Pid), Name & ": process torn down");
         end if;
      end;
   end Run_Case;

begin
   Ada.Directories.Create_Path (Root);

   Run_Case ("ready-timeout", "25.0.1", P_Never'Unrestricted_Access,
             T.Infrastructure, "readiness", True);
   Run_Case ("protocol-mismatch", "25.0.1", P_Wrong'Unrestricted_Access,
             T.Infrastructure, "protocol", True);
   Run_Case ("wrong-java", "17.0.2", P_Ok'Unrestricted_Access,
             T.Infrastructure, "Java", False);
   Run_Case ("probe-exception", "25.0.1", P_Raise'Unrestricted_Access,
             T.Infrastructure, "", True);
   Run_Case ("error-after-ready", "25.0.1", P_Ok'Unrestricted_Access,
             T.Failed, "", True);

   --  Owner teardown on normal scope exit.
   declare
      Pid_File : constant String := Root & "/pid-owner";
      Java     : constant String := Root & "/java-owner";
      Ok       : Boolean;
   begin
      Put_File (Java, Script ("25.0.1", Pid_File));
      GNAT.OS_Lib.Set_Executable (Java);
      declare
         Owner : O.Process_Owner;
      begin
         O.Start (Owner, Java, "x.jar", Root, Root & "/owner.log", Ok);
         Check (Ok, "owner starts");
         delay 0.6;
         Check (O.Is_Running (Owner), "owner running");
      end;
      declare
         Pid : constant String := Read_Pid (Pid_File);
      begin
         Check (Pid /= "", "owner pid recorded");
         if Pid /= "" then
            Check (not Alive (Pid), "owner finalize kills process");
         end if;
      end;
   end;

   --  Generated files: one writer, expected keys present.
   declare
      P : constant String := O.Properties (25565);
   begin
      Check (Ada.Strings.Fixed.Index (P, "online-mode=false") > 0,
             "online-mode");
      Check (Ada.Strings.Fixed.Index (P, "server-ip=127.0.0.1") > 0,
             "server-ip");
      Check (Ada.Strings.Fixed.Index
               (P, "network-compression-threshold=-1") > 0, "compression");
   end;

   begin
      Ada.Directories.Delete_Tree (Root);
   exception
      when others => null;
   end;

   if Failures > 0 then
      Ada.Text_IO.Put_Line ("test_diff_oracle_lifecycle: FAILED");
      raise Program_Error;
   end if;
   Ada.Text_IO.Put_Line ("test_diff_oracle_lifecycle: ok");
end Test_Diff_Oracle_Lifecycle;
