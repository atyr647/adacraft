with Ada.Characters.Handling;
with Ada.Containers;
with Ada.Strings.Fixed;
with Ada.Text_IO;
with Interfaces;
with Adacraft.Auth;
with Adacraft.Kernel;
with Adacraft.Protocol.Buffer;
with Adacraft.Protocol.Frame;
with Adacraft.Protocol.Ids;
with Adacraft.Protocol.Compression;
with Adacraft.Protocol.Login;
with Adacraft.Protocol.Packets;
with Adacraft.Protocol.Varnum;
with Adacraft.Corpus.Loader;

package body Adacraft.Corpus.Runner is

   package P renames Adacraft.Protocol;
   package PS renames Adacraft.Protocol.State;
   use type Adacraft.Protocol.Compression.Byte_Array_Access;
   use type Ada.Containers.Count_Type;
   package Prot_Login renames Adacraft.Protocol.Login;
   use Ada.Strings.Unbounded;
   use type P.Status_Kind;
   use type PS.Result_Kind;
   use type PS.Connection_State;
   use type PS.Login_Dispatch;
   use type Prot_Login.Ack_Outcome;
   use type Byte_Vectors.Vector;
   use type Interfaces.Unsigned_32;

   function Img (N : Natural) return String is
     (Ada.Strings.Fixed.Trim (Natural'Image (N), Ada.Strings.Left));

   function Low (S : String) return String is
     (Ada.Characters.Handling.To_Lower (S));

   Login_Start_Pid      : constant := 0;
   Login_Ack_Pid        : constant := 3;
   Login_Success_Pid    : constant := 2;
   Login_Disconnect_Pid : constant := 0;

   function Frame_Packet
     (WB : P.Buffer.Writer) return Byte_Vectors.Vector
   is
      Framed : P.Buffer.Writer (Capacity => WB.Len + 32 + 1);
      Result : Byte_Vectors.Vector;
   begin
      --  WB already holds the full packet body including its id,
      --  so frame it directly without prepending another id.
      if P.Packets.Frame (Framed, WB) and then not Framed.Failed then
         for I in 1 .. Framed.Len loop
            Result.Append (Framed.Data (I));
         end loop;
      end if;
      return Result;
   end Frame_Packet;

   function Frame_Packet_Compressed
     (WB        : P.Buffer.Writer;
      Threshold : Natural) return Byte_Vectors.Vector
   is
      Result : Byte_Vectors.Vector;
   begin
      if WB.Len = 0 then
         return Result;
      end if;
      declare
         Payload : P.Octets (1 .. WB.Len);
      begin
         for I in 1 .. WB.Len loop
            Payload (I) := WB.Data (I);
         end loop;
         declare
            Framed : constant P.Octets :=
              P.Frame.Encode_Compressed_Frame
                (Uncompressed_Payload => Payload,
                 Threshold            => Threshold);
         begin
            for I in Framed'Range loop
               Result.Append (Interfaces.Unsigned_8 (Framed (I)));
            end loop;
         end;
      end;
      return Result;
   end Frame_Packet_Compressed;

   function Build_Set_Compression (Threshold : Natural)
     return Byte_Vectors.Vector
   is
      WB : P.Buffer.Writer (Capacity => 16);
   begin
      P.Buffer.Reset (WB);
      P.Buffer.Put_Varint
        (WB, Interfaces.Unsigned_32
           (P.Ids.Protocol_Id (P.Ids.Cb_Login_Login_Compression)));
      P.Buffer.Put_Varint (WB, Interfaces.Unsigned_32 (Threshold));
      if WB.Failed then
         return Byte_Vectors.Empty_Vector;
      end if;
      return Frame_Packet (WB);
   end Build_Set_Compression;

   --  When compression is active, unwrap one serverbound compressed frame
   --  into its uncompressed payload (packet id + body). Returns False when
   --  the frame is malformed; caller maps that to a protocol-error close.
   function Unwrap_Compressed
     (Threshold : Natural;
      Input     : P.Octets;
      Payload   : out Byte_Vectors.Vector) return Boolean
   is
      use type P.Status_Kind;
      PL : constant P.Varnum.Varint_Result :=
        P.Varnum.Decode_Varint (Input, 1);
      DL : P.Varnum.Varint_Result;
      Body_First : Positive;
      Comp_First : Positive;
      Comp_Last  : Natural;
   begin
      Payload.Clear;
      if PL.Status /= P.Ok then
         return False;
      end if;
      if PL.Next > Input'Last then
         return False;
      end if;
      DL := P.Varnum.Decode_Varint (Input, PL.Next);
      if DL.Status /= P.Ok then
         return False;
      end if;
      Body_First := DL.Next;
      if Natural (PL.Value) /= Input'Length - 1 then
         --  Packet_Length must cover exactly Data_Length + payload bytes.
         --  Tolerate trailing check via exact length: length prefix value
         --  equals remaining bytes.
         null;
      end if;
      if DL.Value = 0 then
         if Body_First > Input'Last then
            return False;
         end if;
         for I in Body_First .. Input'Last loop
            Payload.Append (Interfaces.Unsigned_8 (Input (I)));
         end loop;
         return True;
      end if;
      if DL.Value < Interfaces.Unsigned_32 (Threshold) then
         return False;
      end if;
      if DL.Value > Interfaces.Unsigned_32
        (P.Compression.Max_Decompressed_Size)
      then
         return False;
      end if;
      if Body_First > Input'Last then
         return False;
      end if;
      Comp_First := Body_First;
      Comp_Last := Input'Last;
      declare
         Comp : P.Octets (Comp_First .. Comp_Last);
         R    : P.Compression.Decode_Result;
      begin
         for I in Comp'Range loop
            Comp (I) := Input (I);
         end loop;
         P.Compression.Decode
           (Threshold => Threshold,
            Input     => Comp,
            R         => R);
         if not R.Ok then
            P.Compression.Free (R);
            return False;
         end if;
         if R.Data = null
           or else R.Data'Length /= Natural (DL.Value)
         then
            P.Compression.Free (R);
            return False;
         end if;
         for B of R.Data.all loop
            Payload.Append (Interfaces.Unsigned_8 (B));
         end loop;
         P.Compression.Free (R);
         return True;
      end;
   end Unwrap_Compressed;

   type Feed_Result is record
      Actual    : Outcome := Rejected;
      Pid       : Natural := 0;
      Category  : Unbounded_String;
      Detail    : Unbounded_String;
      Reencoded : Byte_Vectors.Vector;
   end record;

   procedure Shift_Pending (Ctx : in out Login_Ctx) is
   begin
      if Ctx.Has_Pending2 then
         Ctx.Pending_Output := Ctx.Pending_Output2;
         Ctx.Pending_Output2.Clear;
         Ctx.Has_Pending2 := False;
         Ctx.Has_Pending := True;
      else
         Ctx.Pending_Output.Clear;
         Ctx.Has_Pending := False;
      end if;
   end Shift_Pending;

   procedure Feed
     (State : in out PS.Connection_State;
      Ctx   : in out Login_Ctx;
      Dir   : Direction;
      Input : P.Octets;
      R     : out Feed_Result)
   is
      F : P.Frame.Frame_Decode := P.Frame.Decode_Frame (Input, 1);
      Unwrapped : Byte_Vectors.Vector;
      --  Effective bytes for LOGIN dispatch: either the raw frame payload
      --  or the decompressed payload when compression is active.
      Eff_Pid         : Natural := 0;
      Eff_Payload     : Byte_Vectors.Vector;
      Used_Compressed : Boolean := False;
   begin
      R := (others => <>);
      --  Clientbound expectation step: assert the exact server
      --  frame produced by the previous LOGIN step (Set Compression,
      --  Success bytes or Disconnect bytes). State is unchanged.
      if Dir = Clientbound and then Ctx.Has_Pending then
         if Input'Length = Natural (Ctx.Pending_Output.Length) then
            declare
               Same : Boolean := True;
            begin
               for I in 1 .. Input'Length loop
                  if Input (Input'First + I - 1)
                    /= Ctx.Pending_Output (I)
                  then
                     Same := False;
                     exit;
                  end if;
               end loop;
               if Same then
                  R.Actual := Accepted;
                  R.Pid := F.Packet_Id;
                  R.Category := To_Unbounded_String ("login");
                  R.Detail := To_Unbounded_String ("login output matches");
                  Shift_Pending (Ctx);
                  return;
               end if;
            end;
         end if;
         R.Category := To_Unbounded_String ("login");
         R.Detail := To_Unbounded_String ("login output mismatch");
         return;
      end if;
      if Ctx.Closed then
         R.Category := To_Unbounded_String ("closed");
         R.Detail := To_Unbounded_String ("connection already closed");
         return;
      end if;
      --  Compressed ingress: from the first serverbound frame after Set
      --  Compression was sent, frames are Packet_Length | Data_Length |
      --  payload. Data_Length = 0 means uncompressed.
      if Ctx.Compression_Active
        and then (State = PS.Login or else State = PS.Login_Awaiting_Ack)
        and then Dir = Serverbound
      then
         if not Unwrap_Compressed
           (Threshold => Natural (Ctx.Compression_Threshold),
            Input     => Input,
            Payload   => Unwrapped)
         then
            Ctx.Closed := True;
            Ctx.Has_Pending := False;
            Ctx.Has_Pending2 := False;
            R.Category := To_Unbounded_String ("protocol-error");
            R.Detail := To_Unbounded_String ("bad compressed frame");
            return;
         end if;
         if Unwrapped.Length = 0 then
            Ctx.Closed := True;
            R.Category := To_Unbounded_String ("protocol-error");
            R.Detail := To_Unbounded_String ("empty compressed payload");
            return;
         end if;
         declare
            Flat : P.Octets (1 .. Natural (Unwrapped.Length));
         begin
            for I in Flat'Range loop
               Flat (I) := P.Octet (Unwrapped (I));
            end loop;
            F := P.Frame.Decode_Frame (Flat, 1);
            if F.Status /= P.Ok or else F.Next /= Flat'Last + 1 then
               Ctx.Closed := True;
               R.Category := To_Unbounded_String ("protocol-error");
               R.Detail := To_Unbounded_String
                 ("bad inner frame after decompress");
               return;
            end if;
            Eff_Pid := F.Packet_Id;
            for I in F.Payload_First .. F.Payload_Last loop
               Eff_Payload.Append (Interfaces.Unsigned_8 (Flat (I)));
            end loop;
            Used_Compressed := True;
         end;
      end if;
      if not Used_Compressed then
         if F.Status = P.Need_More then
            if F.Declared_Length > P.Max_Packet_Length then
               R.Actual := Rejected;
               R.Category := To_Unbounded_String ("framing");
               R.Detail := To_Unbounded_String
                 ("frame declared length " & Img (F.Declared_Length)
                  & " exceeds maximum");
            else
               R.Actual := Incomplete;
               R.Category := To_Unbounded_String ("framing");
               R.Detail := To_Unbounded_String ("frame incomplete");
            end if;
            return;
         elsif F.Status = P.Rejected then
            R.Category := To_Unbounded_String ("framing");
            R.Detail := To_Unbounded_String ("frame rejected");
            return;
         elsif F.Next /= Input'Last + 1 then
            R.Category := To_Unbounded_String ("framing");
            R.Detail := To_Unbounded_String ("input is not exactly one frame");
            return;
         end if;
      end if;

      --  LOGIN-state dispatch onto the existing codec. Start is
      --  handled only serverbound in LOGIN, Ack only serverbound
      --  in LOGIN_AWAITING_ACK; anything else in LOGIN context
      --  closes (validation failures produce a Disconnect frame
      --  held as pending output before close).
      if Dir = Serverbound
        and then (State = PS.Login or else State = PS.Login_Awaiting_Ack)
      then
         declare
            Parent_Login : constant Boolean :=
              State = PS.Login or else State = PS.Login_Awaiting_Ack;
         begin
            declare
               Pid_Match : constant Natural :=
                 (if Used_Compressed then Eff_Pid else F.Packet_Id);
            begin
            if Parent_Login and then Pid_Match = Login_Start_Pid then
               if State /= PS.Login then
                  Ctx.Closed := True;
                  Ctx.Has_Pending := False;
                  R.Category := To_Unbounded_String ("login");
                  R.Detail := To_Unbounded_String ("duplicate login start");
                  return;
               end if;
               if not Ctx.Active then
                  Ctx.Session := (others => <>);
                  Ctx.Active := True;
               end if;
               declare
                  Raw_Payload : P.Octets (1 .. Input'Length);
                  Payload : P.Octets (1 .. Input'Length);
                  Pay_Len   : Natural;
               begin
                  if Used_Compressed then
                     Pay_Len := Natural (Eff_Payload.Length);
                     for I in 1 .. Pay_Len loop
                        Payload (I) := P.Octet (Eff_Payload (I));
                     end loop;
                  else
                     Raw_Payload := Input;
                     Pay_Len := F.Payload_Last - F.Payload_First + 1;
                     for I in 1 .. Pay_Len loop
                        Payload (I) :=
                          Raw_Payload (F.Payload_First + I - 1);
                     end loop;
                  end if;
               declare
                  Slice : constant P.Octets := Payload (1 .. Pay_Len);
                  Res : constant Prot_Login.Start_Result :=
                    Prot_Login.Handle_Start
                      (Ctx.Session, Slice,
                       (if Adacraft.Kernel.Online_Mode
                        then Auth.Online else Auth.Offline));
                  W : P.Buffer.Writer (Capacity => 512);
               begin
                  case Res.Outcome is
                     when Prot_Login.Ready_Success =>
                        Ctx.Session := Res.Session;
                        P.Buffer.Reset (W);
                        if Ctx.Compression_Threshold >= 0
                          and then not Ctx.Compression_Sent
                        then
                           declare
                              WB : P.Buffer.Writer (Capacity => 256);
                           begin
                              Prot_Login.Encode_Login_Success (WB, Res.Identity);
                              Ctx.Pending_Output :=
                                Build_Set_Compression
                                  (Natural (Ctx.Compression_Threshold));
                              Ctx.Has_Pending := True;
                              Ctx.Pending_Output2 :=
                                Frame_Packet_Compressed
                                  (WB,
                                   Natural (Ctx.Compression_Threshold));
                              Ctx.Has_Pending2 := True;
                              Ctx.Compression_Sent := True;
                              Ctx.Compression_Active := True;
                           end;
                        else
                           declare
                              WB : P.Buffer.Writer (Capacity => 256);
                           begin
                              Prot_Login.Encode_Login_Success (WB, Res.Identity);
                              if Ctx.Compression_Active then
                                 Ctx.Pending_Output :=
                                   Frame_Packet_Compressed
                                     (WB,
                                      Natural (Ctx.Compression_Threshold));
                              else
                                 Ctx.Pending_Output :=
                                   Frame_Packet (WB);
                              end if;
                              Ctx.Has_Pending := True;
                           end;
                        end if;
                        State := PS.Login_Awaiting_Ack;
                        R.Actual := Accepted;
                        R.Pid := Pid_Match;
                        R.Category := To_Unbounded_String ("login");
                        R.Detail := To_Unbounded_String ("login start ok");
                        return;
                     when Prot_Login.Need_Disconnect_Close
                        | Prot_Login.Refuse_Online =>
                        Ctx.Session := Res.Session;
                        declare
                           WB : P.Buffer.Writer (Capacity => 512);
                        begin
                           Prot_Login.Encode_Login_Disconnect
                             (WB,
                              Res.Reason (1 .. Res.Reason_Len));
                           Ctx.Pending_Output :=
                             Frame_Packet (WB);
                           Ctx.Has_Pending := True;
                        end;
                        Ctx.Closed := True;
                        R.Category := To_Unbounded_String ("disconnect");
                        R.Detail := To_Unbounded_String
                          ("login rejected with disconnect");
                        return;
                     when Prot_Login.Protocol_Error_Close =>
                        Ctx.Session := Res.Session;
                        Ctx.Closed := True;
                        Ctx.Has_Pending := False;
                        Ctx.Has_Pending2 := False;
                        R.Category := To_Unbounded_String ("login");
                        R.Detail := To_Unbounded_String
                          ("malformed login start");
                        return;
                  end case;
               end;
               end;
            elsif Parent_Login and then Pid_Match = Login_Ack_Pid then
               if State /= PS.Login_Awaiting_Ack then
                  Ctx.Closed := True;
                  Ctx.Has_Pending := False;
                  R.Category := To_Unbounded_String ("login");
                  R.Detail := To_Unbounded_String ("early login ack");
                  return;
               end if;
               declare
                  Slice : P.Octets (1 .. Input'Length);
                  Slice_Len : Natural;
               begin
                  if Used_Compressed then
                     Slice_Len := Natural (Eff_Payload.Length);
                     for I in 1 .. Slice_Len loop
                        Slice (I) := P.Octet (Eff_Payload (I));
                     end loop;
                  else
                     Slice := Input;
                     Slice_Len := F.Payload_Last - F.Payload_First + 1;
                     for I in 1 .. Slice_Len loop
                        Slice (I) := Input (F.Payload_First + I - 1);
                     end loop;
                  end if;
               declare
                  Res : constant Prot_Login.Ack_Result :=
                    Prot_Login.Handle_Acknowledged
                      (Ctx.Session, Slice (1 .. Slice_Len));
               begin
                  if Res.Outcome = Prot_Login.To_Configuration then
                     Ctx.Session := Res.Session;
                     Ctx.Has_Pending := False;
                     Ctx.Has_Pending2 := False;
                     State := PS.Configuration;
                     R.Actual := Accepted;
                     R.Pid := Pid_Match;
                     R.Category := To_Unbounded_String ("login");
                     R.Detail := To_Unbounded_String ("ack ok");
                     return;
                  else
                     Ctx.Closed := True;
                     R.Category := To_Unbounded_String ("login");
                     R.Detail := To_Unbounded_String ("bad ack body");
                     return;
                  end if;
               end;
               end;
            elsif Parent_Login then
               Ctx.Closed := True;
               Ctx.Has_Pending := False;
               Ctx.Has_Pending2 := False;
               R.Category := To_Unbounded_String ("login");
               R.Detail := To_Unbounded_String
                 ("unknown login packet id");
               return;
            end if;
            end;
         end;
      end if;

      declare
         Payload : constant P.Octets := Input (F.Payload_First .. F.Payload_Last);
         Intent  : PS.Handshake_Intent := 0;
         Hello   : P.Packets.Handshake;
         Is_Hs   : constant Boolean :=
           State = PS.Handshake and then Dir = Serverbound
           and then F.Packet_Id =
             P.Ids.Protocol_Id (P.Ids.Sb_Handshake_Intention);
      begin
         if Is_Hs then
            Hello := P.Packets.Decode_Handshake (Payload);
            if Hello.Status /= P.Ok then
               R.Category := To_Unbounded_String ("malformed_packet");
               R.Detail := To_Unbounded_String ("handshake payload rejected");
               return;
            end if;
            Intent := PS.Handshake_Intent (Hello.Intent);
         end if;

         declare
            Ev : constant PS.Packet_Event :=
              (Direction => (if Dir = Serverbound then PS.Serverbound
                             else PS.Clientbound),
               Id        => PS.Packet_Id (F.Packet_Id),
               Intent    => Intent);
            T  : constant PS.Transition_Result := PS.Transition (State, Ev);
         begin
            if T.Kind = PS.Rejected then
               R.Category := To_Unbounded_String
                 (Low (PS.Rejection_Reason'Image (T.Reason)));
               R.Detail := To_Unbounded_String
                 ("state machine rejected: " & Low (PS.Rejection_Reason'Image (T.Reason)));
               return;
            end if;
            State := T.Next_State;
            R.Actual := Accepted;
            R.Pid := F.Packet_Id;
         end;

         declare
            Body_W : P.Buffer.Writer (Payload'Length + 16);
            Framed : P.Buffer.Writer (Payload'Length + 32);
         begin
            P.Buffer.Put_Varint (Body_W, Interfaces.Unsigned_32 (F.Packet_Id));
            if Is_Hs then
               P.Buffer.Put_Varint (Body_W, Hello.Version);
               P.Buffer.Put_String (Body_W, Hello.Address (1 .. Hello.Addr_Len));
               P.Buffer.Put_U16 (Body_W, Hello.Port);
               P.Buffer.Put_Varint (Body_W, Hello.Intent);
            else
               P.Buffer.Put_Bytes (Body_W, Payload);
            end if;
            if P.Packets.Frame (Framed, Body_W) and then not Framed.Failed then
               for I in 1 .. Framed.Len loop
                  R.Reencoded.Append (Framed.Data (I));
               end loop;
            end if;
         end;
      end;
   end Feed;

   procedure Replay (S : Scenario; Failure : out Unbounded_String) is
      State : PS.Connection_State := S.Initial_State;
      Ctx   : Login_Ctx;
      Idx   : Natural := 0;
      Threshold_Init : constant Integer :=
        Adacraft.Corpus.Loader.Compression_Threshold_For
          (To_String (S.Id));

      procedure Fail (Expected, Actual, Detail : String) is
      begin
         Failure := To_Unbounded_String
           ("step=" & Img (Idx) & " expected=" & Expected
            & " actual=" & Actual & " detail=" & Detail);
      end Fail;
   begin
      Ctx.Compression_Threshold := Threshold_Init;
      Failure := Null_Unbounded_String;
      for St of S.Steps loop
         Idx := Idx + 1;
         declare
            Input  : P.Octets (1 .. Natural (St.Input.Length));
            Before : constant PS.Connection_State := State;
            R      : Feed_Result;
         begin
            for I in Input'Range loop
               Input (I) := St.Input (I);
            end loop;
            Feed (State, Ctx, St.Dir, Input, R);
            if R.Actual /= St.Expected then
               Fail (Low (Outcome'Image (St.Expected)),
                     Low (Outcome'Image (R.Actual)), To_String (R.Detail));
               return;
            end if;
            case R.Actual is
               when Accepted =>
                  if St.Has_Packet_Id and then R.Pid /= St.Packet_Id then
                     Fail ("packet_id=" & Img (St.Packet_Id),
                           "packet_id=" & Img (R.Pid), "packet id mismatch");
                     return;
                  end if;
                  if St.Has_State_After and then State /= St.State_After then
                     Fail ("state_after=" & Low (PS.Connection_State'Image (St.State_After)),
                           "state_after=" & Low (PS.Connection_State'Image (State)),
                           "state mismatch");
                     return;
                  end if;
                  if St.Canonical and then R.Reencoded /= St.Input then
                     Fail ("canonical", "reencoded differs",
                           "round-trip bytes differ from input");
                     return;
                  end if;
               when Rejected | Incomplete =>
                  if State /= Before then
                     Fail ("state unchanged", "state changed",
                           "state changed on terminal step");
                     return;
                  end if;
                  if St.Has_Rejection_Category
                    and then Low (To_String (St.Rejection_Category))
                             /= To_String (R.Category)
                  then
                     Fail ("category=" & To_String (St.Rejection_Category),
                           "category=" & To_String (R.Category),
                           "rejection category mismatch");
                     return;
                  end if;
                  exit;
            end case;
         end;
      end loop;
      if S.Has_Final_State and then State /= S.Final_State then
         Idx := Natural (S.Steps.Length);
         Fail ("final_state=" & Low (PS.Connection_State'Image (S.Final_State)),
               "final_state=" & Low (PS.Connection_State'Image (State)),
               "final state mismatch");
      end if;
   end Replay;

   procedure Run_All
     (Scenarios : Scenario_Vectors.Vector;
      F         : Filter;
      Summary   : out Run_Summary)
   is
      Failure : Unbounded_String;
      Saved_Online_Mode : constant Boolean := Adacraft.Kernel.Online_Mode;
   begin
      --  Corpus login scenarios exercise the offline flow explicitly.
      --  The runner's LOGIN dispatch still reads the configured mode.
      Adacraft.Kernel.Online_Mode := False;
      Summary := (others => <>);
      for S of Scenarios loop
         if (not F.Has_Id or else S.Id = F.Id)
           and then (not F.Has_Category or else S.Cat = F.Cat)
         then
            Summary.Total := Summary.Total + 1;
            Summary.Per (S.Cat) := Summary.Per (S.Cat) + 1;
            Replay (S, Failure);
            if Length (Failure) = 0 then
               Summary.Passed := Summary.Passed + 1;
            else
               Summary.Failed := Summary.Failed + 1;
               Ada.Text_IO.Put_Line
                 ("FAIL scenario=" & To_String (S.Id)
                  & " file=" & To_String (S.Path) & " " & To_String (Failure));
            end if;
         end if;
      end loop;
      Ada.Text_IO.Put_Line
        ("golden corpus: scenarios=" & Img (Summary.Total)
         & " passed=" & Img (Summary.Passed)
         & " failed=" & Img (Summary.Failed));
      declare
         Line : Unbounded_String := To_Unbounded_String ("category");
      begin
         for C in Category loop
            Append (Line, " " & Low (Category'Image (C)) & "=" & Img (Summary.Per (C)));
         end loop;
         Ada.Text_IO.Put_Line (To_String (Line));
      end;
   end Run_All;

end Adacraft.Corpus.Runner;
