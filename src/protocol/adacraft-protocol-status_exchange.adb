with Adacraft.Protocol.Buffer;
with Adacraft.Protocol.Packets;

package body Adacraft.Protocol.Status_Exchange is

   function Trim_Image (V : Integer) return String is
      Img : constant String := Integer'Image (V);
   begin
      if Img'Length > 0 and then Img (Img'First) = ' ' then
         return Img (Img'First + 1 .. Img'Last);
      else
         return Img;
      end if;
   end Trim_Image;

   function Trim_Natural (V : Natural) return String is
   begin
      return Trim_Image (Integer (V));
   end Trim_Natural;

   function Hex_Digit (V : Natural) return Character is
   begin
      if V < 10 then
         return Character'Val (Character'Pos ('0') + V);
      else
         return Character'Val (Character'Pos ('A') + V - 10);
      end if;
   end Hex_Digit;

   function Escape_MOTD (MOTD : String) return String is
      Result : String (1 .. MOTD'Length * 6 + 1);
      Len    : Natural := 0;
   begin
      for Ch of MOTD loop
         case Character'Pos (Ch) is
            when 34 =>
               Len := Len + 1;
               Result (Len) := '\';
               Len := Len + 1;
               Result (Len) := '"';
            when 92 =>
               Len := Len + 1;
               Result (Len) := '\';
               Len := Len + 1;
               Result (Len) := '\';
            when 10 =>
               Len := Len + 1;
               Result (Len) := '\';
               Len := Len + 1;
               Result (Len) := 'n';
            when 13 =>
               Len := Len + 1;
               Result (Len) := '\';
               Len := Len + 1;
               Result (Len) := 'r';
            when 9 =>
               Len := Len + 1;
               Result (Len) := '\';
               Len := Len + 1;
               Result (Len) := 't';
            when 8 =>
               Len := Len + 1;
               Result (Len) := '\';
               Len := Len + 1;
               Result (Len) := 'b';
            when 12 =>
               Len := Len + 1;
               Result (Len) := '\';
               Len := Len + 1;
               Result (Len) := 'f';
            when others =>
               if Character'Pos (Ch) < 32 then
                  Len := Len + 1;
                  Result (Len) := '\';
                  Len := Len + 1;
                  Result (Len) := 'u';
                  Len := Len + 1;
                  Result (Len) := '0';
                  Len := Len + 1;
                  Result (Len) := '0';
                  Len := Len + 1;
                  Result (Len) := Hex_Digit (Character'Pos (Ch) / 16);
                  Len := Len + 1;
                  Result (Len) := Hex_Digit (Character'Pos (Ch) mod 16);
               else
                  Len := Len + 1;
                  Result (Len) := Ch;
               end if;
         end case;
      end loop;
      if Len = 0 then
         return "";
      end if;
      return Result (1 .. Len);
   end Escape_MOTD;

   function Build_JSON (Config : Status_Config) return String is
      use Ada.Strings.Unbounded;
      VN : constant String := To_String (Config.Version_Name);
      Esc : constant String := Escape_MOTD (To_String (Config.MOTD));
   begin
      return "{""version"":{""name"":""" & VN & """,""protocol"":"
        & Trim_Image (Config.Version_Protocol)
        & "},""players"":{""max"":" & Trim_Natural (Config.Max_Players)
        & ",""online"":" & Trim_Natural (Config.Online_Players)
        & "},""description"":{""text"":""" & Esc & """}}";
   end Build_JSON;

   function Default_Config return Status_Config is
   begin
      return (others => <>);
   end Default_Config;

   function Build_Config
     (Version_Name     : String;
      Version_Protocol : Integer;
      Max_Players      : Natural;
      Online_Players   : Natural;
      MOTD             : String) return Config_Build_Result
   is
      use Ada.Strings.Unbounded;
      C : Status_Config;
      J : Unbounded_String;
   begin
      C.Version_Name := To_Unbounded_String (Version_Name);
      C.Version_Protocol := Version_Protocol;
      C.Max_Players := Max_Players;
      C.Online_Players := Online_Players;
      C.MOTD := To_Unbounded_String (MOTD);
      J := To_Unbounded_String (Build_JSON (C));
      if Length (J) > Max_JSON_Chars then
         return (Valid => False, Config => C);
      end if;
      return (Valid => True, Config => C);
   end Build_Config;

   function Rejected_Close
     (Reason : State.Rejection_Reason) return Outcome
   is
   begin
      return
        (Accepted        => False,
         Has_Reply       => False,
         Reply_Length    => 0,
         Reply_Data      => [others => 0],
         Close_Requested => True,
         Reason          => Reason);
   end Rejected_Close;

   procedure Handle
     (Current_State : State.Connection_State;
      Packet_Id     : Integer;
      Payload       : Octets;
      Config        : Status_Config;
      Status_Sent   : in out Boolean;
      Result        : out Outcome)
   is
      use type State.Connection_State;
   begin
      if Current_State /= State.Status then
         Result := Rejected_Close (State.Packet_Not_Valid_In_State);
         return;
      end if;

      if Packet_Id = 0 then
         if Payload'Length /= 0 then
            Result := Rejected_Close (State.Packet_Not_Valid_In_State);
            return;
         end if;
         if Status_Sent then
            Result := Rejected_Close (State.Packet_Not_Valid_In_State);
            return;
         end if;
         declare
            JSON : constant String := Build_JSON (Config);
            W : Buffer.Writer (Capacity => Max_Reply_Bytes);
         begin
            if JSON'Length > Max_JSON_Chars then
               Result := Rejected_Close (State.Packet_Not_Valid_In_State);
               return;
            end if;
            Buffer.Reset (W);
            Buffer.Put_Varint (W, 0);
            Buffer.Put_String (W, JSON);
            if W.Failed or else W.Len = 0 then
               Result := Rejected_Close (State.Packet_Not_Valid_In_State);
               return;
            end if;
            Result.Accepted := True;
            Result.Has_Reply := True;
            Result.Reply_Length := W.Len;
            Result.Reply_Data := [others => 0];
            for I in 1 .. W.Len loop
               Result.Reply_Data (I) := W.Data (I);
            end loop;
            Result.Close_Requested := False;
            Result.Reason := State.No_Rejection;
            Status_Sent := True;
            return;
         end;
      elsif Packet_Id = 1 then
         declare
            Dec : constant Packets.Ping := Packets.Decode_Ping (Payload);
            W : Buffer.Writer (Capacity => Max_Reply_Bytes);
         begin
            if Dec.Status /= Ok then
               Result := Rejected_Close (State.Packet_Not_Valid_In_State);
               return;
            end if;
            Buffer.Reset (W);
            Buffer.Put_Varint (W, 1);
            Buffer.Put_U64 (W, Dec.Value);
            if W.Failed or else W.Len = 0 then
               Result := Rejected_Close (State.Packet_Not_Valid_In_State);
               return;
            end if;
            Result.Accepted := True;
            Result.Has_Reply := True;
            Result.Reply_Length := W.Len;
            Result.Reply_Data := [others => 0];
            for I in 1 .. W.Len loop
               Result.Reply_Data (I) := W.Data (I);
            end loop;
            Result.Close_Requested := True;
            Result.Reason := State.No_Rejection;
            return;
         end;
      else
         Result := Rejected_Close (State.Packet_Not_Valid_In_State);
         return;
      end if;
   end Handle;

end Adacraft.Protocol.Status_Exchange;
