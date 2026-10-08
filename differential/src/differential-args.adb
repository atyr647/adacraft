with Ada.Command_Line;
with Ada.Strings.Unbounded;
with Ada.Text_IO;

package body Differential.Args is

   use Ada.Strings.Unbounded;

   procedure Parse_Endpoint
     (Image : in String;
      Ep    : out Endpoint)
   is
      Sep : Natural := 0;
   begin
      Ep := (Host => Null_Unbounded_String, Port => 0);
      for I in Image'Range loop
         if Image (I) = ':' then
            Sep := I;
         end if;
      end loop;
      if Sep = 0 then
         raise Usage_Error;
      end if;
      declare
         H : constant String := Image (Image'First .. Sep - 1);
         P : constant String := Image (Sep + 1 .. Image'Last);
         N : Natural := 0;
      begin
         if H'Length = 0 or else P'Length = 0 then
            raise Usage_Error;
         end if;
         for C of P loop
            if C not in '0' .. '9' then
               raise Usage_Error;
            end if;
            N := N * 10 + (Character'Pos (C) - Character'Pos ('0'));
            if N > 65_535 then
               raise Usage_Error;
            end if;
         end loop;
         if N < 1 or else N > 65_535 then
            raise Usage_Error;
         end if;
         Ep.Host := To_Unbounded_String (H);
         Ep.Port := N;
      end;
   end Parse_Endpoint;

   procedure Parse_Args (Args : in Arg_Array; Opts : out Options) is
      Saw_Selftest : Boolean := False;
      I : Natural := Args'First - 1;
      N : constant Natural := Args'Last;
   begin
      Opts := (others => <>);
      Opts.Mode := Run;
      if Args'Length = 0 then
         raise Usage_Error;
      end if;
      I := Args'First;
      while I <= N loop
         declare
            A : constant String := To_String (Args (I));
         begin
            if A = "--selftest" then
               if Saw_Selftest then
                  raise Usage_Error;
               end if;
               Saw_Selftest := True;
               I := I + 1;
            elsif A = "--oracle" or else A = "--candidate" then
               declare
                  Is_Oracle : constant Boolean := (A = "--oracle");
                  Val : Unbounded_String;
                  Ep  : Endpoint;
               begin
                  if I + 1 > N then
                     raise Usage_Error;
                  end if;
                  Val := Args (I + 1);
                  if Length (Val) = 0
                    or else To_String (Val) (To_String (Val)'First) = '-'
                  then
                     raise Usage_Error;
                  end if;
                  Parse_Endpoint (To_String (Val), Ep);
                  if Is_Oracle then
                     if Opts.Has_Oracle then
                        raise Usage_Error;
                     end if;
                     Opts.Oracle := Ep;
                     Opts.Has_Oracle := True;
                  else
                     if Opts.Has_Candidate then
                        raise Usage_Error;
                     end if;
                     Opts.Candidate := Ep;
                     Opts.Has_Candidate := True;
                  end if;
                  I := I + 2;
               end;
            elsif A'Length > 9
              and then A (A'First .. A'First + 8) = "--oracle="
            then
               declare
                  Ep : Endpoint;
               begin
                  if Opts.Has_Oracle then
                     raise Usage_Error;
                  end if;
                  Parse_Endpoint
                    (A (A'First + 9 .. A'Last), Ep);
                  Opts.Oracle := Ep;
                  Opts.Has_Oracle := True;
                  I := I + 1;
               end;
            elsif A'Length > 12
              and then A (A'First .. A'First + 11) = "--candidate="
            then
               declare
                  Ep : Endpoint;
               begin
                  if Opts.Has_Candidate then
                     raise Usage_Error;
                  end if;
                  Parse_Endpoint
                    (A (A'First + 12 .. A'Last), Ep);
                  Opts.Candidate := Ep;
                  Opts.Has_Candidate := True;
                  I := I + 1;
               end;
            else
               raise Usage_Error;
            end if;
         end;
      end loop;

      if Saw_Selftest then
         if Opts.Has_Oracle or else Opts.Has_Candidate then
            raise Usage_Error;
         end if;
         Opts.Mode := Selftest;
      else
         Opts.Mode := Run;
         if not (Opts.Has_Oracle and then Opts.Has_Candidate) then
            raise Usage_Error;
         end if;
      end if;
   end Parse_Args;

   function Parse return Options is
      use Ada.Command_Line;
      Count : constant Natural := Argument_Count;
      Opts  : Options;
   begin
      if Count = 0 or else Count > Max_Args then
         raise Usage_Error;
      end if;
      declare
         Args : Arg_Array (1 .. Count);
      begin
         for I in 1 .. Count loop
            Args (I) := To_Unbounded_String (Argument (I));
         end loop;
         Parse_Args (Args, Opts);
         return Opts;
      end;
   end Parse;

   procedure Usage is
      use Ada.Text_IO;
   begin
      Put_Line (Standard_Error,
        "Usage: differential-main --selftest");
      Put_Line (Standard_Error,
        "   or: differential-main " &
        "--oracle <host:port> --candidate <host:port>");
   end Usage;

end Differential.Args;
