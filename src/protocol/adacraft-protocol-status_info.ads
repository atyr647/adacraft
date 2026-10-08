--  Read-only server status snapshot for STATUS state.
--  MOTD is bounded to 256 UTF-8 bytes and validated at construction;
--  any Status_Info value is therefore safe to serialize.

package Adacraft.Protocol.Status_Info is

   Max_Motd_Bytes         : constant := 256;
   Max_Version_Name_Bytes : constant := 32;

   Default_Version_Name : constant String := "26.3";
   Default_Protocol     : constant        := 777;
   Default_Max_Players  : constant        := 20;
   Default_Online       : constant        := 0;
   Default_Motd         : constant String := "AdaCraft";

   Invalid_Status_Info : exception;

   type Status_Info is private;

   function Is_Valid_Utf8 (S : String) return Boolean;

   function Create
     (Motd                 : String;
      Max_Players          : Natural := Default_Max_Players;
      Online_Players       : Natural := Default_Online;
      Enforces_Secure_Chat : Boolean := False;
      Version_Name         : String := Default_Version_Name;
      Protocol             : Integer := Default_Protocol) return Status_Info;
   --  Validates Motd (byte length <= 256, valid UTF-8) and Version_Name
   --  (valid UTF-8, fits bound). Raises Invalid_Status_Info on violation.

   function Default_Info return Status_Info;

   function Motd (Info : Status_Info) return String;
   function Max_Players (Info : Status_Info) return Natural;
   function Online_Players (Info : Status_Info) return Natural;
   function Enforces_Secure_Chat (Info : Status_Info) return Boolean;
   function Version_Name (Info : Status_Info) return String;
   function Protocol_Number (Info : Status_Info) return Integer;

private

   type Status_Info is record
      Version_Len : Natural := Default_Version_Name'Length;
      Version_Txt : String (1 .. Max_Version_Name_Bytes) :=
        (1 .. Default_Version_Name'Length => ' ',
         others                           => ' ');
      Protocol    : Integer := Default_Protocol;
      Max_Players : Natural := Default_Max_Players;
      Online      : Natural := Default_Online;
      Motd_Len    : Natural := Default_Motd'Length;
      Motd_Txt    : String (1 .. Max_Motd_Bytes) :=
        (1 .. Default_Motd'Length => ' ', others => ' ');
      Enforces    : Boolean := False;
   end record;

end Adacraft.Protocol.Status_Info;
