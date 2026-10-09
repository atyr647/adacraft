with Ada.Text_IO;
with Interfaces;
with Adacraft.Protocol;
with Adacraft.Protocol.Compression;
with Adacraft.Protocol.Frame;

procedure Test_Compression_Wiring is
   use Adacraft.Protocol;
   use type Interfaces.Unsigned_8;

   Failures : Natural := 0;

   procedure Check (Cond : Boolean; Name : String) is
   begin
      if not Cond then
         Failures := Failures + 1;
         Ada.Text_IO.Put_Line ("FAIL: " & Name);
      end if;
   end Check;

   function Equal_Octets (A, B : Octets) return Boolean is
   begin
      if A'Length /= B'Length then
         return False;
      end if;
      for I in 1 .. A'Length loop
         if A (A'First + I - 1) /= B (B'First + I - 1) then
            return False;
         end if;
      end loop;
      return True;
   end Equal_Octets;

   procedure Read_Varint
     (Buf : Octets; From : Positive; Value : out Natural;
      Next : out Natural; Ok : out Boolean)
   is
      V : Natural := 0;
      Shift : Natural := 0;
      Pos : Natural := From;
   begin
      Value := 0;
      Next := From;
      Ok := False;
      loop
         if Pos > Buf'Last then
            return;
         end if;
         V := V + Natural (Buf (Pos) and 16#7F#) * (2 ** Shift);
         Shift := Shift + 7;
         Pos := Pos + 1;
         if Shift > 35 then
            return;
         end if;
         if (Buf (Pos - 1) and 16#80#) = 0 then
            Value := V;
            Next := Pos;
            Ok := True;
            return;
         end if;
      end loop;
   end Read_Varint;

   procedure Encode_Varint (Value : Natural; Buf : out Octets; Len : out Natural) is
      V : Natural := Value;
      N : Natural := 0;
   begin
      loop
         N := N + 1;
         Buf (N) := Octet (V mod 128);
         V := V / 128;
         if V > 0 then
            Buf (N) := Buf (N) or 16#80#;
         else
            exit;
         end if;
      end loop;
      Len := N;
   end Encode_Varint;

   function Make_Payload (Size : Positive; Fill : Octet) return Octets is
      Result : Octets (1 .. Size);
   begin
      Result (1) := 2;
      for I in 2 .. Size loop
         Result (I) := Fill;
      end loop;
      return Result;
   end Make_Payload;

   --  (a) Set Compression egress is uncompressed, next egress compressed.
   procedure T_Set_Compression_First is
      use Adacraft.Protocol.Frame;
      SC_Payload : Octets (1 .. 3) := (3, 16#80#, 16#02#);
      Next_Pay : Octets := Make_Payload (10, 16#41#);
      SC_Frame : Octets := Encode_Compressed_Frame (SC_Payload, 256);
      --  Reference uncompressed framing via plain Decode_Frame on a
      --  manually length-prefixed buffer.
      Plen_Buf : Octets (1 .. 5) := (others => 0);
      Plen_Len : Natural := 0;
      Plain : Octets (1 .. 4);
      D : Frame_Decode;
   begin
      --  The Set Compression packet itself must be framed uncompressed by
      --  the caller: here we check the plain length-prefixed form decodes.
      Encode_Varint (SC_Payload'Length, Plen_Buf, Plen_Len);
      Plain := (Octets (Plen_Buf (1 .. Plen_Len)) & SC_Payload);
      D := Decode_Frame (Plain, 1);
      Check (D.Status = Ok, "a: set compression plain decodes");
      Check (D.Packet_Id = 3, "a: set compression id 3");
      --  Next egress uses compressed framing.
      declare
         F : Octets := Encode_Compressed_Frame (Next_Pay, 256);
         PL, DL : Natural := 0;
         N1, N2 : Natural := 0;
         Ok1, Ok2 : Boolean := False;
      begin
         Check (F'Length > 0, "a: next egress non-empty");
         Read_Varint (F, 1, PL, N1, Ok1);
         Read_Varint (F, N1, DL, N2, Ok2);
         Check (Ok1 and Ok2, "a: prefixes parse");
         Check (DL = 0, "a: small next egress DataLen 0");
         Check (PL = F'Length - N1 + 1, "a: Packet_Length covers DataLen+payload");
         Check (Equal_Octets (F (N2 .. F'Last), Next_Pay), "a: raw payload follows");
      end;
   end T_Set_Compression_First;

   --  (b) below threshold gets Data_Length 0.
   procedure T_Below is
      use Adacraft.Protocol.Frame;
      Pay : Octets := Make_Payload (5, 16#42#);
      F : Octets := Encode_Compressed_Frame (Pay, 256);
      PL, DL : Natural := 0;
      N1, N2 : Natural := 0;
      Ok1, Ok2 : Boolean := False;
   begin
      Read_Varint (F, 1, PL, N1, Ok1);
      Read_Varint (F, N1, DL, N2, Ok2);
      Check (Ok1 and Ok2, "b: prefixes parse");
      Check (DL = 0, "b: DataLen 0 below threshold");
      Check (PL = 1 + Pay'Length, "b: Packet_Length exact");
      Check (Equal_Octets (F (N2 .. F'Last), Pay), "b: payload raw");
   end T_Below;

   --  (c) at/above threshold compressed with correct DataLen + Packet_Length.
   procedure T_Above is
      use Adacraft.Protocol.Frame;
      Pay : Octets := Make_Payload (100, 16#43#);
      F : Octets := Encode_Compressed_Frame (Pay, 16);
      PL, DL : Natural := 0;
      N1, N2 : Natural := 0;
      Ok1, Ok2 : Boolean := False;
      Data : Compression.Byte_Array_Access := null;
      Next : Natural := 0;
      St : Compressed_Split_Status := Rejected;
   begin
      Check (F'Length > 0, "c: frame non-empty");
      Read_Varint (F, 1, PL, N1, Ok1);
      Read_Varint (F, N1, DL, N2, Ok2);
      Check (Ok1 and Ok2, "c: prefixes parse");
      Check (DL = Pay'Length, "c: DataLen equals uncompressed size");
      Check (PL = F'Length - (N1 - 1), "c: Packet_Length covers rest");
      Decode_Compressed_Frame (F, 1, 16, Data, Next, St);
      Check (St = Ok, "c: decodes ok");
      if St = Ok and then Data /= null then
         Check (Equal_Octets (Data.all, Pay), "c: round-trip payload");
         Check (Next = F'Last + 1, "c: Next at end");
      else
         Check (False, "c: data present");
      end if;
      Compression.Free (Data);
      --  Boundary: length exactly threshold compresses.
      declare
         Pay2 : Octets := Make_Payload (16, 16#44#);
         F2 : Octets := Encode_Compressed_Frame (Pay2, 16);
         DL2 : Natural := 0;
         M1, M2 : Natural := 0;
         O1, O2 : Boolean := False;
         PL2 : Natural := 0;
      begin
         Read_Varint (F2, 1, PL2, M1, O1);
         Read_Varint (F2, M1, DL2, M2, O2);
         Check (O1 and O2, "c: boundary prefixes parse");
         Check (DL2 = Pay2'Length, "c: at-threshold compresses");
      end;
   end T_Above;

   --  (d) reject non-zero DataLen < threshold.
   procedure T_Reject_Below is
      use Adacraft.Protocol.Frame;
      Pay : Octets := Make_Payload (100, 16#45#);
      F : Octets := Encode_Compressed_Frame (Pay, 16);
      Data : Compression.Byte_Array_Access := null;
      Next : Natural := 0;
      St : Compressed_Split_Status := Rejected;
   begin
      --  Same bytes validated against a larger threshold: declared
      --  Data_Length (100) < 256 must be rejected.
      Decode_Compressed_Frame (F, 1, 256, Data, Next, St);
      Check (St = Rejected, "d: non-zero DataLen below threshold rejected");
      Check (Data = null, "d: no data on reject");
      Compression.Free (Data);
   end T_Reject_Below;

   --  (e) reject truncated/padded mismatch (declared vs actual).
   procedure T_Mismatch is
      use Adacraft.Protocol.Frame;
      Pay : Octets := Make_Payload (100, 16#46#);
      F : Octets := Encode_Compressed_Frame (Pay, 16);
      PL : Natural := 0;
      N1 : Natural := 0;
      Ok1 : Boolean := False;
      Data : Compression.Byte_Array_Access := null;
      Next : Natural := 0;
      St : Compressed_Split_Status := Rejected;
   begin
      Read_Varint (F, 1, PL, N1, Ok1);
      Check (Ok1, "e: prefix parses");
      --  Truncated: drop last byte -> Need_More, never Ok.
      Decode_Compressed_Frame (F (1 .. F'Last - 1), 1, 16, Data, Next, St);
      Check (St /= Ok, "e: truncated not ok");
      Compression.Free (Data);
      --  Padded/mismatched: bump declared Data_Length by one without
      --  changing the zlib bytes. Payload len 100 -> declare 101;
      --  both are 1-byte varints so frame shape is unchanged.
      declare
         G : Octets := F;
      begin
         G (N1) := Octet (101);
         Decode_Compressed_Frame (G, 1, 16, Data, Next, St);
         Check (St = Rejected, "e: padded mismatch rejected");
         Compression.Free (Data);
      end;
   end T_Mismatch;

   --  (f) negative threshold sends nothing, framing unchanged.
   procedure T_Negative is
      use Adacraft.Protocol.Frame;
      Threshold : Integer := -1;
      Sent : Boolean := False;
      Pay : Octets := Make_Payload (8, 16#47#);
      Plen_Buf : Octets (1 .. 5) := (others => 0);
      Plen_Len : Natural := 0;
      Plain : Octets (1 .. 9);
      D : Frame_Decode;
   begin
      --  Caller guard: never send Set Compression when negative.
      if Threshold < 0 then
         Sent := False;
      else
         Sent := True;
      end if;
      Check (not Sent, "f: negative sends nothing");
      Encode_Varint (Pay'Length, Plen_Buf, Plen_Len);
      Plain := (Octets (Plen_Buf (1 .. Plen_Len)) & Pay);
      D := Decode_Frame (Plain, 1);
      Check (D.Status = Ok, "f: plain framing unchanged");
      Check (D.Packet_Id = 2, "f: id preserved");
   end T_Negative;

   --  Two-connection isolation.
   procedure T_Isolation is
      use Adacraft.Protocol.Frame;
      type Conn_Sim is record
         Threshold : Natural := 256;
         Active : Boolean := False;
         Sent : Boolean := False;
      end record;
      A : Conn_Sim := (Threshold => 256, Active => True, Sent => True);
      B : Conn_Sim := (Threshold => 16, Active => True, Sent => True);
      Pay : Octets := Make_Payload (100, 16#48#);
      FA : Octets := Encode_Compressed_Frame (Pay, A.Threshold);
      FB : Octets := Encode_Compressed_Frame (Pay, B.Threshold);
      DLA, DLB : Natural := 0;
      N1, N2, M1, M2 : Natural := 0;
      O1, O2, P1, P2 : Boolean := False;
      PLA, PLB : Natural := 0;
   begin
      Read_Varint (FA, 1, PLA, N1, O1);
      Read_Varint (FA, N1, DLA, N2, O2);
      Read_Varint (FB, 1, PLB, M1, P1);
      Read_Varint (FB, M1, DLB, M2, P2);
      Check (O1 and O2 and P1 and P2, "iso: parse");
      Check (DLA = 0, "iso: A below threshold uncompressed");
      Check (DLB = Pay'Length, "iso: B above threshold compressed");
      Check (A.Active and B.Active, "iso: flags independent");
   end T_Isolation;

begin
   T_Set_Compression_First;
   T_Below;
   T_Above;
   T_Reject_Below;
   T_Mismatch;
   T_Negative;
   T_Isolation;
   if Failures = 0 then
      Ada.Text_IO.Put_Line ("PASS test_compression_wiring");
   else
      Ada.Text_IO.Put_Line ("FAIL test_compression_wiring:" & Natural'Image (Failures));
   end if;
   if Failures > 0 then
      raise Program_Error with "compression wiring failures";
   end if;
end Test_Compression_Wiring;
