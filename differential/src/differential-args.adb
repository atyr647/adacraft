with Ada.Command_Line;
with Ada.Text_IO;

package body Differential.Args is

   function Host_Image (E : Endpoint) return String is
   begin
      if E.Host_Len = 0 then
         return "";
      end if;
      return E.Host (1 .. E.Host_Len);
   end Host_Image;

   procedure Print_Usage is
      use Ada.Text_IO;
   begin
      Put_Line (Standard_Error,
        "Usage: differential-main --oracle <host>:<port>" &
        " --candidate <host>:<port>");
      Put_Line (Standard_Error,
        "   or: differential-main --selftest");
   end Print_Usage;

   procedure Parse_Host_Port (Text : String; E : out Endpoint) is
      Colon : Natural := 0;
   begin
      E.Host := (others => ' ');
      E.Host_Len := 0;
      E.Port := 0;
      for I in Text'Range loop
         if Text (I) = ':' then
            Colon := I;
         end if;
      end loop;
      if Colon = 0 then
         raise Usage_Error;
      end if;
      declare
         H_First : constant Positive := Text'First;
         H_Last  : constant Natural := Colon - 1;
         P_First : constant Positive := Colon + 1;
         P_Last  : constant Natural := Text'Last;
         H_Len   : constant Natural :=
           (if H_Last >= H_First then H_Last - H_First + 1 else 0);
         P_Len   : constant Natural :=
           (if P_Last >= P_First then P_Last - P_First + 1 else 0);
         Value   : Natural := 0;
      begin
         if H_Len = 0 or else H_Len > 256 then
            raise Usage_Error;
         end if;
         if P_Len = 0 or else P_Len > 5 then
            raise Usage_Error;
         end if;
         for I in H_First .. H_Last loop
            if Text (I) = ' ' or else Text (I) = ASCII.HT then
               raise Usage_Error;
            end if;
         end loop;
         for I in P_First .. P_Last loop
            if Text (I) not in '0' .. '9' then
               raise Usage_Error;
            end if;
            Value := Value * 10 + (Character'Pos (Text (I)) - Character'Pos ('0'));
            if Value > 65_535 then
               raise Usage_Error;
            end if;
         end loop;
         if Value < 1 or else Value > 65_535 then
            raise Usage_Error;
         end if;
         E.Host (1 .. H_Len) := Text (H_First .. H_Last);
         E.Host_Len := H_Len;
         E.Port := Value;
      end;
   end Parse_Host_Port;

   procedure Parse_Argv
     (Count : Natural;
      Get   : access function (Index : Positive) return String;
      Opts  : out Options)
   is
      I : Positive := 1;
   begin
      Opts := (others => <>);
      if Count = 0 then
         raise Usage_Error;
      end if;
      while I <= Count loop
         declare
            A : constant String := Get (I);
         begin
            if A = "--selftest" then
               if Count /= 1 then
                  raise Usage_Error;
               end if;
               Opts.Selftest := True;
               return;
            elsif A = "--oracle" then
               if Opts.Has_Oracle then
                  raise Usage_Error;
               end if;
               if I + 1 > Count then
                  raise Usage_Error;
               end if;
               I := I + 1;
               Parse_Host_Port (Get (I), Opts.Oracle);
               Opts.Has_Oracle := True;
            elsif A = "--candidate" then
               if Opts.Has_Candidate then
                  raise Usage_Error;
               end if;
               if I + 1 > Count then
                  raise Usage_Error;
               end if;
               I := I + 1;
               Parse_Host_Port (Get (I), Opts.Candidate);
               Opts.Has_Candidate := True;
            else
               raise Usage_Error;
            end if;
         end;
         I := I + 1;
      end loop;
      if Opts.Selftest then
         return;
      end if;
      if not Opts.Has_Oracle or else not Opts.Has_Candidate then
         raise Usage_Error;
      end if;
   end Parse_Argv;

   procedure Parse_Command_Line (Opts : out Options) is
      use Ada.Command_Line;
      Count : constant Natural := Argument_Count;
      function Get (Index : Positive) return String is
      begin
         return Argument (Index);
      end Get;
   begin
      Parse_Argv (Count, Get'Access, Opts);
   end Parse_Command_Line;

end Differential.Args;
