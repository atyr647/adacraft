with Ada.Command_Line;
with Ada.Text_IO;
with Ada.Unchecked_Conversion;
with Interfaces;
with Adacraft.Protocol;
with Adacraft.Protocol.Varnum;
with Adacraft.Protocol.Packet_Decoder;

procedure Test_Protocol_Packet_Decoder is
   package V renames Adacraft.Protocol.Varnum;
   package D renames Adacraft.Protocol.Packet_Decoder;
   use Adacraft.Protocol;
   use type Interfaces.Integer_8;
   use type Interfaces.Integer_16;
   use type Interfaces.Integer_32;
   use type Interfaces.Integer_64;
   use type Interfaces.Unsigned_8;
   use type Interfaces.Unsigned_16;
   use type Interfaces.Unsigned_32;
   use type Interfaces.Unsigned_64;
   use type V.Status_Type;
   use type D.Decode_Status;
   use type D.Field_Kind;

   Failures : Natural := 0;

   procedure Check (Condition : Boolean; Name : String) is
   begin
      if not Condition then
         Failures := Failures + 1;
         Ada.Text_IO.Put_Line ("FAIL: " & Name);
      end if;
   end Check;

   type Field_Array_Access is access D.Field_Array;

   --  Scratch buffer for building payloads (heap to avoid stack pressure).
   type Scratch_Access is access Octets;

   procedure Append_VarInt
     (Value : Interfaces.Integer_32;
      Buf   : in out Octets;
      Pos   : in out Positive)
   is
      Tmp : Octets (1 .. 5) := [others => 0];
      W   : Natural := 0;
      S   : V.Status_Type;
   begin
      V.Encode (Value, Tmp, 1, W, S);
      if S /= V.Ok then
         Check (False, "helper Append_VarInt encode ok");
         return;
      end if;
      for I in 1 .. W loop
         Buf (Pos) := Tmp (I);
         Pos := Pos + 1;
      end loop;
   end Append_VarInt;

   procedure Append_VarLong
     (Value : Interfaces.Integer_64;
      Buf   : in out Octets;
      Pos   : in out Positive)
   is
      Tmp : Octets (1 .. 10) := [others => 0];
      W   : Natural := 0;
      S   : V.Status_Type;
   begin
      V.Encode_Varlong (Value, Tmp, 1, W, S);
      if S /= V.Ok then
         Check (False, "helper Append_VarLong encode ok");
         return;
      end if;
      for I in 1 .. W loop
         Buf (Pos) := Tmp (I);
         Pos := Pos + 1;
      end loop;
   end Append_VarLong;

   procedure Append_Byte (Buf : in out Octets; Pos : in out Positive; B : Octet) is
   begin
      Buf (Pos) := B;
      Pos := Pos + 1;
   end Append_Byte;

   procedure Append_U16BE (Buf : in out Octets; Pos : in out Positive; U : Interfaces.Unsigned_16) is
   begin
      Buf (Pos) := Octet (Interfaces.Shift_Right (U, 8) and 16#FF#);
      Buf (Pos + 1) := Octet (U and 16#FF#);
      Pos := Pos + 2;
   end Append_U16BE;

   procedure Append_U32BE (Buf : in out Octets; Pos : in out Positive; U : Interfaces.Unsigned_32) is
   begin
      for I in 0 .. 3 loop
         Buf (Pos + I) :=
           Octet (Interfaces.Shift_Right (U, (3 - I) * 8) and 16#FF#);
      end loop;
      Pos := Pos + 4;
   end Append_U32BE;

   procedure Append_U64BE (Buf : in out Octets; Pos : in out Positive; U : Interfaces.Unsigned_64) is
   begin
      for I in 0 .. 7 loop
         Buf (Pos + I) :=
           Octet (Interfaces.Shift_Right (U, (7 - I) * 8) and 16#FF#);
      end loop;
      Pos := Pos + 8;
   end Append_U64BE;

   function To_U16 (V : Interfaces.Integer_16) return Interfaces.Unsigned_16 is
      function C is new Ada.Unchecked_Conversion
        (Interfaces.Integer_16, Interfaces.Unsigned_16);
   begin
      return C (V);
   end To_U16;

   function To_U32 (V : Interfaces.Integer_32) return Interfaces.Unsigned_32 is
      function C is new Ada.Unchecked_Conversion
        (Interfaces.Integer_32, Interfaces.Unsigned_32);
   begin
      return C (V);
   end To_U32;

   function To_U64 (V : Interfaces.Integer_64) return Interfaces.Unsigned_64 is
      function C is new Ada.Unchecked_Conversion
        (Interfaces.Integer_64, Interfaces.Unsigned_64);
   begin
      return C (V);
   end To_U64;

   function To_U8 (V : Interfaces.Integer_8) return Interfaces.Unsigned_8 is
      function C is new Ada.Unchecked_Conversion
        (Interfaces.Integer_8, Interfaces.Unsigned_8);
   begin
      return C (V);
   end To_U8;

   function To_I8 (U : Interfaces.Unsigned_8) return Interfaces.Integer_8 is
      function C is new Ada.Unchecked_Conversion
        (Interfaces.Unsigned_8, Interfaces.Integer_8);
   begin
      return C (U);
   end To_I8;

   function Single_Layout (K : D.Field_Kind) return D.Layout_Type is
      L : D.Layout_Type;
   begin
      L.Count := 1;
      L.Kinds (1) := K;
      return L;
   end Single_Layout;

   --  Pre-flight notes (ingress reasons, bounded change R1/R2 only):
   --  * Constitution ingress authority: docs/constitution.txt sections 9
   --    (Decode/Validate ingress flow), 16 (malformed-input rejection),
   --    20 (bounded decoding; reject malformed or overlong; no unchecked
   --    buffer access). No separate ingress reason table with distinct
   --    enumerators was found in the constitution text.
   --  * Decoder spec source of truth (A1): D.String_Max and D.Decode_Status
   --    (Success, Rejected) names are used exactly. There is no
   --    Rejection_Reason enumerator in
   --    src/protocol/adacraft-protocol-packet_decoder.ads, so every
   --    constitution malformed-input phrase maps to D.Rejected.
   --    -- spelling: constitution "rejected/malformed" = spec Rejected (A2).
   --    -- TODO(Q1): constitution has no per-reason enumerator table;
   --    --   using closest existing reason Rejected; raised with owner.
   --    --   Distinct empty/truncation/overlong/over-max/overrun reasons
   --    --   belong to a later decoder-spec item; this item must not edit
   --    --   the .ads.
   --  * Varnum distinctness (read-only): V.Decode / V.Decode_Varlong report
   --    Status_Type (Ok, Truncated, Overlong, Buffer_Too_Small); decoder body
   --    maps any non-Ok locally to Rejected. Varnum is never touched (R12).
   --  * String_Max unit (A5): decoder compares byte count
   --    (Natural (Len_Val) vs String_Max); tests treat String_Max as bytes
   --    here, matching the decoder's current comparison unit.

   --  Shared rejection helper: every new malformed-input assertion checks
   --  BOTH that decode failed with no packet value accepted (Status is
   --  Rejected and Field_Count is 0) and the reported reason equals the
   --  constitution ingress reason via the spec enumerator (here: Rejected).
   --  A bare "failed" check alone does not count.
   procedure Assert_Rejects
     (Payload : Octets;
      Layout  : D.Layout_Type;
      Msg     : String)
   is
      Fields_P : Field_Array_Access := new D.Field_Array;
      Pid : Interfaces.Integer_32 := 0;
      Cnt : Natural := 0;
      St  : D.Decode_Status := D.Success;
   begin
      D.Decode (Payload, Layout, Pid, Fields_P.all, Cnt, St);
      Check (St = D.Rejected, Msg & " status is Rejected");
      Check (Cnt = 0, Msg & " no packet accepted (Field_Count = 0)");
   end Assert_Rejects;

   --  R1: empty input. Zero-length buffer decode fails with the
   --  constitution empty-input reason (= spec Rejected).
   --  Per A4: zero-length reports the empty-input reason, not truncation,
   --  so R2 loops below start at length 1. Constitution text states the
   --  ingress flow Decode/Validate with malformed-input rejection but does
   --  not define empty == truncation; asserting the empty-input reason
   --  (Rejected) here with this comment records the A4 choice.
   procedure Check_Empty_R1 is
      Backing  : Scratch_Access := new Octets (1 .. 1);
      Fields_P : Field_Array_Access := new D.Field_Array;
      Pid : Interfaces.Integer_32 := 0;
      Cnt : Natural := 999;
      St  : D.Decode_Status := D.Success;
      L   : D.Layout_Type := Single_Layout (D.VarInt);
   begin
      Backing.all (1) := 16#00#;
      --  Null slice has Length 0; decoder returns Rejected on Length = 0.
      D.Decode (Backing.all (2 .. 1), L, Pid, Fields_P.all, Cnt, St);
      Check (St = D.Rejected, "R1 empty status is Rejected");
      Check (Cnt = 0, "R1 empty no packet accepted (Field_Count = 0)");
   end Check_Empty_R1;

   --  R2 helper: every strict prefix 1 .. N-1 of a valid packet must fail
   --  with the truncation reason (= spec Rejected). Loop, not samples.
   procedure Check_Prefixes_Truncated
     (Full   : Octets;
      Layout : D.Layout_Type;
      Name   : String)
   is
      Fields_P : Field_Array_Access := new D.Field_Array;
      Pid : Interfaces.Integer_32 := 0;
      Cnt : Natural := 0;
      St  : D.Decode_Status := D.Success;
      N   : constant Natural := Full'Length;
   begin
      Check (N >= 2, Name & " full packet length >= 2 for prefix loop");
      --  Sanity: full packet itself must decode successfully.
      D.Decode (Full, Layout, Pid, Fields_P.all, Cnt, St);
      Check (St = D.Success, Name & " full packet status Success");
      if N >= 2 then
         for L in 1 .. N - 1 loop
            Assert_Rejects
              (Payload => Full (Full'First .. Full'First + L - 1),
               Layout  => Layout,
               Msg     => Name & " truncated prefix len" & Natural'Image (L));
         end loop;
      end if;
   end Check_Prefixes_Truncated;

   --  R2: one valid encoded packet per supported field kind (all 10
   --  D.Field_Kind enumerators found in the decoder body: VarInt, VarLong,
   --  String, Boolean, Byte, Unsigned_Byte, Short, Unsigned_Short, Int,
   --  Long). Each vector of length N is decoded at every L in 1 .. N-1.
   procedure Check_Truncated_R2 is
      Buf_Ptr : Scratch_Access := new Octets (1 .. 64);
      Pos : Positive;
      N : Natural;
   begin
      --  VarInt field.
      Pos := 1;
      Append_VarInt (7, Buf_Ptr.all, Pos);
      Append_VarInt (-12_345, Buf_Ptr.all, Pos);
      N := Pos - 1;
      Check_Prefixes_Truncated
        (Buf_Ptr.all (1 .. N), Single_Layout (D.VarInt), "R2 varint");
      --  VarLong field.
      Pos := 1;
      Append_VarInt (7, Buf_Ptr.all, Pos);
      Append_VarLong (-9_876_543_210, Buf_Ptr.all, Pos);
      N := Pos - 1;
      Check_Prefixes_Truncated
        (Buf_Ptr.all (1 .. N), Single_Layout (D.VarLong), "R2 varlong");
      --  String field (small, in-range).
      Pos := 1;
      Append_VarInt (5, Buf_Ptr.all, Pos);
      Append_VarInt (3, Buf_Ptr.all, Pos);
      Append_Byte (Buf_Ptr.all, Pos, 16#68#);
      Append_Byte (Buf_Ptr.all, Pos, 16#69#);
      Append_Byte (Buf_Ptr.all, Pos, 16#21#);
      N := Pos - 1;
      Check_Prefixes_Truncated
        (Buf_Ptr.all (1 .. N), Single_Layout (D.String), "R2 string");
      --  Boolean field.
      Pos := 1;
      Append_VarInt (3, Buf_Ptr.all, Pos);
      Append_Byte (Buf_Ptr.all, Pos, 16#01#);
      N := Pos - 1;
      Check_Prefixes_Truncated
        (Buf_Ptr.all (1 .. N), Single_Layout (D.Boolean), "R2 boolean");
      --  Byte field.
      Pos := 1;
      Append_VarInt (11, Buf_Ptr.all, Pos);
      Append_Byte (Buf_Ptr.all, Pos, To_U8 (-12));
      N := Pos - 1;
      Check_Prefixes_Truncated
        (Buf_Ptr.all (1 .. N), Single_Layout (D.Byte), "R2 byte");
      --  Unsigned_Byte field.
      Pos := 1;
      Append_VarInt (11, Buf_Ptr.all, Pos);
      Append_Byte (Buf_Ptr.all, Pos, 200);
      N := Pos - 1;
      Check_Prefixes_Truncated
        (Buf_Ptr.all (1 .. N), Single_Layout (D.Unsigned_Byte),
         "R2 unsigned_byte");
      --  Short field.
      Pos := 1;
      Append_VarInt (11, Buf_Ptr.all, Pos);
      Append_U16BE (Buf_Ptr.all, Pos, To_U16 (-12_345));
      N := Pos - 1;
      Check_Prefixes_Truncated
        (Buf_Ptr.all (1 .. N), Single_Layout (D.Short), "R2 short");
      --  Unsigned_Short field.
      Pos := 1;
      Append_VarInt (11, Buf_Ptr.all, Pos);
      Append_U16BE (Buf_Ptr.all, Pos, 60_000);
      N := Pos - 1;
      Check_Prefixes_Truncated
        (Buf_Ptr.all (1 .. N), Single_Layout (D.Unsigned_Short),
         "R2 unsigned_short");
      --  Int field.
      Pos := 1;
      Append_VarInt (11, Buf_Ptr.all, Pos);
      Append_U32BE (Buf_Ptr.all, Pos, To_U32 (-123_456_789));
      N := Pos - 1;
      Check_Prefixes_Truncated
        (Buf_Ptr.all (1 .. N), Single_Layout (D.Int), "R2 int");
      --  Long field.
      Pos := 1;
      Append_VarInt (11, Buf_Ptr.all, Pos);
      Append_U64BE (Buf_Ptr.all, Pos, To_U64 (-123_456_789_012_345_678));
      N := Pos - 1;
      Check_Prefixes_Truncated
        (Buf_Ptr.all (1 .. N), Single_Layout (D.Long), "R2 long");
   end Check_Truncated_R2;

   --  R3: overlong VarInt (6 bytes, continuation bit still set on byte 5).
   --  Per A3: input ending inside a VarInt under the 5-byte limit is
   --  truncation; once the limit is exceeded it is overlong whatever
   --  follows, unless the constitution says otherwise. Constitution
   --  ingress authority demands rejection of malformed/overlong input
   --  (see pre-flight notes); spec enumerator Rejected used (A2, Q1 TODO
   --  above). No decoder/spec edits; each case checks fail plus reason
   --  via Assert_Rejects.
   procedure Check_Overlong_VarInt_R3 is
      Overlong : constant Octets (1 .. 6) :=
        (16#80#, 16#80#, 16#80#, 16#80#, 16#80#, 16#00#);
      Empty_Layout : D.Layout_Type;
      Buf_Ptr : Scratch_Access := new Octets (1 .. 16);
   begin
      --  Case A: overlong sequence as packet-ID at offset 0.
      Assert_Rejects
        (Payload => Overlong,
         Layout  => Empty_Layout,
         Msg     => "R3 overlong varint as packet id");
      --  Case B: overlong sequence as VarInt field after a valid ID.
      Buf_Ptr.all (1) := 16#07#;
      for I in Overlong'Range loop
         Buf_Ptr.all (1 + I) := Overlong (I);
      end loop;
      Assert_Rejects
        (Payload => Buf_Ptr.all (1 .. 7),
         Layout  => Single_Layout (D.VarInt),
         Msg     => "R3 overlong varint as field");
   end Check_Overlong_VarInt_R3;

   --  R4: overlong VarLong (11 bytes, continuation bit still set on
   --  byte 10). Per A3 limit rule as above; asserts the overlong reason
   --  (= spec Rejected) with fail-plus-reason checks only.
   procedure Check_Overlong_VarLong_R4 is
      Overlong : constant Octets (1 .. 11) :=
        (16#80#, 16#80#, 16#80#, 16#80#, 16#80#, 16#80#,
         16#80#, 16#80#, 16#80#, 16#80#, 16#00#);
      Buf_Ptr : Scratch_Access := new Octets (1 .. 16);
   begin
      Buf_Ptr.all (1) := 16#07#;
      for I in Overlong'Range loop
         Buf_Ptr.all (1 + I) := Overlong (I);
      end loop;
      Assert_Rejects
        (Payload => Buf_Ptr.all (1 .. 12),
         Layout  => Single_Layout (D.VarLong),
         Msg     => "R4 overlong varlong as field");
   end Check_Overlong_VarLong_R4;

   procedure Check_VarInt (Value : Interfaces.Integer_32; Name : String) is
      Buf_Ptr : Scratch_Access := new Octets (1 .. 16);
      Fields_P : Field_Array_Access := new D.Field_Array;
      Pos : Positive := 1;
      Pid : Interfaces.Integer_32 := 0;
      Cnt : Natural := 0;
      St  : D.Decode_Status := D.Rejected;
   begin
      Append_VarInt (7, Buf_Ptr.all, Pos);
      Append_VarInt (Value, Buf_Ptr.all, Pos);
      D.Decode (Buf_Ptr.all (1 .. Pos - 1), Single_Layout (D.VarInt),
                Pid, Fields_P.all, Cnt, St);
      Check (St = D.Success, Name & " status");
      Check (Pid = 7, Name & " packet id");
      Check (Cnt = 1, Name & " count");
      if St = D.Success and then Cnt = 1 then
         Check (Fields_P.all (1).Kind = D.VarInt, Name & " kind");
         Check (Fields_P.all (1).VarInt_Value = Value, Name & " value");
      end if;
   end Check_VarInt;

   procedure Check_VarLong (Value : Interfaces.Integer_64; Name : String) is
      Buf_Ptr : Scratch_Access := new Octets (1 .. 32);
      Fields_P : Field_Array_Access := new D.Field_Array;
      Pos : Positive := 1;
      Pid : Interfaces.Integer_32 := 0;
      Cnt : Natural := 0;
      St  : D.Decode_Status := D.Rejected;
   begin
      Append_VarInt (7, Buf_Ptr.all, Pos);
      Append_VarLong (Value, Buf_Ptr.all, Pos);
      D.Decode (Buf_Ptr.all (1 .. Pos - 1), Single_Layout (D.VarLong),
                Pid, Fields_P.all, Cnt, St);
      Check (St = D.Success, Name & " status");
      Check (Pid = 7, Name & " packet id");
      Check (Cnt = 1, Name & " count");
      if St = D.Success and then Cnt = 1 then
         Check (Fields_P.all (1).Kind = D.VarLong, Name & " kind");
         Check (Fields_P.all (1).VarLong_Value = Value, Name & " value");
      end if;
   end Check_VarLong;

   procedure Check_Bool (Value : Boolean; Name : String) is
      Buf_Ptr : Scratch_Access := new Octets (1 .. 16);
      Fields_P : Field_Array_Access := new D.Field_Array;
      Pos : Positive := 1;
      Pid : Interfaces.Integer_32 := 0;
      Cnt : Natural := 0;
      St  : D.Decode_Status := D.Rejected;
   begin
      Append_VarInt (3, Buf_Ptr.all, Pos);
      if Value then
         Append_Byte (Buf_Ptr.all, Pos, 16#01#);
      else
         Append_Byte (Buf_Ptr.all, Pos, 16#00#);
      end if;
      D.Decode (Buf_Ptr.all (1 .. Pos - 1), Single_Layout (D.Boolean),
                Pid, Fields_P.all, Cnt, St);
      Check (St = D.Success, Name & " status");
      Check (Pid = 3, Name & " packet id");
      Check (Cnt = 1, Name & " count");
      if St = D.Success and then Cnt = 1 then
         Check (Fields_P.all (1).Kind = D.Boolean, Name & " kind");
         Check (Fields_P.all (1).Bool_Value = Value, Name & " value");
      end if;
   end Check_Bool;

   procedure Check_Byte (Value : Interfaces.Integer_8; Name : String) is
      Buf_Ptr : Scratch_Access := new Octets (1 .. 16);
      Fields_P : Field_Array_Access := new D.Field_Array;
      Pos : Positive := 1;
      Pid : Interfaces.Integer_32 := 0;
      Cnt : Natural := 0;
      St  : D.Decode_Status := D.Rejected;
      U : Interfaces.Unsigned_8;
   begin
      U := To_U8 (Value);
      Append_VarInt (11, Buf_Ptr.all, Pos);
      Append_Byte (Buf_Ptr.all, Pos, U);
      D.Decode (Buf_Ptr.all (1 .. Pos - 1), Single_Layout (D.Byte),
                Pid, Fields_P.all, Cnt, St);
      Check (St = D.Success, Name & " status");
      Check (Pid = 11, Name & " packet id");
      if St = D.Success and then Cnt = 1 then
         Check (Fields_P.all (1).Byte_Value = Value, Name & " value");
      end if;
   end Check_Byte;

   procedure Check_UByte (Value : Interfaces.Unsigned_8; Name : String) is
      Buf_Ptr : Scratch_Access := new Octets (1 .. 16);
      Fields_P : Field_Array_Access := new D.Field_Array;
      Pos : Positive := 1;
      Pid : Interfaces.Integer_32 := 0;
      Cnt : Natural := 0;
      St  : D.Decode_Status := D.Rejected;
   begin
      Append_VarInt (11, Buf_Ptr.all, Pos);
      Append_Byte (Buf_Ptr.all, Pos, Value);
      D.Decode (Buf_Ptr.all (1 .. Pos - 1), Single_Layout (D.Unsigned_Byte),
                Pid, Fields_P.all, Cnt, St);
      Check (St = D.Success, Name & " status");
      if St = D.Success and then Cnt = 1 then
         Check (Fields_P.all (1).UByte_Value = Value, Name & " value");
      end if;
   end Check_UByte;

   procedure Check_Short (Value : Interfaces.Integer_16; Name : String) is
      Buf_Ptr : Scratch_Access := new Octets (1 .. 16);
      Fields_P : Field_Array_Access := new D.Field_Array;
      Pos : Positive := 1;
      Pid : Interfaces.Integer_32 := 0;
      Cnt : Natural := 0;
      St  : D.Decode_Status := D.Rejected;
   begin
      Append_VarInt (11, Buf_Ptr.all, Pos);
      Append_U16BE (Buf_Ptr.all, Pos, To_U16 (Value));
      D.Decode (Buf_Ptr.all (1 .. Pos - 1), Single_Layout (D.Short),
                Pid, Fields_P.all, Cnt, St);
      Check (St = D.Success, Name & " status");
      if St = D.Success and then Cnt = 1 then
         Check (Fields_P.all (1).Short_Value = Value, Name & " value");
      end if;
   end Check_Short;

   procedure Check_UShort (Value : Interfaces.Unsigned_16; Name : String) is
      Buf_Ptr : Scratch_Access := new Octets (1 .. 16);
      Fields_P : Field_Array_Access := new D.Field_Array;
      Pos : Positive := 1;
      Pid : Interfaces.Integer_32 := 0;
      Cnt : Natural := 0;
      St  : D.Decode_Status := D.Rejected;
   begin
      Append_VarInt (11, Buf_Ptr.all, Pos);
      Append_U16BE (Buf_Ptr.all, Pos, Value);
      D.Decode (Buf_Ptr.all (1 .. Pos - 1), Single_Layout (D.Unsigned_Short),
                Pid, Fields_P.all, Cnt, St);
      Check (St = D.Success, Name & " status");
      if St = D.Success and then Cnt = 1 then
         Check (Fields_P.all (1).UShort_Value = Value, Name & " value");
      end if;
   end Check_UShort;

   procedure Check_Int (Value : Interfaces.Integer_32; Name : String) is
      Buf_Ptr : Scratch_Access := new Octets (1 .. 16);
      Fields_P : Field_Array_Access := new D.Field_Array;
      Pos : Positive := 1;
      Pid : Interfaces.Integer_32 := 0;
      Cnt : Natural := 0;
      St  : D.Decode_Status := D.Rejected;
   begin
      Append_VarInt (11, Buf_Ptr.all, Pos);
      Append_U32BE (Buf_Ptr.all, Pos, To_U32 (Value));
      D.Decode (Buf_Ptr.all (1 .. Pos - 1), Single_Layout (D.Int),
                Pid, Fields_P.all, Cnt, St);
      Check (St = D.Success, Name & " status");
      if St = D.Success and then Cnt = 1 then
         Check (Fields_P.all (1).Int_Value = Value, Name & " value");
      end if;
   end Check_Int;

   procedure Check_Long (Value : Interfaces.Integer_64; Name : String) is
      Buf_Ptr : Scratch_Access := new Octets (1 .. 32);
      Fields_P : Field_Array_Access := new D.Field_Array;
      Pos : Positive := 1;
      Pid : Interfaces.Integer_32 := 0;
      Cnt : Natural := 0;
      St  : D.Decode_Status := D.Rejected;
   begin
      Append_VarInt (11, Buf_Ptr.all, Pos);
      Append_U64BE (Buf_Ptr.all, Pos, To_U64 (Value));
      D.Decode (Buf_Ptr.all (1 .. Pos - 1), Single_Layout (D.Long),
                Pid, Fields_P.all, Cnt, St);
      Check (St = D.Success, Name & " status");
      if St = D.Success and then Cnt = 1 then
         Check (Fields_P.all (1).Long_Value = Value, Name & " value");
      end if;
   end Check_Long;

   procedure Check_String_Empty is
      Buf_Ptr : Scratch_Access := new Octets (1 .. 16);
      Fields_P : Field_Array_Access := new D.Field_Array;
      Pos : Positive := 1;
      Pid : Interfaces.Integer_32 := 0;
      Cnt : Natural := 0;
      St  : D.Decode_Status := D.Rejected;
   begin
      Append_VarInt (5, Buf_Ptr.all, Pos);
      Append_VarInt (0, Buf_Ptr.all, Pos);
      D.Decode (Buf_Ptr.all (1 .. Pos - 1), Single_Layout (D.String),
                Pid, Fields_P.all, Cnt, St);
      Check (St = D.Success, "string empty status");
      Check (Pid = 5, "string empty packet id");
      Check (Cnt = 1, "string empty count");
      if St = D.Success and then Cnt = 1 then
         Check (Fields_P.all (1).Kind = D.String, "string empty kind");
         Check (Fields_P.all (1).String_Len = 0, "string empty len");
      end if;
   end Check_String_Empty;

   procedure Check_String_Max is
      Total : constant Positive := 1 + 5 + D.String_Max + 8;
      Buf_Ptr : Scratch_Access := new Octets (1 .. Total);
      Fields_P : Field_Array_Access := new D.Field_Array;
      Pos : Positive := 1;
      Pid : Interfaces.Integer_32 := 0;
      Cnt : Natural := 0;
      St  : D.Decode_Status := D.Rejected;
      Same : Boolean := True;
   begin
      Append_VarInt (9, Buf_Ptr.all, Pos);
      Append_VarInt (Interfaces.Integer_32 (D.String_Max), Buf_Ptr.all, Pos);
      for I in 1 .. D.String_Max loop
         Buf_Ptr.all (Pos) := 16#41#;
         Pos := Pos + 1;
      end loop;
      D.Decode (Buf_Ptr.all (1 .. Pos - 1), Single_Layout (D.String),
                Pid, Fields_P.all, Cnt, St);
      Check (St = D.Success, "string max status");
      Check (Pid = 9, "string max packet id");
      Check (Cnt = 1, "string max count");
      if St = D.Success and then Cnt = 1 then
         Check (Fields_P.all (1).String_Len = D.String_Max, "string max len");
         for I in 1 .. D.String_Max loop
            if Fields_P.all (1).String_Data (I) /= 16#41# then
               Same := False;
               exit;
            end if;
         end loop;
         Check (Same, "string max bytes");
      end if;
   end Check_String_Max;

   procedure Check_String_Small is
      Buf_Ptr : Scratch_Access := new Octets (1 .. 32);
      Fields_P : Field_Array_Access := new D.Field_Array;
      Pos : Positive := 1;
      Pid : Interfaces.Integer_32 := 0;
      Cnt : Natural := 0;
      St  : D.Decode_Status := D.Rejected;
   begin
      Append_VarInt (5, Buf_Ptr.all, Pos);
      Append_VarInt (3, Buf_Ptr.all, Pos);
      Append_Byte (Buf_Ptr.all, Pos, 16#68#);
      Append_Byte (Buf_Ptr.all, Pos, 16#69#);
      Append_Byte (Buf_Ptr.all, Pos, 16#21#);
      D.Decode (Buf_Ptr.all (1 .. Pos - 1), Single_Layout (D.String),
                Pid, Fields_P.all, Cnt, St);
      Check (St = D.Success, "string small status");
      if St = D.Success and then Cnt = 1 then
         Check (Fields_P.all (1).String_Len = 3, "string small len");
         Check (Fields_P.all (1).String_Data (1) = 16#68#
                and then Fields_P.all (1).String_Data (2) = 16#69#
                and then Fields_P.all (1).String_Data (3) = 16#21#,
                "string small bytes");
      end if;
   end Check_String_Small;

   procedure Check_Mixed is
      Buf_Ptr : Scratch_Access := new Octets (1 .. 256);
      Fields_P : Field_Array_Access := new D.Field_Array;
      Pos : Positive := 1;
      Pid : Interfaces.Integer_32 := 0;
      Cnt : Natural := 0;
      St  : D.Decode_Status := D.Rejected;
      L : D.Layout_Type;
      Exp_I32 : Interfaces.Integer_32 := -12_345;
      Exp_I64 : Interfaces.Integer_64 := -9_876_543_210;
      Exp_B : Interfaces.Integer_8 := -12;
      Exp_UB : Interfaces.Unsigned_8 := 200;
      Exp_S : Interfaces.Integer_16 := -12_345;
      Exp_US : Interfaces.Unsigned_16 := 60_000;
      Exp_I : Interfaces.Integer_32 := -123_456_789;
      Exp_L : Interfaces.Integer_64 := -123_456_789_012_345_678;
      UB_Raw : Interfaces.Unsigned_8;
   begin
      L.Count := 10;
      L.Kinds (1) := D.VarInt;
      L.Kinds (2) := D.VarLong;
      L.Kinds (3) := D.String;
      L.Kinds (4) := D.Boolean;
      L.Kinds (5) := D.Byte;
      L.Kinds (6) := D.Unsigned_Byte;
      L.Kinds (7) := D.Short;
      L.Kinds (8) := D.Unsigned_Short;
      L.Kinds (9) := D.Int;
      L.Kinds (10) := D.Long;
      Append_VarInt (42, Buf_Ptr.all, Pos);
      Append_VarInt (Exp_I32, Buf_Ptr.all, Pos);
      Append_VarLong (Exp_I64, Buf_Ptr.all, Pos);
      Append_VarInt (2, Buf_Ptr.all, Pos);
      Append_Byte (Buf_Ptr.all, Pos, 16#41#);
      Append_Byte (Buf_Ptr.all, Pos, 16#42#);
      Append_Byte (Buf_Ptr.all, Pos, 16#01#);
      Append_Byte (Buf_Ptr.all, Pos, To_U8 (Exp_B));
      Append_Byte (Buf_Ptr.all, Pos, Exp_UB);
      Append_U16BE (Buf_Ptr.all, Pos, To_U16 (Exp_S));
      Append_U16BE (Buf_Ptr.all, Pos, Exp_US);
      Append_U32BE (Buf_Ptr.all, Pos, To_U32 (Exp_I));
      Append_U64BE (Buf_Ptr.all, Pos, To_U64 (Exp_L));
      D.Decode (Buf_Ptr.all (1 .. Pos - 1), L, Pid, Fields_P.all, Cnt, St);
      Check (St = D.Success, "mixed status");
      Check (Pid = 42, "mixed packet id");
      Check (Cnt = 10, "mixed count");
      if St = D.Success and then Cnt = 10 then
         Check (Fields_P.all (1).VarInt_Value = Exp_I32, "mixed varint");
         Check (Fields_P.all (2).VarLong_Value = Exp_I64, "mixed varlong");
         Check (Fields_P.all (3).String_Len = 2
                and then Fields_P.all (3).String_Data (1) = 16#41#
                and then Fields_P.all (3).String_Data (2) = 16#42#,
                "mixed string");
         Check (Fields_P.all (4).Bool_Value = True, "mixed bool");
         Check (Fields_P.all (5).Byte_Value = Exp_B, "mixed byte");
         Check (Fields_P.all (6).UByte_Value = Exp_UB, "mixed ubyte");
         Check (Fields_P.all (7).Short_Value = Exp_S, "mixed short");
         Check (Fields_P.all (8).UShort_Value = Exp_US, "mixed ushort");
         Check (Fields_P.all (9).Int_Value = Exp_I, "mixed int");
         Check (Fields_P.all (10).Long_Value = Exp_L, "mixed long");
      end if;
   end Check_Mixed;

begin
   Check_Empty_R1;
   Check_Truncated_R2;
   Check_Overlong_VarInt_R3;
   Check_Overlong_VarLong_R4;
   Check_VarInt (0, "varint 0");
   Check_VarInt (-1, "varint -1");
   Check_VarInt (Interfaces.Integer_32'First, "varint first");
   Check_VarInt (Interfaces.Integer_32'Last, "varint last");
   Check_VarLong (0, "varlong 0");
   Check_VarLong (-1, "varlong -1");
   Check_VarLong (Interfaces.Integer_64'First, "varlong first");
   Check_VarLong (Interfaces.Integer_64'Last, "varlong last");
   Check_String_Empty;
   Check_String_Small;
   Check_String_Max;
   Check_Bool (False, "bool false");
   Check_Bool (True, "bool true");
   Check_Byte (0, "byte 0");
   Check_Byte (-1, "byte -1");
   Check_Byte (Interfaces.Integer_8'First, "byte first");
   Check_Byte (Interfaces.Integer_8'Last, "byte last");
   Check_UByte (0, "ubyte 0");
   Check_UByte (Interfaces.Unsigned_8'First, "ubyte first");
   Check_UByte (Interfaces.Unsigned_8'Last, "ubyte last");
   Check_Short (0, "short 0");
   Check_Short (-1, "short -1");
   Check_Short (Interfaces.Integer_16'First, "short first");
   Check_Short (Interfaces.Integer_16'Last, "short last");
   Check_UShort (0, "ushort 0");
   Check_UShort (Interfaces.Unsigned_16'First, "ushort first");
   Check_UShort (Interfaces.Unsigned_16'Last, "ushort last");
   Check_Int (0, "int 0");
   Check_Int (-1, "int -1");
   Check_Int (Interfaces.Integer_32'First, "int first");
   Check_Int (Interfaces.Integer_32'Last, "int last");
   Check_Long (0, "long 0");
   Check_Long (-1, "long -1");
   Check_Long (Interfaces.Integer_64'First, "long first");
   Check_Long (Interfaces.Integer_64'Last, "long last");
   Check_Mixed;
   if Failures = 0 then
      Ada.Text_IO.Put_Line ("test_protocol_packet_decoder PASS");
   else
      Ada.Text_IO.Put_Line ("test_protocol_packet_decoder FAIL:" &
                            Natural'Image (Failures));
      Ada.Command_Line.Set_Exit_Status (1);
   end if;
end Test_Protocol_Packet_Decoder;
