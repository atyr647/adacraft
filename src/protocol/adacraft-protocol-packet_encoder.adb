with Interfaces;
with Adacraft.Protocol.Frame;
with Adacraft.Protocol.Varnum;

package body Adacraft.Protocol.Packet_Encoder is

   --  Internal capacity helper for field writers.
   --  Precedence: sticky error first, then ordering, then Overflow,
   --  then Body_Too_Long. Sets E.St on failure, Ready = False.
   procedure Reserve
     (E     : in out Encoder;
      Buf   : Byte_Array;
      Count : Natural;
      Ready : out Boolean)
   is
      Cap : Natural;
   begin
      Ready := False;
      if E.St /= Ok then
         return;
      end if;
      if not E.Id_Written then
         E.St := Invalid_Sequence;
         return;
      end if;
      Cap := Buf'Length;
      if Count > Cap - E.Len then
         E.St := Overflow;
         return;
      end if;
      if E.Len + Count > Adacraft.Protocol.Frame.Max_Frame_Body_Length then
         E.St := Body_Too_Long;
         return;
      end if;
      Ready := True;
   end Reserve;

   procedure Start (E : out Encoder) is
   begin
      E.Len := 0;
      E.St := Ok;
      E.Id_Written := False;
   end Start;

   procedure Write_Packet_Id
     (E   : in out Encoder;
      Buf : in out Byte_Array;
      Id  : Interfaces.Integer_32)
   is
      use type Interfaces.Integer_32;
      use type Varnum.Status_Type;
      Staging : Adacraft.Protocol.Octets (1 .. Max_Varint_Bytes) := (others => 0);
      Written : Natural := 0;
      Vs      : Varnum.Status_Type;
      Ready   : Boolean := False;
      Cap     : Natural;
   begin
      if E.St /= Ok then
         return;
      end if;
      if E.Id_Written then
         E.St := Invalid_Sequence;
         return;
      end if;
      if Id < 0 then
         E.St := Invalid_Packet_Id;
         return;
      end if;
      Varnum.Encode (Id, Staging, Staging'First, Written, Vs);
      if Vs /= Varnum.Ok then
         E.St := Overflow;
         return;
      end if;
      Cap := Buf'Length;
      if Written > Cap - E.Len then
         E.St := Overflow;
         return;
      end if;
      if E.Len + Written > Adacraft.Protocol.Frame.Max_Frame_Body_Length then
         E.St := Body_Too_Long;
         return;
      end if;
      Ready := True;
      if Ready then
         for I in 0 .. Written - 1 loop
            Buf (Buf'First + E.Len + I) := Staging (Staging'First + I);
         end loop;
         E.Len := E.Len + Written;
         E.Id_Written := True;
      end if;
   end Write_Packet_Id;

   procedure Write_Boolean
     (E   : in out Encoder;
      Buf : in out Byte_Array;
      V   : Boolean)
   is
      pragma Unreferenced (Buf);
      pragma Unreferenced (V);
   begin
      if E.St /= Ok then
         return;
      end if;
      if not E.Id_Written then
         E.St := Invalid_Sequence;
         return;
      end if;
      null;
   end Write_Boolean;

   procedure Write_Byte
     (E   : in out Encoder;
      Buf : in out Byte_Array;
      V   : Interfaces.Integer_8)
   is
      pragma Unreferenced (Buf);
      pragma Unreferenced (V);
   begin
      if E.St /= Ok then
         return;
      end if;
      if not E.Id_Written then
         E.St := Invalid_Sequence;
         return;
      end if;
      null;
   end Write_Byte;

   procedure Write_UByte
     (E   : in out Encoder;
      Buf : in out Byte_Array;
      V   : Interfaces.Unsigned_8)
   is
      pragma Unreferenced (Buf);
      pragma Unreferenced (V);
   begin
      if E.St /= Ok then
         return;
      end if;
      if not E.Id_Written then
         E.St := Invalid_Sequence;
         return;
      end if;
      null;
   end Write_UByte;

   procedure Write_Short
     (E   : in out Encoder;
      Buf : in out Byte_Array;
      V   : Interfaces.Integer_16)
   is
      pragma Unreferenced (Buf);
      pragma Unreferenced (V);
   begin
      if E.St /= Ok then
         return;
      end if;
      if not E.Id_Written then
         E.St := Invalid_Sequence;
         return;
      end if;
      null;
   end Write_Short;

   procedure Write_UShort
     (E   : in out Encoder;
      Buf : in out Byte_Array;
      V   : Interfaces.Unsigned_16)
   is
      pragma Unreferenced (Buf);
      pragma Unreferenced (V);
   begin
      if E.St /= Ok then
         return;
      end if;
      if not E.Id_Written then
         E.St := Invalid_Sequence;
         return;
      end if;
      null;
   end Write_UShort;

   procedure Write_Int
     (E   : in out Encoder;
      Buf : in out Byte_Array;
      V   : Interfaces.Integer_32)
   is
      pragma Unreferenced (Buf);
      pragma Unreferenced (V);
   begin
      if E.St /= Ok then
         return;
      end if;
      if not E.Id_Written then
         E.St := Invalid_Sequence;
         return;
      end if;
      null;
   end Write_Int;

   procedure Write_Long
     (E   : in out Encoder;
      Buf : in out Byte_Array;
      V   : Interfaces.Integer_64)
   is
      pragma Unreferenced (Buf);
      pragma Unreferenced (V);
   begin
      if E.St /= Ok then
         return;
      end if;
      if not E.Id_Written then
         E.St := Invalid_Sequence;
         return;
      end if;
      null;
   end Write_Long;

   procedure Write_VarInt
     (E   : in out Encoder;
      Buf : in out Byte_Array;
      V   : Interfaces.Integer_32)
   is
      pragma Unreferenced (Buf);
      pragma Unreferenced (V);
   begin
      if E.St /= Ok then
         return;
      end if;
      if not E.Id_Written then
         E.St := Invalid_Sequence;
         return;
      end if;
      null;
   end Write_VarInt;

   procedure Write_VarLong
     (E   : in out Encoder;
      Buf : in out Byte_Array;
      V   : Interfaces.Integer_64)
   is
      pragma Unreferenced (Buf);
      pragma Unreferenced (V);
   begin
      if E.St /= Ok then
         return;
      end if;
      if not E.Id_Written then
         E.St := Invalid_Sequence;
         return;
      end if;
      null;
   end Write_VarLong;

   procedure Write_String
     (E         : in out Encoder;
      Buf       : in out Byte_Array;
      Bytes     : Byte_Array;
      Max_Bytes : Natural)
   is
      pragma Unreferenced (Buf);
      pragma Unreferenced (Bytes);
      pragma Unreferenced (Max_Bytes);
   begin
      if E.St /= Ok then
         return;
      end if;
      if not E.Id_Written then
         E.St := Invalid_Sequence;
         return;
      end if;
      null;
   end Write_String;

   procedure Write_Bytes
     (E   : in out Encoder;
      Buf : in out Byte_Array;
      B   : Byte_Array)
   is
      pragma Unreferenced (Buf);
      pragma Unreferenced (B);
   begin
      if E.St /= Ok then
         return;
      end if;
      if not E.Id_Written then
         E.St := Invalid_Sequence;
         return;
      end if;
      null;
   end Write_Bytes;

   function Body_Length (E : Encoder) return Natural is
   begin
      return E.Len;
   end Body_Length;

   function Status_Of (E : Encoder) return Status is
   begin
      return E.St;
   end Status_Of;

   procedure Finish
     (E         : in     Encoder;
      Buf       : in     Byte_Array;
      Body_Last :    out Natural;
      S         :    out Status)
   is
   begin
      Body_Last := Buf'First - 1;
      if E.St /= Ok then
         S := E.St;
         return;
      end if;
      if not E.Id_Written then
         S := Invalid_Sequence;
         return;
      end if;
      if E.Len = 0 then
         S := Invalid_Sequence;
         return;
      end if;
      if E.Len > Buf'Length then
         S := Overflow;
         return;
      end if;
      Body_Last := Buf'First + E.Len - 1;
      S := Ok;
   end Finish;

   procedure Frame
     (E       : in     Encoder;
      Buf     : in     Byte_Array;
      Out_Buf :    out Byte_Array;
      Out_Last :   out Natural;
      S       :    out Status)
   is
      pragma Unreferenced (Buf);
   begin
      Out_Last := Out_Buf'First - 1;
      if E.St /= Ok then
         S := E.St;
         return;
      end if;
      if not E.Id_Written then
         S := Invalid_Sequence;
         return;
      end if;
      --  Full framing delegation is implemented in a later task.
      S := Frame_Error;
   end Frame;

end Adacraft.Protocol.Packet_Encoder;
