with Ada.Strings.Fixed;
with Adacraft.Protocol.Buffer;
with Adacraft.Protocol.Packets;
with Adacraft.Protocol.State;
with Adacraft.Protocol.Varnum;

package body Adacraft.Protocol.Status_Exchange with SPARK_Mode => Off is
   use Adacraft.Protocol;
   use type State.Connection_State;

   --  Single status JSON builder. Version fields are pinned to the single
   --  version package Adacraft.Protocol.State (Protocol_Number = 777,
   --  Minecraft_Version = "26.3"). Dropped fields vs. vanilla samples:
   --  favicon, enforcesSecureChat and previews are omitted; players
   --  reports max 20 / online 0 and description is {"text":"AdaCraft"}.
   function Build_Response return String is
      Num_Image : constant String :=
        Ada.Strings.Fixed.Trim
          (State.Protocol_Number'Image, Ada.Strings.Left);
   begin
      return "{""version"":{""name"":""" & State.Minecraft_Version
        & """,""protocol"":" & Num_Image & "},"
        & """players"":{""max"":20,""online"":0},"
        & """description"":{""text"":""AdaCraft""}}";
   end Build_Response;

   procedure Reset (S : in out Session) is
   begin
      S.Request_Seen := False;
   end Reset;

   procedure Handle
     (Packet_Id        : in     Natural;
      Payload          : in     Octets;
      Current          : in out State.Connection_State;
      Session_State    : in out Session;
      Result           :    out Handle_Result;
      Response_Id      :    out Natural;
      Response_Data    :    out Octets;
      Response_Len     :    out Natural;
      Close_Connection :    out Boolean)
   is
   begin
      Response_Id := 0;
      Response_Len := 0;
      if Response_Data'Length > 0 then
         for I in Response_Data'Range loop
            Response_Data (I) := 0;
         end loop;
      end if;

      if Current /= State.Status then
         Result := Rejected_Close;
         Close_Connection := True;
         return;
      end if;

      if Packet_Id = 16#00# then
         if Payload'Length /= 0 or else Session_State.Request_Seen then
            Result := Rejected_Close;
            Close_Connection := True;
            return;
         end if;
         declare
            JSON : constant String := Build_Response;
            W : Buffer.Writer (33_000);
         begin
            if JSON'Length > 32_767 then
               Result := Rejected_Close;
               Close_Connection := True;
               return;
            end if;
            Buffer.Put_String (W, JSON);
            if W.Failed then
               Result := Rejected_Close;
               Close_Connection := True;
               return;
            end if;
            if W.Len > Response_Data'Length then
               Result := Rejected_Close;
               Close_Connection := True;
               return;
            end if;
            for I in 1 .. W.Len loop
               Response_Data (Response_Data'First + I - 1) := W.Data (I);
            end loop;
            Response_Id := 16#00#;
            Response_Len := W.Len;
            Session_State.Request_Seen := True;
            Result := Responded;
            Close_Connection := False;
            return;
         end;
      elsif Packet_Id = 16#01# then
         if Payload'Length /= 8 then
            Result := Rejected_Close;
            Close_Connection := True;
            return;
         end if;
         declare
            Dec : constant Packets.Ping :=
              Packets.Decode_Ping (Payload);
         begin
            if Dec.Status /= Ok then
               Result := Rejected_Close;
               Close_Connection := True;
               return;
            end if;
         end;
         if 8 > Response_Data'Length then
            Result := Rejected_Close;
            Close_Connection := True;
            return;
         end if;
         for I in 0 .. 7 loop
            Response_Data (Response_Data'First + I) :=
              Payload (Payload'First + I);
         end loop;
         Response_Id := 16#01#;
         Response_Len := 8;
         Result := Pong_Ready_Close;
         Close_Connection := True;
         return;
      else
         Result := Rejected_Close;
         Close_Connection := True;
         return;
      end if;
   end Handle;

end Adacraft.Protocol.Status_Exchange;
