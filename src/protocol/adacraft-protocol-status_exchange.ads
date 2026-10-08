with Ada.Strings.Unbounded;
with Adacraft.Protocol.State;

package Adacraft.Protocol.Status_Exchange is

   Max_JSON_Chars  : constant := 32767;
   Max_Reply_Bytes : constant := 40000;

   type Status_Config is record
      Version_Name     : Ada.Strings.Unbounded.Unbounded_String :=
        Ada.Strings.Unbounded.To_Unbounded_String ("26.3");
      Version_Protocol : Integer := 777;
      Max_Players      : Natural := 20;
      Online_Players   : Natural := 0;
      MOTD             : Ada.Strings.Unbounded.Unbounded_String :=
        Ada.Strings.Unbounded.To_Unbounded_String ("A Minecraft Server");
   end record;

   type Config_Build_Result is record
      Valid  : Boolean := False;
      Config : Status_Config;
   end record;

   type Outcome is record
      Accepted        : Boolean := False;
      Has_Reply       : Boolean := False;
      Reply_Length    : Natural := 0;
      Reply_Data      : Octets (1 .. Max_Reply_Bytes) := [others => 0];
      Close_Requested : Boolean := False;
      Reason          : State.Rejection_Reason := State.No_Rejection;
   end record;

   function Default_Config return Status_Config;

   function Build_Config
     (Version_Name     : String;
      Version_Protocol : Integer;
      Max_Players      : Natural;
      Online_Players   : Natural;
      MOTD             : String) return Config_Build_Result;

   procedure Handle
     (Current_State : State.Connection_State;
      Packet_Id     : Integer;
      Payload       : Octets;
      Config        : Status_Config;
      Status_Sent   : in out Boolean;
      Result        : out Outcome);

end Adacraft.Protocol.Status_Exchange;
