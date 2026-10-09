with Ada.Streams;
with Ada.Text_IO;
with Adacraft.Auth;
with Adacraft.Protocol;
with Adacraft.Protocol.Buffer;
with Adacraft.Protocol.Frame;
with Adacraft.Protocol.Login;
with Adacraft.Protocol.Varnum;

procedure Test_Protocol_Login is
   package L renames Adacraft.Protocol.Login;
   package Auth renames Adacraft.Auth;
   package Protocol renames Adacraft.Protocol;
   package Varnum renames Adacraft.Protocol.Varnum;
   package Frame renames Adacraft.Protocol.Frame;
   use type L.Login_Start_Status;
   use type L.Start_Outcome;
   use type L.Ack_Outcome;
   use type L.Login_State;
   use type Auth.Server_Auth_Mode;
   use type Auth.Identity_Kind;
   use type Auth.Digest;
   use type Protocol.Octet;
   use type Protocol.Octets;
   use type Interfaces.Unsigned_8;
   use type Interfaces.Unsigned_32;
   use type Frame.Encode_Status;
   use type Ada.Streams.Stream_Element_Offset;

   Failures : Natural := 0;

   procedure Check (Cond : Boolean; Name : String) is
   begin
      if not Cond then
         Failures := Failures + 1;
         Ada.Text_IO.Put_Line ("FAIL login: " & Name);
      end if;
   end Check;

   function Hex (D : Auth.Digest) return String is
      Map : constant String := "0123456789abcdef";
      Image : String (1 .. 32);
   begin
      for I in D'Range loop
         Image (I * 2 - 1) := Map (Natural (D (I)) / 16 + 1);
         Image (I * 2) := Map (Natural (D (I)) mod 16 + 1);
      end loop;
      return Image;
   end Hex;

   function Same_Octets (A, B : Protocol.Octets) return Boolean is
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
   end Same_Octets;

   Dummy_Uuid : constant Protocol.Octets (1 .. 16) :=
     (16#01#, 16#02#, 16#03#, 16#04#, 16#05#, 16#06#, 16#07#, 16#08#,
      16#09#, 16#0A#, 16#0B#, 16#0C#, 16#0D#, 16#0E#, 16#0F#, 16#10#);

   function Build_Start (Name : String; Uuid : Protocol.Octets) return Protocol.Octets is
      W : Protocol.Buffer.Writer (64);
   begin
      Protocol.Buffer.Put_String (W, Name);
      Protocol.Buffer.Put_Bytes (W, Uuid);
      declare
         R : Protocol.Octets (1 .. W.Len);
      begin
         for I in 1 .. W.Len loop
            R (I) := W.Data (I);
         end loop;
         return R;
      end;
   end Build_Start;

   function Slice (A : Protocol.Octets; Last : Natural) return Protocol.Octets is
      R : Protocol.Octets (1 .. Last - A'First + 1);
   begin
      for I in A'First .. Last loop
         R (I - A'First + 1) := A (I);
      end loop;
      return R;
   end Slice;

   function With_Trailing (A : Protocol.Octets) return Protocol.Octets is
      R : Protocol.Octets (1 .. A'Length + 1);
   begin
      for I in 1 .. A'Length loop
         R (I) := A (A'First + I - 1);
      end loop;
      R (R'Last) := 0;
      return R;
   end With_Trailing;

   function Fresh_Session return L.Login_Session is
      S : L.Login_Session;
   begin
      return S;
   end Fresh_Session;
begin
   --  T-1: name validation, lengths 1/16 pass, 0/17 fail, space/control fail.
   Check (L.Is_Valid_Name ("a"), "T-1 len 1 pass");
   Check (L.Is_Valid_Name ("0123456789ABCDEF"), "T-1 len 16 pass");
   Check (not L.Is_Valid_Name (""), "T-1 len 0 fail");
   Check (not L.Is_Valid_Name ("0123456789ABCDEFG"), "T-1 len 17 fail");
   Check (not L.Is_Valid_Name ("has space"), "T-1 space fail");
   Check (not L.Is_Valid_Name ("ab" & Character'Val (1) & "cd"), "T-1 control fail");
   Check (not L.Is_Valid_Name ("ab" & Character'Val (16#7F#)), "T-1 DEL fail");
   Check (not L.Is_Valid_Name ("ab" & Character'Val (128)), "T-1 >=0x7F fail");
   Check (L.Is_Valid_Name ("!~"), "T-1 21-7E pass");

   declare
      P : constant Protocol.Octets := Build_Start ("Notch", Dummy_Uuid);
      D : constant L.Login_Start := L.Decode_Login_Start (P);
   begin
      Check (D.Status = L.Ok, "T-1 valid decode ok");
      Check (D.Name_Len = 5 and then D.Name (1 .. 5) = "Notch", "T-1 valid name");
      Check (Same_Octets (D.Client_Uuid, Dummy_Uuid), "T-1 client uuid read");
   end;

   declare
      P1 : constant Protocol.Octets := Build_Start ("a", Dummy_Uuid);
      D1 : constant L.Login_Start := L.Decode_Login_Start (P1);
      P16 : constant Protocol.Octets := Build_Start ("0123456789ABCDEF", Dummy_Uuid);
      D16 : constant L.Login_Start := L.Decode_Login_Start (P16);
   begin
      Check (D1.Status = L.Ok, "T-1 decode len 1 ok");
      Check (D16.Status = L.Ok, "T-1 decode len 16 ok");
   end;

   declare
      P0 : constant Protocol.Octets := Build_Start ("", Dummy_Uuid);
      D0 : constant L.Login_Start := L.Decode_Login_Start (P0);
      P17 : constant Protocol.Octets := Build_Start ("0123456789ABCDEFG", Dummy_Uuid);
      D17 : constant L.Login_Start := L.Decode_Login_Start (P17);
      PS : constant Protocol.Octets := Build_Start ("has space", Dummy_Uuid);
      DS : constant L.Login_Start := L.Decode_Login_Start (PS);
      PC : constant Protocol.Octets :=
        Build_Start ("ab" & Character'Val (1) & "cd", Dummy_Uuid);
      DC : constant L.Login_Start := L.Decode_Login_Start (PC);
   begin
      Check (D0.Status /= L.Ok, "T-1 decode len 0 reject");
      Check (D17.Status = L.Malformed, "T-1 decode len 17 malformed");
      Check (DS.Status = L.Invalid_Name, "T-1 decode space invalid");
      Check (DC.Status = L.Invalid_Name, "T-1 decode control invalid");
   end;

   --  T-1b: truncation / over-long prefix / trailing bytes fail.
   declare
      P : constant Protocol.Octets := Build_Start ("Notch", Dummy_Uuid);
      Trunc : constant Protocol.Octets := Slice (P, P'Last - 1);
      DT : constant L.Login_Start := L.Decode_Login_Start (Trunc);
      Trail : constant Protocol.Octets := With_Trailing (P);
      DTr : constant L.Login_Start := L.Decode_Login_Start (Trail);
      Over : constant Protocol.Octets (1 .. 19) :=
        (16#14#, 16#61#, 16#62#,
         16#01#, 16#02#, 16#03#, 16#04#, 16#05#, 16#06#, 16#07#, 16#08#,
         16#09#, 16#0A#, 16#0B#, 16#0C#, 16#0D#, 16#0E#, 16#0F#, 16#10#);
      DOv : constant L.Login_Start := L.Decode_Login_Start (Over);
      DE : constant L.Login_Start :=
        L.Decode_Login_Start ((1 => 0));
   begin
      Check (DT.Status = L.Malformed, "T-1 truncation malformed");
      Check (DTr.Status = L.Malformed, "T-1 trailing malformed");
      Check (DOv.Status = L.Malformed, "T-1 overlong prefix malformed");
      Check (DE.Status = L.Malformed, "T-1 empty payload malformed");
   end;

   --  T-2: offline UUID KAVs + determinism + version/variant nibbles.
   declare
      N1 : constant Auth.Digest := L.Offline_UUID ("Notch");
      N2 : constant Auth.Digest := L.Offline_UUID ("Notch");
      S1 : constant Auth.Digest := L.Offline_UUID ("Steve");
   begin
      Check (Hex (N1) = "b50ad385829d3141a2167e7d7539ba7f", "T-2 KAV Notch");
      Check (Hex (S1) = "5627dd98e6be3c21b8a8e92344183641", "T-2 KAV Steve");
      Check (N1 = N2, "T-2 determinism");
      Check (N1 /= S1, "T-2 distinct names distinct uuid");
      Check ((N1 (7) / 16) = 3, "T-2 version nibble 3 Notch");
      Check ((S1 (7) / 16) = 3, "T-2 version nibble 3 Steve");
      Check (((N1 (9)) and 192) = 128, "T-2 variant Notch");
      Check (((S1 (9)) and 192) = 128, "T-2 variant Steve");
   end;

   declare
      Id : constant Auth.Player_Identity := L.Offline_Identity ("Notch");
   begin
      Check (Id.Kind = Auth.Offline, "T-2 identity marked offline");
      Check (Hex (Id.UUID) = "b50ad385829d3141a2167e7d7539ba7f", "T-2 identity uuid");
      Check (Id.Name_Length = 5, "T-2 identity name len");
   end;

   --  T-3: byte-exact Login Success.
   declare
      Id : constant Auth.Player_Identity := L.Offline_Identity ("Notch");
      W : Protocol.Buffer.Writer (64);
      U : constant Auth.Digest := Id.UUID;
      Expected : constant Protocol.Octets (1 .. 24) :=
        (16#02#,
         U (1), U (2), U (3), U (4), U (5), U (6), U (7), U (8),
         U (9), U (10), U (11), U (12), U (13), U (14), U (15), U (16),
         16#05#, 16#4E#, 16#6F#, 16#74#, 16#63#, 16#68#, 16#00#);
      Got : Protocol.Octets (1 .. 24);
   begin
      L.Encode_Login_Success (W, Id);
      Check (not W.Failed, "T-3 encode no fail");
      Check (W.Len = Expected'Length, "T-3 success length");
      for I in 1 .. W.Len loop
         Got (I) := W.Data (I);
      end loop;
      Check (Same_Octets (Got, Expected), "T-3 byte-exact success");
   end;

   --  T-4: Start -> Success -> Ack -> CONFIGURATION.
   declare
      P : constant Protocol.Octets := Build_Start ("Notch", Dummy_Uuid);
      R : constant L.Start_Result :=
        L.Handle_Start (Fresh_Session, P, Auth.Offline);
      A : L.Ack_Result;
      Empty : constant Protocol.Octets (1 .. 0) := (others => 0);
   begin
      Check (R.Outcome = L.Ready_Success, "T-4 start ready");
      Check (R.Session.State = L.Success_Sent, "T-4 stays LOGIN success-sent");
      Check (R.Session.Success_Sent, "T-4 success flag");
      Check (R.Session.Has_Identity, "T-4 has identity");
      Check (Hex (R.Identity.UUID) = "b50ad385829d3141a2167e7d7539ba7f",
        "T-4 offline uuid used not client uuid");
      Check (Hex (R.Identity.UUID) /= "0102030405060708090a0b0c0d0e0f10",
        "T-4 client uuid never identity");
      A := L.Handle_Acknowledged (R.Session, Empty);
      Check (A.Outcome = L.To_Configuration, "T-4 ack to configuration");
      Check (A.Session.State = L.Configuration, "T-4 configuration state");
      declare
         R2 : constant L.Start_Result :=
           L.Handle_Start (A.Session, P, Auth.Offline);
      begin
         Check (R2.Outcome = L.Protocol_Error_Close, "T-4 login after transition refused");
         Check (R2.Session.State = L.Closed, "T-4 post-transition closed");
         Check (not R2.Session.Has_Identity, "T-4 post-transition no identity");
      end;
   end;

   --  T-4b: FR-5 closes leave no identity and not CONFIGURATION.
   declare
      Bad_Name : constant Protocol.Octets := Build_Start ("has space", Dummy_Uuid);
      RB : constant L.Start_Result :=
        L.Handle_Start (Fresh_Session, Bad_Name, Auth.Offline);
      P : constant Protocol.Octets := Build_Start ("Notch", Dummy_Uuid);
      Trunc : constant Protocol.Octets := Slice (P, P'Last - 1);
      RM : constant L.Start_Result :=
        L.Handle_Start (Fresh_Session, Trunc, Auth.Offline);
      Empty : constant Protocol.Octets (1 .. 0) := (others => 0);
      RE : constant L.Ack_Result :=
        L.Handle_Acknowledged (Fresh_Session, Empty);
      R1 : constant L.Start_Result :=
        L.Handle_Start (Fresh_Session, P, Auth.Offline);
      RD : constant L.Start_Result :=
        L.Handle_Start (R1.Session, P, Auth.Offline);
      RN : constant L.Ack_Result :=
        L.Handle_Acknowledged (R1.Session, P (1 .. 1));
   begin
      Check (RB.Outcome = L.Need_Disconnect_Close, "T-4 invalid name disconnect-close");
      Check (RB.Session.State = L.Closed, "T-4 invalid name closed");
      Check (not RB.Session.Has_Identity, "T-4 invalid name no identity");
      Check (RB.Reason_Len > 0, "T-4 invalid name reason");
      Check (RM.Outcome = L.Need_Disconnect_Close, "T-4 malformed disconnect-close");
      Check (RM.Session.State = L.Closed, "T-4 malformed closed");
      Check (not RM.Session.Has_Identity, "T-4 malformed no identity");
      Check (RE.Outcome = L.Protocol_Error_Close, "T-4 early ack closes");
      Check (RE.Session.State = L.Closed, "T-4 early ack closed");
      Check (not RE.Session.Has_Identity, "T-4 early ack no identity");
      Check (RD.Outcome = L.Protocol_Error_Close, "T-4 duplicate start closes");
      Check (RD.Session.State = L.Closed, "T-4 duplicate closed");
      Check (not RD.Session.Has_Identity, "T-4 duplicate no identity");
      Check (RN.Outcome = L.Protocol_Error_Close, "T-4 non-empty ack closes");
      Check (RN.Session.State = L.Closed, "T-4 non-empty ack closed");
   end;

   --  T-5: online-mode refusal sends Disconnect reason, never Success.
   declare
      P : constant Protocol.Octets := Build_Start ("Notch", Dummy_Uuid);
      R : constant L.Start_Result :=
        L.Handle_Start (Fresh_Session, P, Auth.Online);
      W : Protocol.Buffer.Writer (256);
   begin
      Check (R.Outcome = L.Refuse_Online, "T-5 online refusal");
      Check (R.Session.State = L.Closed, "T-5 online closed");
      Check (not R.Session.Has_Identity, "T-5 online no identity");
      Check (R.Reason_Len > 0, "T-5 online reason present");
      declare
         Got : String (1 .. R.Reason_Len);
      begin
         for I in 1 .. R.Reason_Len loop
            Got (I) := R.Reason (I);
         end loop;
         Check (Got = L.Online_Not_Yet_Supported_Reason, "T-5 not-yet-supported reason");
      end;
      L.Encode_Login_Disconnect
        (W, L.Online_Not_Yet_Supported_Reason);
      Check (not W.Failed and then W.Len > 0, "T-5 disconnect encodable");
      Check (W.Data (1) = 16#00#, "T-5 disconnect id 0");
   end;

   --  T-6: single Build_Login_Disconnect builder (VarInt id 0x00 S->C
   --  plus VarInt string-len plus UTF-8 TextComponent JSON).
   declare
      use type Protocol.Status_Kind;
      Built : constant Protocol.Octets :=
        L.Build_Login_Disconnect;
      Def   : constant Protocol.Octets :=
        L.Build_Login_Disconnect (L.Default_Disconnect_Reason);
      W     : Protocol.Buffer.Writer (512);
      V     : Varnum.Varint_Result;
      F     : Frame.Frame_Decode;
      JSON  : constant String :=
        "{""text"":""" & L.Default_Disconnect_Reason & """}";
   begin
      Check (Built'Length = Def'Length, "T-6 default reason");
      Check (Built'Length > 2, "T-6 disconnect non-empty");
      --  Packet-ID decodes via the one VarInt.
      V := Varnum.Decode_Varint (Built, Built'First);
      Check (V.Status = Protocol.Ok, "T-6 varint ok");
      Check (V.Value = 0, "T-6 packet id 0");
      --  Body matches the one Writer-based encoder, no ad-hoc copy.
      L.Encode_Login_Disconnect (W, L.Default_Disconnect_Reason);
      Check (not W.Failed, "T-6 encode no fail");
      Check (W.Len = Built'Length, "T-6 builder matches encoder");
      declare
         Same : Boolean := W.Len = Built'Length;
      begin
         for I in 1 .. W.Len loop
            if W.Data (I) /= Built (Built'First + I - 1) then
               Same := False;
            end if;
         end loop;
         Check (Same, "T-6 builder bytes match encoder");
      end;
      --  String-len + JSON text component decodes via Buffer.
      declare
         Dec : constant Protocol.Buffer.String_Decode :=
           Protocol.Buffer.Decode_String (Built, V.Next, 32767);
      begin
         Check (Dec.Status = Protocol.Ok, "T-6 reason string ok");
         Check (Dec.Length = JSON'Length, "T-6 reason len");
         Check (Dec.Text (1 .. Dec.Length) = JSON, "T-6 reason json");
      end;
      --  Frame decoder agrees on the framed disconnect body.
      declare
         Payload : Ada.Streams.Stream_Element_Array
           (Ada.Streams.Stream_Element_Offset (Built'First)
            .. Ada.Streams.Stream_Element_Offset (Built'Last));
         Out_Buf : Frame.Byte_Array (1 .. 1024);
         Last    : Ada.Streams.Stream_Element_Offset;
         Status  : Frame.Encode_Status;
         Wire    : Protocol.Octets (1 .. 1024);
         Wire_Len : Natural;
      begin
         for I in Built'Range loop
            Payload (Ada.Streams.Stream_Element_Offset (I)) :=
              Ada.Streams.Stream_Element (Built (I));
         end loop;
         Frame.Encode (Payload, Out_Buf, Last, Status);
         Check (Status = Frame.Ok, "T-6 frame encode ok");
         Wire_Len := Natural (Last - Out_Buf'First + 1);
         for I in 1 .. Wire_Len loop
            Wire (I) := Protocol.Octet (Out_Buf (Out_Buf'First
              + Ada.Streams.Stream_Element_Offset (I) - 1));
         end loop;
         F := Frame.Decode_Frame (Wire (1 .. Wire_Len), 1);
         Check (F.Status = Protocol.Ok, "T-6 frame decode ok");
         Check (F.Packet_Id = 0, "T-6 frame packet id 0");
      end;
      --  Custom reason path uses the same single builder.
      declare
         Custom : constant Protocol.Octets :=
           L.Build_Login_Disconnect ("invalid name");
         Vc : Varnum.Varint_Result;
      begin
         Vc := Varnum.Decode_Varint (Custom, Custom'First);
         Check (Vc.Status = Protocol.Ok and then Vc.Value = 0,
           "T-6 custom id 0");
         Check (Custom'Length > 2, "T-6 custom non-empty");
      end;
   end;

   if Failures = 0 then
      Ada.Text_IO.Put_Line ("protocol login tests passed");
   else
      Ada.Text_IO.Put_Line ("protocol login tests failed");
      raise Program_Error with "protocol login tests failed";
   end if;
end Test_Protocol_Login;
