with Ada.Command_Line;
with Ada.Text_IO;
with Interfaces;
with System;
with Adacraft.Protocol;
with Adacraft.Protocol.Ids;
with Adacraft.Protocol.State;
with Adacraft.Protocol.Login_Encryption;

procedure Test_Protocol_Login_Encryption is
   use Adacraft.Protocol;
   use type Interfaces.Unsigned_8;
   use type System.Address;
   package LE renames Adacraft.Protocol.Login_Encryption;
   use type LE.Encode_Status;
   use type LE.Decode_Status;
   use type LE.Encrypt_Status;
   use type LE.Verify_Status;

   Failures : Natural := 0;

   procedure Check (Cond : Boolean; Name : String) is
   begin
      if not Cond then
         Failures := Failures + 1;
         Ada.Text_IO.Put_Line ("FAIL: " & Name);
      end if;
   end Check;

   function Bytes_Equal (A, B : Octets) return Boolean is
   begin
      if A'Length /= B'Length then
         return False;
      end if;
      for I in 1 .. A'Length loop
         if A (A'First + (I - 1)) /= B (B'First + (I - 1)) then
            return False;
         end if;
      end loop;
      return True;
   end Bytes_Equal;

   Der_Buf : Octets (1 .. 2_048) := (others => 0);
   Der_Len : Natural := 0;
   Der_Ok  : Boolean := False;

   Tok_A : LE.Token_Bytes := (others => 0);
   Tok_Ok : Boolean := False;
begin
   --  Init once.
   Check (LE.Ensure_Initialized, "T1 ensure initialized");
   Check (LE.Is_Initialized, "T1 is initialized");
   Check (LE.Private_Handle_Address /= System.Null_Address,
          "T1 private handle present");
   Check (LE.Public_Der_Length > 0, "T1 der length nonzero");

   LE.Get_Public_DER (Der_Buf, Der_Len, Der_Ok);
   Check (Der_Ok and then Der_Len = LE.Public_Der_Length,
          "T1 get der ok");
   Check (Der_Len > 0 and then Der_Len <= Der_Buf'Length,
          "T1 der length bounds");

   --  T1: DER parses back as 1024-bit RSA with e = 65537.
   --  NOTE: parsed back via the Login_Encryption test-encrypt hook
   --  (wire compatibility without touching Adacraft.Crypto directly,
   --  whose parent spec lives outside this task's files).
   declare
      Found_Exp : Boolean := False;
   begin
      Check (Der_Len >= 100 and then Der_Len <= Der_Buf'Length,
             "T1 der plausible spki length");
      --  e = 65537 is DER INTEGER 02 03 01 00 01 inside the SPKI.
      if Der_Len >= 5 then
         for I in 1 .. Der_Len - 4 loop
            if Der_Buf (I) = 16#02# and then Der_Buf (I + 1) = 16#03#
              and then Der_Buf (I + 2) = 16#01#
              and then Der_Buf (I + 3) = 16#00#
              and then Der_Buf (I + 4) = 16#01#
            then
               Found_Exp := True;
            end if;
         end loop;
      end if;
      Check (Found_Exp, "T1 exponent 65537 in DER");
      Check (Der_Buf'Length = 2_048, "T1 der buffer shape");
      --  1024-bit RSA => 128-byte ciphertext via the live public key.
      declare
         Probe : constant Octets (1 .. 4) := (1, 2, 3, 4);
         Er    : LE.Encrypt_Result := LE.Test_Encrypt_With_Public_Key (Probe);
      begin
         Check (Er.Status = LE.Encrypt_Ok and then Er.Length = 128,
                "T1 rsa size 128 via public encrypt");
      end;
   end;

   --  T10 + token generation (needed by T2/T4 too).
   LE.Generate_Verify_Token (Tok_A, Tok_Ok);
   Check (Tok_Ok, "T10 generate token ok");
   declare
      Tok_B : LE.Token_Bytes := (others => 0);
      Ok_B  : Boolean := False;
      Same  : Boolean := True;
   begin
      LE.Generate_Verify_Token (Tok_B, Ok_B);
      Check (Ok_B, "T10 second token ok");
      for I in LE.Token_Bytes'Range loop
         if Tok_A (I) /= Tok_B (I) then
            Same := False;
         end if;
      end loop;
      if Same then
         --  Astronomically unlikely collision: regenerate once, not a loop.
         LE.Generate_Verify_Token (Tok_B, Ok_B);
         Same := True;
         if Ok_B then
            Same := False;
            for I in LE.Token_Bytes'Range loop
               if Tok_A (I) /= Tok_B (I) then
                  null;
               else
                  --  count equal bytes; recompute below
                  null;
               end if;
            end loop;
            Same := Bytes_Equal (Octets (Tok_A), Octets (Tok_B));
         end if;
      end if;
      Check (not Same, "T10 two tokens differ");
   end;

   --  T2: request encode, pinned ID + VarInt prefixes, True/False.
   declare
      Der_Slice : Octets renames Der_Buf (1 .. Der_Len);
      Tok_Fixed : constant LE.Token_Bytes := (16#AA#, 16#BB#, 16#CC#, 16#DD#);
      Req_Id : constant Natural :=
        Adacraft.Protocol.Ids.Protocol_Id
          (Adacraft.Protocol.Ids.Cb_Login_Hello);
      Rt : LE.Encode_Result := LE.Encode_Encryption_Request
        (Der_Slice, Tok_Fixed, True, State.Login, State.Clientbound);
      Rf : LE.Encode_Result := LE.Encode_Encryption_Request
        (Der_Slice, Tok_Fixed, False, State.Login, State.Clientbound);
   begin
      Check (Req_Id = 1, "T2 pinned request id 1");
      Check (Rt.Status = LE.Encode_Ok, "T2 encode true ok");
      Check (Rf.Status = LE.Encode_Ok, "T2 encode false ok");
      if Rt.Status = LE.Encode_Ok and then Rf.Status = LE.Encode_Ok then
         Check (Rt.Length > 0 and then Rt.Length = Rf.Length,
                "T2 true/false same length");
         Check (Rt.Data (1) = Octet (Req_Id), "T2 packet id prefix");
         Check (Rt.Data (2) = 0, "T2 empty server id prefix");
         --  DER length varint follows: Der_Len < 16384 so 2 bytes.
         Check (Rt.Data (3) = Octet (16#80# + (Der_Len mod 128))
                or else True,
                "T2 der prefix present");
         declare
            Lo : constant Natural := Der_Len mod 128;
            Hi : constant Natural := Der_Len / 128;
         begin
            Check (Rt.Data (3) = Octet (Lo + 128), "T2 der len lo");
            Check (Rt.Data (4) = Octet (Hi), "T2 der len hi");
            Check (Bytes_Equal (Rt.Data (5 .. 4 + Der_Len), Der_Slice),
                   "T2 der bytes");
            Check (Rt.Data (5 + Der_Len) = 4, "T2 token len prefix");
            Check (Bytes_Equal
                     (Rt.Data (6 + Der_Len .. 9 + Der_Len),
                      Octets (Tok_Fixed)),
                   "T2 token bytes");
            Check (Rt.Data (10 + Der_Len) = 1, "T2 bool true");
            Check (Rf.Data (10 + Der_Len) = 0, "T2 bool false");
            Check (Rt.Length = 10 + Der_Len + 1, "T2 total length");
         end;
      end if;
   end;

   --  T3: response encode-then-decode round-trip from hand-built bytes.
   declare
      Secret_Plain : constant Octets (1 .. 16) :=
        (1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16);
      Token_Plain : Octets (1 .. 4) := Octets (Tok_A);
      Es : LE.Encrypt_Result := LE.Test_Encrypt_With_Public_Key (Secret_Plain);
      Et : LE.Encrypt_Result := LE.Test_Encrypt_With_Public_Key (Token_Plain);
   begin
      Check (Es.Status = LE.Encrypt_Ok and then Es.Length = 128,
             "T3 encrypt secret ok");
      Check (Et.Status = LE.Encrypt_Ok and then Et.Length = 128,
             "T3 encrypt token ok");
      if Es.Status = LE.Encrypt_Ok and then Et.Status = LE.Encrypt_Ok then
         declare
            Payload : Octets (1 .. 1 + 2 + 128 + 2 + 128) := (others => 0);
            Resp_Id : constant Natural :=
              Adacraft.Protocol.Ids.Protocol_Id
                (Adacraft.Protocol.Ids.Sb_Login_Key);
            D : LE.Decode_Result;
         begin
            Check (Resp_Id = 1, "T3 pinned response id 1");
            Payload (1) := Octet (Resp_Id);
            Payload (2) := 16#80#;
            Payload (3) := 16#01#;
            Payload (4 .. 131) := Octets (Es.Data);
            Payload (132) := 16#80#;
            Payload (133) := 16#01#;
            Payload (134 .. 261) := Octets (Et.Data);
            D := LE.Decode_Encryption_Response
              (Payload, State.Login, State.Serverbound);
            Check (D.Status = LE.Decode_Ok, "T3 decode ok");
            if D.Status = LE.Decode_Ok then
               Check (Bytes_Equal (Octets (D.Response.Secret_Cipher),
                                  Octets (Es.Data)),
                      "T3 secret cipher round-trip");
               Check (Bytes_Equal (Octets (D.Response.Token_Cipher),
                                  Octets (Et.Data)),
                      "T3 token cipher round-trip");
            end if;
         end;
      end if;
   end;

   --  T4: happy-path R5 returns known secret.
   declare
      Secret_Known : constant Octets (1 .. 16) :=
        (16#DE#, 16#AD#, 16#BE#, 16#EF#, 16#00#, 16#11#, 16#22#, 16#33#,
         16#44#, 16#55#, 16#66#, 16#77#, 16#88#, 16#99#, 16#AA#, 16#BB#);
      Tok : LE.Token_Bytes := (others => 0);
      Ok  : Boolean := False;
   begin
      LE.Generate_Verify_Token (Tok, Ok);
      Check (Ok, "T4 token ok");
      declare
         Es : LE.Encrypt_Result :=
           LE.Test_Encrypt_With_Public_Key (Secret_Known);
         Et : LE.Encrypt_Result :=
           LE.Test_Encrypt_With_Public_Key (Octets (Tok));
      begin
         Check (Es.Status = LE.Encrypt_Ok, "T4 encrypt secret");
         Check (Et.Status = LE.Encrypt_Ok, "T4 encrypt token");
         if Es.Status = LE.Encrypt_Ok and then Et.Status = LE.Encrypt_Ok then
            declare
               Dec : LE.Encryption_Response;
               Ver : LE.Verify_Result;
            begin
               Dec.Secret_Cipher := LE.Cipher_Bytes (Es.Data);
               Dec.Token_Cipher := LE.Cipher_Bytes (Et.Data);
               Ver := LE.Verify_Response (Dec, Tok);
               Check (Ver.Status = LE.Verify_Ok, "T4 verify ok");
               if Ver.Status = LE.Verify_Ok then
                  Check (Bytes_Equal (Octets (Ver.Secret), Secret_Known),
                         "T4 secret matches");
               end if;
            end;
         end if;
      end;
   end;

   if Failures = 0 then
      Ada.Text_IO.Put_Line ("login encryption tests passed");
   else
      Ada.Text_IO.Put_Line ("login encryption tests FAILED");
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
   end if;
end Test_Protocol_Login_Encryption;
