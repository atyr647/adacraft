with Ada.Text_IO;
with Interfaces;
with Adacraft.Protocol;
with Adacraft.Protocol.Compression;
with Adacraft.Protocol.Frame;

procedure Test_Login_Encryption_Compression is
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

   --  Stand-in stream cipher for the #215 CFB8 vector key: XOR with a
   --  repeating key. The point under test is layer ordering
   --  (compress-then-encrypt / decrypt-then-decompress), not the cipher.
   --  #213 fake session check is a plain Boolean allow/deny.
   Fake_Key : constant Octets (1 .. 16) :=
     (16#2B#, 16#7E#, 16#15#, 16#16#, 16#28#, 16#AE#, 16#D2#, 16#A6#,
      16#AB#, 16#F7#, 16#15#, 16#88#, 16#09#, 16#CF#, 16#4F#, 16#3C#);

   Fake_Session_Allow : constant Boolean := True;

   function Xor_Crypt (Data : Octets) return Octets is
      Result : Octets (Data'Range);
   begin
      for I in Data'Range loop
         Result (I) :=
           Data (I) xor Fake_Key ((I - Data'First) mod 16 + Fake_Key'First);
      end loop;
      return Result;
   end Xor_Crypt;

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

   function Make_Payload (Size : Positive; Fill : Octet) return Octets is
      Result : Octets (1 .. Size);
   begin
      Result (1) := 2;
      for I in 2 .. Size loop
         Result (I) := Fill;
      end loop;
      return Result;
   end Make_Payload;

   --  Egress: packet -> compression framing -> encrypt -> socket.
   procedure T_Egress_Order is
      use Adacraft.Protocol.Frame;
      Pay : Octets := Make_Payload (120, 16#51#);
      Compressed : Octets := Encode_Compressed_Frame (Pay, 16);
      On_Wire : Octets := Xor_Crypt (Compressed);
      Back : Octets := Xor_Crypt (On_Wire);
      DL : Natural := 0;
      N1, N2 : Natural := 0;
      O1, O2 : Boolean := False;
      PL : Natural := 0;
      Data : Compression.Byte_Array_Access := null;
      Next : Natural := 0;
      St : Compressed_Split_Status := Rejected;
   begin
      Check (Fake_Session_Allow, "egress: fake session allows login");
      Check (Compressed'Length > 0, "egress: compressed non-empty");
      Check (not Equal_Octets (On_Wire, Compressed), "egress: ciphertext differs");
      --  Correct order decrypts to a compressed frame.
      Read_Varint (Back, 1, PL, N1, O1);
      Read_Varint (Back, N1, DL, N2, O2);
      Check (O1 and O2, "egress: decrypted prefixes parse");
      Check (DL = Pay'Length, "egress: DataLen correct after decrypt");
      Decode_Compressed_Frame (Back, 1, 16, Data, Next, St);
      Check (St = Ok, "egress: decrypt-then-decompress ok");
      if St = Ok and then Data /= null then
         Check (Equal_Octets (Data.all, Pay), "egress: round-trip payload");
      else
         Check (False, "egress: data present");
      end if;
      Compression.Free (Data);
      --  Swapped order (encrypt-then-compress) must not decode: decrypting
      --  the wrong layer yields garbage framing.
      declare
         Wrong : Octets := Encode_Compressed_Frame (Xor_Crypt (Pay), 16);
         D2 : Compression.Byte_Array_Access := null;
         N : Natural := 0;
         S2 : Compressed_Split_Status := Rejected;
      begin
         Decode_Compressed_Frame (Xor_Crypt (Wrong), 1, 16, D2, N, S2);
         --  This path double-encrypts inconsistently; at minimum the
         --  payload must not equal the original without proper order.
         if S2 = Ok and then D2 /= null then
            Check (not Equal_Octets (D2.all, Pay), "egress: swapped order corrupts");
         end if;
         Compression.Free (D2);
      end;
   end T_Egress_Order;

   --  Ingress: socket -> decrypt -> frame split -> decompress -> decode.
   procedure T_Ingress_Order is
      use Adacraft.Protocol.Frame;
      --  Login Acknowledged serverbound id 3, empty body.
      Ack : Octets (1 .. 1) := (1 => 3);
      Compressed : Octets := Encode_Compressed_Frame (Ack, 16);
      On_Wire : Octets := Xor_Crypt (Compressed);
      Data : Compression.Byte_Array_Access := null;
      Next : Natural := 0;
      St : Compressed_Split_Status := Rejected;
   begin
      --  Correct ingress order.
      declare
         Decrypted : Octets := Xor_Crypt (On_Wire);
      begin
         Decode_Compressed_Frame (Decrypted, 1, 16, Data, Next, St);
         Check (St = Ok, "ingress: decrypt-then-decompress ok");
         if St = Ok and then Data /= null then
            Check (Equal_Octets (Data.all, Ack), "ingress: ack round-trips");
         else
            Check (False, "ingress: data present");
         end if;
         Compression.Free (Data);
      end;
      --  Decompress-before-decrypt (wrong order) must fail.
      Decode_Compressed_Frame (On_Wire, 1, 16, Data, Next, St);
      Check (St /= Ok or else Data = null
             or else not Equal_Octets (Data.all, Ack),
             "ingress: wrong order does not yield ack");
      Compression.Free (Data);
   end T_Ingress_Order;

begin
   T_Egress_Order;
   T_Ingress_Order;
   if Failures = 0 then
      Ada.Text_IO.Put_Line ("PASS test_login_encryption_compression");
   else
      Ada.Text_IO.Put_Line ("FAIL test_login_encryption_compression:" & Natural'Image (Failures));
   end if;
   if Failures > 0 then
      raise Program_Error with "ordering failures";
   end if;
end Test_Login_Encryption_Compression;
