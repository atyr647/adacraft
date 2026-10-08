with Ada.Command_Line;
with Ada.Text_IO;

package body Differential.Args is

   function Find_Colon (S : String) return Natural is
   begin
      for I in S'Range loop
         if S (I) = ':' then
            return I;
         end if;
      end loop;
      return 0;
   end Find_Colon;

   function Parse_Endpoint_Value
     (Value : String;
      EP    : out Endpoint) return String
   is
      Colon : constant Natural := Find_Colon (Value);
   begin
      EP := (Host => Host_Strings.Null_Bounded_String,
             Port => 25565,
             Set  => False);
      if Value'Length = 0 then
         return "empty endpoint value";
      end if;
      if Colon = 0 then
         return "endpoint must be HOST:PORT";
      end if;
      if Colon = Value'First then
         return "endpoint host is empty";
      end if;
      if Colon = Value'Last then
         return "endpoint port is empty";
      end if;
      declare
         Host_Part : constant String :=
           Value (Value'First .. Colon - 1);
         Port_Part : constant String :=
           Value (Colon + 1 .. Value'Last);
         Port_Val  : Natural := 0;
      begin
         if Host_Part'Length > 255 then
            return "endpoint host too long";
         end if;
         for C of Port_Part loop
            if C not in '0' .. '9' then
               return "endpoint port is not numeric";
            end if;
            Port_Val := Port_Val * 10 + (Character'Pos (C) - Character'Pos ('0'));
            if Port_Val > 65_535 then
               return "endpoint port out of range 1..65535";
            end if;
         end loop;
         if Port_Val < 1 or else Port_Val > 65_535 then
            return "endpoint port out of range 1..65535";
         end if;
         EP.Host := Host_Strings.To_Bounded_String (Host_Part);
         EP.Port := Port_Val;
         EP.Set := True;
         return "";
      end;
   end Parse_Endpoint_Value;

   function Fail (Msg : String) return Config is
   begin
      return (Mode      => Run,
              Oracle    => (Host => Host_Strings.Null_Bounded_String,
                            Port => 25565,
                            Set  => False),
              Candidate => (Host => Host_Strings.Null_Bounded_String,
                            Port => 25565,
                            Set  => False),
              Valid     => False,
              Error_Msg => Msg_Strings.To_Bounded_String (Msg));
   end Fail;

   function Parse return Config is
      use Ada.Command_Line;
      Count : constant Natural := Natural (Argument_Count);
   begin
      if Count = 1 and then Argument (1) = "--selftest" then
         return (Mode      => Selftest,
                 Oracle    => (Host => Host_Strings.Null_Bounded_String,
                               Port => 25565,
                               Set  => False),
                 Candidate => (Host => Host_Strings.Null_Bounded_String,
                               Port => 25565,
                               Set  => False),
                 Valid     => True,
                 Error_Msg => Msg_Strings.Null_Bounded_String);
      end if;

      if Count = 0 then
         return Fail ("missing arguments");
      end if;

      --  --selftest must appear alone.
      for I in 1 .. Count loop
         if Argument (I) = "--selftest" then
            return Fail ("--selftest takes no other arguments");
         end if;
      end loop;

      if Count /= 4 then
         return Fail ("expected --oracle HOST:PORT --candidate HOST:PORT");
      end if;

      declare
         Oracle_Seen    : Boolean := False;
         Candidate_Seen : Boolean := False;
         Oracle_EP      : Endpoint;
         Candidate_EP   : Endpoint;
         I              : Positive := 1;
      begin
         while I <= Count loop
            declare
               Opt : constant String := Argument (I);
            begin
               if Opt = "--oracle" then
                  if Oracle_Seen then
                     return Fail ("duplicate --oracle");
                  end if;
                  if I + 1 > Count then
                     return Fail ("missing value for --oracle");
                  end if;
                  declare
                     Err : constant String :=
                       Parse_Endpoint_Value (Argument (I + 1), Oracle_EP);
                  begin
                     if Err /= "" then
                        return Fail ("bad --oracle value: " & Err);
                     end if;
                  end;
                  Oracle_Seen := True;
                  I := I + 2;
               elsif Opt = "--candidate" then
                  if Candidate_Seen then
                     return Fail ("duplicate --candidate");
                  end if;
                  if I + 1 > Count then
                     return Fail ("missing value for --candidate");
                  end if;
                  declare
                     Err : constant String :=
                       Parse_Endpoint_Value (Argument (I + 1), Candidate_EP);
                  begin
                     if Err /= "" then
                        return Fail ("bad --candidate value: " & Err);
                     end if;
                  end;
                  Candidate_Seen := True;
                  I := I + 2;
               else
                  return Fail ("unknown option: " & Opt);
               end if;
            end;
         end loop;

         if not Oracle_Seen or else not Candidate_Seen then
            return Fail ("both --oracle and --candidate are required");
         end if;

         return (Mode      => Run,
                 Oracle    => Oracle_EP,
                 Candidate => Candidate_EP,
                 Valid     => True,
                 Error_Msg => Msg_Strings.Null_Bounded_String);
      end;
   end Parse;

   procedure Print_Usage is
      use Ada.Text_IO;
   begin
      Put_Line (Standard_Error,
                "Usage: differential-main --oracle HOST:PORT" &
                " --candidate HOST:PORT");
      Put_Line (Standard_Error,
                "   or: differential-main --selftest");
   end Print_Usage;

end Differential.Args;
