with Ada.Command_Line;
with Ada.Streams;
with Ada.Text_IO;
with Interfaces;
with Adacraft.Protocol;
with Adacraft.Protocol.Frame;
with Adacraft.Protocol.Varnum;

procedure Test_Frame_Zero_Length is
   package Frame renames Adacraft.Protocol.Frame;
   package Varnum renames Adacraft.Protocol.Varnum;

   use Adacraft.Protocol;
   use type Adacraft.Protocol.Status_Kind;
   use type Frame.Feed_Status;
   use type Varnum.Status_Type;

   Failures   : Natural := 0;
   Body_Count : Natural := 0;

   procedure Check (Cond : Boolean; Name : String) is
   begin
      if not Cond then
         Ada.Text_IO.Put_Line ("FAIL " & Name);
         Failures := Failures + 1;
      end if;
   end Check;

   procedure On_Frame (Data : Frame.Byte_Array) is
      pragma Unreferenced (Data);
   begin
      Body_Count := Body_Count + 1;
   end On_Frame;

   --  Decoder embeds a ~2 MB buffer: keep it on the heap, never on stack.
   type Decoder_Access is access Frame.Decoder_Type;
   Decoder : constant Decoder_Access := new Frame.Decoder_Type;

   Wire_Buf : Octets (1 .. 5) := (others => 0);
   Written  : Natural := 0;
   Enc_Stat : Varnum.Status_Type := Varnum.Truncated;
   Res      : Frame.Frame_Decode;
   Feed_Stat : Frame.Feed_Status := Frame.Success;
   Chunk    : Frame.Byte_Array (1 .. 1);
begin
   --  Build length-VarInt 0 via Varnum.Encode (no bit logic here).
   Varnum.Encode
     (Value       => 0,
      Buffer      => Wire_Buf,
      Start_Index => 1,
      Written     => Written,
      Status      => Enc_Stat);
   Check (Enc_Stat = Varnum.Ok and then Written = 1
            and then Wire_Buf (1) = 0,
          "encode zero length varint");

   --  One-shot path: Decode_Frame must reject zero length as framing error.
   declare
      Wire : Octets (1 .. 1) := (1 => Wire_Buf (1));
   begin
      Res := Frame.Decode_Frame (Wire, 1);
      Check (Res.Status = Rejected, "decode_frame rejects zero length");
   end;

   --  Streaming path: Feed must reject the same bytes as framing error.
   Chunk (1) := Ada.Streams.Stream_Element (Wire_Buf (1));
   Frame.Feed (Decoder.all, Chunk, On_Frame'Access, Feed_Stat);
   Check (Feed_Stat = Frame.Framing_Error, "feed rejects zero length");
   Check (Body_Count = 0, "no body on zero length");

   --  Framing error is terminal: close, reported again on later calls.
   Frame.Feed (Decoder.all, Chunk, On_Frame'Access, Feed_Stat);
   Check (Feed_Stat = Frame.Framing_Error, "feed stays framing error");
   Check (Body_Count = 0, "still no body after close");

   --  Both paths agree: rejection as a framing error closing the connection.
   Check ((Res.Status = Rejected) = (Feed_Stat = Frame.Framing_Error),
          "both paths agree");
   Check (Res.Status = Rejected and then Feed_Stat = Frame.Framing_Error,
          "same outcome is rejection closing connection");

   if Failures = 0 then
      Ada.Text_IO.Put_Line ("frame zero length tests passed");
   else
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
   end if;
end Test_Frame_Zero_Length;
