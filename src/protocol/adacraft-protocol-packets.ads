with Ada.Streams;
with Interfaces;
with Adacraft.Protocol.Buffer;
with Adacraft.Protocol.Frame;

package Adacraft.Protocol.Packets is
   type Handshake is record
      Status   : Status_Kind := Rejected;
      Version  : Interfaces.Unsigned_32 := 0;
      Address  : String (1 .. 255) := (others => ' ');
      Addr_Len : Natural := 0;
      Port     : Interfaces.Unsigned_16 := 0;
      Intent   : Interfaces.Unsigned_32 := 0;
      Next     : Natural := 0;
   end record;

   function Decode_Handshake (Payload : Octets) return Handshake;

   procedure Encode_Status_Response (W : in out Buffer.Writer);
   procedure Encode_Pong (W : in out Buffer.Writer; Payload : Interfaces.Unsigned_64);
   procedure Encode_Login_Disconnect (W : in out Buffer.Writer; Reason : String);

   function Frame (W : in out Buffer.Writer; Payload : Buffer.Writer) return Boolean;

   type Ping is record
      Status : Status_Kind := Rejected;
      Value  : Interfaces.Unsigned_64 := 0;
   end record;

   function Decode_Ping (Payload : Octets) return Ping;

   type Login_Hello is record
      Status : Status_Kind := Rejected;
      Name   : String (1 .. 16) := (others => ' ');
      Name_Len : Natural := 0;
      Uuid   : Octets (1 .. 16) := (others => 0);
   end record;

   function Decode_Login_Hello (Payload : Octets) return Login_Hello;

   --  Generic packet decoder (shipped names recorded from main).
   --  <Packet_Pkg>  = Adacraft.Protocol.Packets
   --  <Field_Kinds> = (K_Boolean, K_Byte, K_Int, K_Long,
   --                   K_Varint, K_Varlong, K_String)
   --    derived from Packet_Encoder on main (Start_Packet/Write_Boolean/
   --    Write_Byte/Write_Int/Write_Long for the packet ID plus fixed-size
   --    fields, Varnum Decode/Decode_Varlong for variable-length fields,
   --    VarInt-prefixed strings). No Field_Kind / String_Max shipped on
   --    main, so these names govern this unit only.
   --  <String_Max>  = 32_767 (matches Buffer.Decode_String bound).

   String_Max : constant := 32_767;

   Max_Decode_Fields : constant := 32;

   subtype Byte_Array is Octets;

   type Field_Kind is
     (K_Boolean, K_Byte, K_Int, K_Long, K_Varint, K_Varlong, K_String);

   type Field_Kind_Array is array (Positive range <>) of Field_Kind;

   type Field_Value (Kind : Field_Kind := K_Boolean) is record
      case Kind is
         when K_Boolean =>
            B : Boolean := False;
         when K_Byte =>
            Y : Octet := 0;
         when K_Int | K_Varint =>
            I32 : Interfaces.Integer_32 := 0;
         when K_Long | K_Varlong =>
            I64 : Interfaces.Integer_64 := 0;
         when K_String =>
            S_Len  : Natural := 0;
            S_Data : String (1 .. String_Max) := (others => ' ');
      end case;
   end record;

   type Field_Value_Array is
     array (Positive range <>) of Field_Value;

   subtype Bounded_Fields is Field_Value_Array (1 .. Max_Decode_Fields);

   type Decode_Error_Kind is
     (Truncated, Overlong, Invalid_Packet_Id, String_Too_Long,
      Invalid_Field_Value, Trailing_Bytes);

   type Decode_Result (Ok : Boolean := False) is record
      case Ok is
         when True =>
            Id         : Natural := 0;
            Num_Fields : Natural := 0;
            Fields     : Bounded_Fields :=
              (others => (Kind => K_Boolean, B => False));
         when False =>
            Err : Decode_Error_Kind := Truncated;
      end case;
   end record;

   function Decode
     (Raw    : Byte_Array;
      Layout : Field_Kind_Array) return Decode_Result;
   --  Single-pass decode of one already-delimited frame body against the
   --  caller-supplied ordered layout. Pure: no world/simulation/connection
   --  state, no I/O. Never raises; all malformations yield Err.

   --  Defensive bound re-check uses Frame.Max_Frame_Body_Length.
   procedure Touch_Frame_Max
     with Inline;

end Adacraft.Protocol.Packets;

end Adacraft.Protocol.Packets;
