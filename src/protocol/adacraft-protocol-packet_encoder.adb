with Ada.Streams;
with Interfaces;
with Adacraft.Protocol;
with Adacraft.Protocol.Frame;
with Adacraft.Protocol.Varnum;

package body Adacraft.Protocol.Packet_Encoder is
   use type Ada.Streams.Stream_Element_Offset;
   use type Adacraft.Protocol.Varnum.Status_Type;
   use type Adacraft.Protocol.Frame.Encode_Status;

   procedure Append_Raw
     (E      : in out Encoder_Type;
      Source :        Ada.Streams.Stream_Element_Array)
   is
   begin
      if E.Failed then
         return;
      end if;

      if Source'Length > Natural (E.Capacity) - E.Count then
         E.Failed := True;
         return;
      end if;

      for Item of Source loop
         E.Count := E.Count + 1;
         E.Buffer (Ada.Streams.Stream_Element_Offset (E.Count)) := Item;
      end loop;
   end Append_Raw;

   procedure Append_VarInt_Id
     (E         : in out Encoder_Type;
      Packet_Id :        Interfaces.Integer_32)
   is
      Encoded : Adacraft.Protocol.Octets (1 .. 5) := (others => 0);
      Written : Natural;
      Status  : Adacraft.Protocol.Varnum.Status_Type;
   begin
      Adacraft.Protocol.Varnum.Encode
        (Packet_Id, Encoded, Encoded'First, Written, Status);

      if Status /= Adacraft.Protocol.Varnum.Ok then
         E.Failed := True;
         E.Count := 0;
         return;
      end if;

      declare
         Raw : Ada.Streams.Stream_Element_Array (1 .. Ada.Streams.Stream_Element_Offset (Written));
      begin
         for I in 1 .. Written loop
            Raw (Ada.Streams.Stream_Element_Offset (I)) :=
              Ada.Streams.Stream_Element (Encoded (I));
         end loop;
         Append_Raw (E, Raw);
      end;
   end Append_VarInt_Id;

   procedure Start_Packet
     (E         : in out Encoder_Type;
      Packet_Id :        Interfaces.Integer_32)
   is
   begin
      E.Count := 0;
      E.Failed := False;
      E.Started := True;
      Append_VarInt_Id (E, Packet_Id);
   end Start_Packet;

   procedure Write_Boolean (E : in out Encoder_Type; V : Boolean) is
      Value : Ada.Streams.Stream_Element_Array (1 .. 1);
   begin
      if E.Failed then
         return;
      end if;

      if not E.Started then
         E.Failed := True;
         return;
      end if;

      Value (1) := (if V then 16#01# else 16#00#);
      Append_Raw (E, Value);
   end Write_Boolean;

   procedure Write_Byte (E : in out Encoder_Type; V : Interfaces.Integer_8) is
      Value : Ada.Streams.Stream_Element_Array (1 .. 1);
   begin
      if E.Failed then
         return;
      end if;

      if not E.Started then
         E.Failed := True;
         return;
      end if;

      Value (1) := Ada.Streams.Stream_Element (Integer (V) mod 256);
      Append_Raw (E, Value);
   end Write_Byte;

   procedure Write_Int (E : in out Encoder_Type; V : Interfaces.Integer_32) is
      Bits  : constant Interfaces.Unsigned_32 := Interfaces.Unsigned_32 (V);
      Value : Ada.Streams.Stream_Element_Array (1 .. 4);
   begin
      if E.Failed then
         return;
      end if;

      if not E.Started then
         E.Failed := True;
         return;
      end if;

      for I in 0 .. 3 loop
         Value (Ada.Streams.Stream_Element_Offset (I + 1)) :=
           Ada.Streams.Stream_Element
             (Interfaces.Shift_Right (Bits, (3 - I) * 8) and 16#FF#);
      end loop;
      Append_Raw (E, Value);
   end Write_Int;

   procedure Write_Long (E : in out Encoder_Type; V : Interfaces.Integer_64) is
      Bits  : constant Interfaces.Unsigned_64 := Interfaces.Unsigned_64 (V);
      Value : Ada.Streams.Stream_Element_Array (1 .. 8);
   begin
      if E.Failed then
         return;
      end if;

      if not E.Started then
         E.Failed := True;
         return;
      end if;

      for I in 0 .. 7 loop
         Value (Ada.Streams.Stream_Element_Offset (I + 1)) :=
           Ada.Streams.Stream_Element
             (Interfaces.Shift_Right (Bits, (7 - I) * 8) and 16#FF#);
      end loop;
      Append_Raw (E, Value);
   end Write_Long;

   function Has_Failed (E : Encoder_Type) return Boolean is
   begin
      return E.Failed;
   end Has_Failed;

   function Length (E : Encoder_Type) return Natural is
   begin
      return E.Count;
   end Length;

   procedure Encode_Frame
     (E       : in out Encoder_Type;
      Output  :    out Ada.Streams.Stream_Element_Array;
      Out_Len :    out Natural;
      Success :    out Boolean)
   is
      Last   : Ada.Streams.Stream_Element_Offset;
      Status : Adacraft.Protocol.Frame.Encode_Status;
   begin
      Out_Len := 0;
      Success := False;

      if E.Failed
        or else not E.Started
        or else E.Count > Adacraft.Protocol.Frame.Max_Frame_Body_Length
      then
         return;
      end if;

      Adacraft.Protocol.Frame.Encode
        (E.Buffer (1 .. Ada.Streams.Stream_Element_Offset (E.Count)),
         Output, Last, Status);

      if Status = Adacraft.Protocol.Frame.Ok then
         Out_Len := Natural (Last - Output'First + 1);
         Success := True;
      end if;
   end Encode_Frame;
end Adacraft.Protocol.Packet_Encoder;
