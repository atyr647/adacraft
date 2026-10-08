--  Online-auth session contract and pure reply interpreter.
--  No network, file, or clock I/O. No GNAT.Sockets, Ada.Text_IO,
--  Ada.Calendar calls.

with Ada.Strings.Bounded;
with Interfaces;

package Adacraft.Auth.Session is

   Max_Body_Bytes : constant := 65_536;
   Max_Properties : constant := 16;

   Max_Username_Chars : constant := 16;
   Max_Hash_Chars     : constant := 128;
   Max_Name_Chars     : constant := 16;
   Max_Prop_Chars     : constant := 512;
   Max_Ip_Chars       : constant := 64;

   package Username_Bounded is new Ada.Strings.Bounded.Generic_Bounded_Length
     (Max => Max_Username_Chars);
   package Hash_Bounded is new Ada.Strings.Bounded.Generic_Bounded_Length
     (Max => Max_Hash_Chars);
   package Profile_Name_Bounded is new Ada.Strings.Bounded.Generic_Bounded_Length
     (Max => Max_Name_Chars);
   package Prop_Bounded is new Ada.Strings.Bounded.Generic_Bounded_Length
     (Max => Max_Prop_Chars);
   package Body_Bounded is new Ada.Strings.Bounded.Generic_Bounded_Length
     (Max => Max_Body_Bytes);
   package Ip_Bounded is new Ada.Strings.Bounded.Generic_Bounded_Length
     (Max => Max_Ip_Chars);

   subtype Username      is Username_Bounded.Bounded_String;
   subtype Server_Hash   is Hash_Bounded.Bounded_String;
   subtype Profile_Name  is Profile_Name_Bounded.Bounded_String;
   subtype Property_Text is Prop_Bounded.Bounded_String;
   subtype Body_Bytes    is Body_Bounded.Bounded_String;
   subtype Ip_Text       is Ip_Bounded.Bounded_String;

   type Uuid is array (0 .. 15) of Interfaces.Unsigned_8
     with Default_Component_Value => 0;

   type Optional_Ip (Present : Boolean := False) is record
      case Present is
         when False => null;
         when True  => Value : Ip_Text;
      end case;
   end record;

   type Auth_Property is record
      Name      : Property_Text;
      Value     : Property_Text;
      Has_Sig   : Boolean := False;
      Signature : Property_Text;
   end record;

   type Property_Vector is array (1 .. Max_Properties) of Auth_Property;

   type Auth_Profile is record
      Id         : Uuid := [others => 0];
      Name       : Profile_Name;
      Properties : Property_Vector;
      Prop_Count : Natural range 0 .. Max_Properties := 0;
   end record;

   type Disconnect_Reason is (Auth_Failed, Auth_Service_Unavailable);

   type Result_Kind is (Accepted, Rejected);

   type Auth_Result (Kind : Result_Kind := Rejected) is record
      case Kind is
         when Accepted => Profile : Auth_Profile;
         when Rejected => Reason  : Disconnect_Reason;
      end case;
   end record;

   type Http_Reply (Transport_Failed : Boolean := False) is record
      case Transport_Failed is
         when True  => null;
         when False =>
            Status    : Integer range 100 .. 599 := 200;
            Body_Text : Body_Bytes;
      end case;
   end record;

   function Interpret_Reply (Reply : Http_Reply) return Auth_Result
     with Global => null;

   type Session_Check is interface;

   function Has_Joined
     (Self        : in out Session_Check;
      Username    : Adacraft.Auth.Session.Username;
      Server_Hash : Adacraft.Auth.Session.Server_Hash;
      Client_Ip   : Optional_Ip) return Auth_Result is abstract;

end Adacraft.Auth.Session;
