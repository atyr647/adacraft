package body Adacraft.Auth.Session with SPARK_Mode => On is
   use type Interfaces.Unsigned_8;

   function Is_Hex (C : Character) return Boolean is
   begin
      return (C in '0' .. '9')
        or else (C in 'a' .. 'f')
        or else (C in 'A' .. 'F');
   end Is_Hex;

   function Is_Hex4 (S : String; P : Natural) return Boolean is
   begin
      if P + 3 > S'Last then
         return False;
      end if;
      for K in P .. P + 3 loop
         if not Is_Hex (S (K)) then
            return False;
         end if;
      end loop;
      return True;
   end Is_Hex4;

   function Is_Simple_Escape (E : Character) return Boolean is
   begin
      case E is
         when '"' | '\' | '/' | 'b' | 'f' | 'n' | 'r' | 't' =>
            return True;
         when others =>
            return False;
      end case;
   end Is_Simple_Escape;

   function Unescape (E : Character) return Character is
   begin
      case E is
         when 'b'    => return ASCII.BS;
         when 'f'    => return ASCII.FF;
         when 'n'    => return ASCII.LF;
         when 'r'    => return ASCII.CR;
         when 't'    => return ASCII.HT;
         when others => return E;
      end case;
   end Unescape;

   function Nibble (C : Character) return Interfaces.Unsigned_8 is
   begin
      if C in '0' .. '9' then
         return Interfaces.Unsigned_8 (Character'Pos (C) - Character'Pos ('0'));
      elsif C in 'a' .. 'f' then
         return Interfaces.Unsigned_8
           (Character'Pos (C) - Character'Pos ('a') + 10);
      else
         return Interfaces.Unsigned_8
           (Character'Pos (C) - Character'Pos ('A') + 10);
      end if;
   end Nibble;

   function Is_32_Hex (S : String) return Boolean is
   begin
      if S'Length /= 32 then
         return False;
      end if;
      for I in S'Range loop
         if not Is_Hex (S (I)) then
            return False;
         end if;
      end loop;
      return True;
   end Is_32_Hex;

   function Hex_To_Uuid (S : String) return Uuid is
      R      : Uuid := [others => 0];
      Hi, Lo : Interfaces.Unsigned_8;
   begin
      if S'Length /= 32 then
         return R;
      end if;
      for I in 0 .. 15 loop
         Hi := Nibble (S (S'First + I * 2));
         Lo := Nibble (S (S'First + I * 2 + 1));
         R (I) := Hi * Interfaces.Unsigned_8 (16) + Lo;
      end loop;
      return R;
   end Hex_To_Uuid;

   ---------------
   -- JSON scan --
   ---------------

   --  All routines are total: they return Ok=False instead of raising.

   --  Single shared escape consumer: merges the Parse_String/Skip_String
   --  copies. Expects S(P) = '\'; on success advances P past the escape
   --  and returns the decoded character (unicode escapes as '?').
   procedure Consume_Escape
     (S : String; P : in out Natural; C : out Character; Ok : out Boolean)
   is
   begin
      C := '?';
      Ok := False;
      if P > S'Last or else S (P) /= '\' then
         return;
      end if;
      if P + 1 > S'Last then
         return;
      end if;
      declare
         E : constant Character := S (P + 1);
      begin
         if E = 'u' then
            if not Is_Hex4 (S, P + 2) then
               return;
            end if;
            C := '?';
            P := P + 6;
            Ok := True;
            return;
         elsif Is_Simple_Escape (E) then
            C := Unescape (E);
            P := P + 2;
            Ok := True;
            return;
         else
            return;
         end if;
      end;
   end Consume_Escape;

   procedure Skip_WS (S : String; P : in out Natural) is
   begin
      while P <= S'Last
        and then (S (P) = ' ' or else S (P) = ASCII.HT
                  or else S (P) = ASCII.LF or else S (P) = ASCII.CR)
      loop
         P := P + 1;
      end loop;
   end Skip_WS;

   --  Parse a JSON string at S(P) = '"', storing the unescaped content
   --  into Buf(Buf_First .. *Len). Handles \" \\ \/ \b \f \n \r \t \uXXXX
   --  (unicode escapes stored as '?'). Returns Ok=False on truncation,
   --  unterminated string, or over-long content.
   procedure Parse_String
     (S         : String;
      P         : in out Natural;
      Buf       : out String;
      Buf_First : Natural;
      Len       : out Natural;
      Ok        : out Boolean)
   is
      Out_Next : Natural := Buf_First;
      Cap      : constant Natural := Buf'Last;
   begin
      Len := 0;
      Ok := False;
      if P > S'Last or else S (P) /= '"' then
         return;
      end if;
      P := P + 1;
      while P <= S'Last loop
         if S (P) = '"' then
            P := P + 1;
            Len := Out_Next - Buf_First;
            Ok := True;
            return;
         elsif S (P) = '\' then
            declare
               C   : Character := '?';
               EOk : Boolean := False;
            begin
               Consume_Escape (S, P, C, EOk);
               if not EOk then
                  return;
               end if;
               if Out_Next > Cap then
                  return;
               end if;
               Buf (Out_Next) := C;
               Out_Next := Out_Next + 1;
            end;
         else
            if Out_Next > Cap then
               return;
            end if;
            Buf (Out_Next) := S (P);
            Out_Next := Out_Next + 1;
            P := P + 1;
         end if;
      end loop;
      --  Unterminated.
      Ok := False;
   end Parse_String;

   --  Forward: structural string skip used by Skip_Value so long
   --  string values (e.g. unknown keys like "extra":"hello") validate.
   procedure Skip_String (S : String; P : in out Natural; Ok : out Boolean);

   procedure Skip_Elements
     (S : String; P : in out Natural; Close : Character; Is_Object : Boolean;
      Ok : out Boolean);

   --  Skip digit run helper for Skip_Number.
   procedure Skip_Digits (S : String; P : in out Natural) is
   begin
      while P <= S'Last and then S (P) in '0' .. '9' loop
         P := P + 1;
      end loop;
   end Skip_Digits;

   --  Skip JSON number fraction part; Ok=False on malformed fraction.
   procedure Skip_Fraction (S : String; P : in out Natural; Ok : out Boolean) is
   begin
      Ok := True;
      if P <= S'Last and then S (P) = '.' then
         P := P + 1;
         if P > S'Last or else S (P) not in '0' .. '9' then
            Ok := False;
            return;
         end if;
         Skip_Digits (S, P);
      end if;
   end Skip_Fraction;

   --  Skip JSON number exponent part; Ok=False on malformed exponent.
   procedure Skip_Exponent (S : String; P : in out Natural; Ok : out Boolean) is
   begin
      Ok := True;
      if P <= S'Last and then (S (P) = 'e' or else S (P) = 'E') then
         P := P + 1;
         if P <= S'Last and then (S (P) = '+' or else S (P) = '-') then
            P := P + 1;
         end if;
         if P > S'Last or else S (P) not in '0' .. '9' then
            Ok := False;
            return;
         end if;
         Skip_Digits (S, P);
      end if;
   end Skip_Exponent;

   --  Skip one JSON number at S(P); Ok=False unless well-formed.
   procedure Skip_Number (S : String; P : in out Natural; Ok : out Boolean) is
      Sub_Ok : Boolean;
   begin
      Ok := False;
      if P <= S'Last and then S (P) = '-' then
         P := P + 1;
         if P > S'Last then
            return;
         end if;
      end if;
      if P > S'Last then
         return;
      end if;
      if S (P) = '0' then
         P := P + 1;
      elsif S (P) in '1' .. '9' then
         Skip_Digits (S, P);
      else
         return;
      end if;
      Skip_Fraction (S, P, Sub_Ok);
      if not Sub_Ok then
         return;
      end if;
      Skip_Exponent (S, P, Sub_Ok);
      if not Sub_Ok then
         return;
      end if;
      Ok := True;
   end Skip_Number;

   --  Match one JSON literal word at S(P).
   procedure Skip_Word (S : String; P : in out Natural; Word : String;
                        Ok : out Boolean) is
   begin
      Ok := False;
      if P + Word'Length - 1 <= S'Last
        and then S (P .. P + Word'Length - 1) = Word
      then
         P := P + Word'Length;
         Ok := True;
      end if;
   end Skip_Word;

   --  Skip one generic JSON value with structural validation.
   procedure Skip_Value (S : String; P : in out Natural; Ok : out Boolean) is
      SOk : Boolean;
   begin
      Ok := False;
      Skip_WS (S, P);
      if P > S'Last then
         return;
      end if;
      case S (P) is
         when '"' =>
            Skip_String (S, P, SOk);
            Ok := SOk;
            return;
         when '{' =>
            P := P + 1;
            Skip_Elements (S, P, '}', True, SOk);
            Ok := SOk;
            return;
         when '[' =>
            P := P + 1;
            Skip_Elements (S, P, ']', False, SOk);
            Ok := SOk;
            return;
         when 't' =>
            Skip_Word (S, P, "true", SOk);
            Ok := SOk;
            return;
         when 'f' =>
            Skip_Word (S, P, "false", SOk);
            Ok := SOk;
            return;
         when 'n' =>
            Skip_Word (S, P, "null", SOk);
            Ok := SOk;
            return;
         when '-' | '0' .. '9' =>
            Skip_Number (S, P, SOk);
            Ok := SOk;
            return;
         when others =>
            return;
      end case;
   end Skip_Value;

   --  Consume separator between elements; handles first/close/comma.
   --  Returns Done=True when Close consumed (Ok=True); otherwise
   --  positions P at next element start.
   procedure Skip_Separator
     (S : String; P : in out Natural; Close : Character;
      First : in out Boolean; Done : out Boolean; Ok : out Boolean)
   is
   begin
      Done := False;
      Ok := False;
      Skip_WS (S, P);
      if P > S'Last then
         return;
      end if;
      if First and then S (P) = Close then
         P := P + 1;
         Done := True;
         Ok := True;
         return;
      end if;
      if not First then
         if S (P) = Close then
            return; --  trailing comma
         end if;
         if S (P) /= ',' then
            return;
         end if;
         P := P + 1;
         Skip_WS (S, P);
         if P > S'Last then
            return;
         end if;
         if S (P) = Close then
            return; --  trailing comma invalid
         end if;
      end if;
      First := False;
      Ok := True;
   end Skip_Separator;

   --  Skip one object key prefix ("key":) inside Skip_Elements.
   procedure Skip_Key_Prefix
     (S : String; P : in out Natural; Ok : out Boolean)
   is
      SOk : Boolean;
   begin
      Ok := False;
      if P > S'Last or else S (P) /= '"' then
         return;
      end if;
      Skip_String (S, P, SOk);
      if not SOk then
         return;
      end if;
      Skip_WS (S, P);
      if P > S'Last or else S (P) /= ':' then
         return;
      end if;
      P := P + 1;
      Ok := True;
   end Skip_Key_Prefix;

   procedure Skip_Elements
     (S : String; P : in out Natural; Close : Character; Is_Object : Boolean;
      Ok : out Boolean)
   is
      SOk   : Boolean;
      First : Boolean := True;
      Done  : Boolean := False;
   begin
      Ok := False;
      loop
         Skip_Separator (S, P, Close, First, Done, SOk);
         if not SOk then
            return;
         end if;
         if Done then
            Ok := True;
            return;
         end if;
         if Is_Object then
            Skip_Key_Prefix (S, P, SOk);
            if not SOk then
               return;
            end if;
         end if;
         Skip_Value (S, P, SOk);
         if not SOk then
            return;
         end if;
         Skip_WS (S, P);
         if P > S'Last then
            return;
         end if;
         if S (P) = Close then
            P := P + 1;
            Ok := True;
            return;
         elsif S (P) /= ',' then
            return;
         end if;
         --  Comma consumed at top of next iteration.
      end loop;
   end Skip_Elements;

   --  Skip a string structurally (no content capture) for unknown keys.
   procedure Skip_String (S : String; P : in out Natural; Ok : out Boolean) is
   begin
      Ok := False;
      if P > S'Last or else S (P) /= '"' then
         return;
      end if;
      P := P + 1;
      while P <= S'Last loop
         if S (P) = '\' then
            declare
               C   : Character := '?';
               EOk : Boolean := False;
            begin
               Consume_Escape (S, P, C, EOk);
               if not EOk then
                  return;
               end if;
            end;
         elsif S (P) = '"' then
            P := P + 1;
            Ok := True;
            return;
         else
            P := P + 1;
         end if;
      end loop;
   end Skip_String;

   --  Shared key parser: merges the Parse_Property/Parse_Document copies.
   --  Parses a JSON string key at S(P), consumes the ':' separator and
   --  trailing whitespace. On success P points at the value start.
   procedure Parse_Key
     (S     : String;
      P     : in out Natural;
      K_Buf : out String;
      KLen  : out Natural;
      Ok    : out Boolean)
   is
      KOk : Boolean := False;
   begin
      KLen := 0;
      Ok := False;
      Parse_String (S, P, K_Buf, K_Buf'First, KLen, KOk);
      if not KOk then
         return;
      end if;
      Skip_WS (S, P);
      if P > S'Last or else S (P) /= ':' then
         return;
      end if;
      P := P + 1;
      Skip_WS (S, P);
      if P > S'Last then
         return;
      end if;
      Ok := True;
   end Parse_Key;

   --  Store one parsed property into Props(Count+1) after bound checks.
   procedure Store_Property
     (Props : in out Property_Vector;
      Count : Natural;
      N_Buf : String; NLen : Natural;
      V_Buf : String; VLen : Natural;
      S_Buf : String; SLen : Natural;
      NSet, VSet, SSet : Boolean;
      Ok : out Boolean)
   is
   begin
      Ok := False;
      if not NSet or else not VSet then
         return;
      end if;
      if NLen = 0 or else NLen > Max_Prop_Chars then
         return;
      end if;
      if VLen > Max_Prop_Chars then
         return;
      end if;
      if SSet and then SLen > Max_Prop_Chars then
         return;
      end if;
      if Count + 1 > Max_Properties then
         return;
      end if;
      Props (Count + 1).Name :=
        Prop_Bounded.To_Bounded_String
          (N_Buf (N_Buf'First .. N_Buf'First + NLen - 1));
      Props (Count + 1).Value :=
        (if VLen = 0 then Prop_Bounded.Null_Bounded_String
         else Prop_Bounded.To_Bounded_String
           (V_Buf (V_Buf'First .. V_Buf'First + VLen - 1)));
      Props (Count + 1).Has_Sig := SSet;
      Props (Count + 1).Signature :=
        (if not SSet or else SLen = 0 then Prop_Bounded.Null_Bounded_String
         else Prop_Bounded.To_Bounded_String
           (S_Buf (S_Buf'First .. S_Buf'First + SLen - 1)));
      Ok := True;
   end Store_Property;

   --  Parse one property member value by key.
   procedure Parse_Property_Value
     (S     : String;
      P     : in out Natural;
      Key   : String;
      N_Buf : in out String; NLen : in out Natural;
      V_Buf : in out String; VLen : in out Natural;
      S_Buf : in out String; SLen : in out Natural;
      NSet, VSet : in out Boolean; SSet : in out Boolean;
      Ok    : out Boolean)
   is
      SOk : Boolean;
   begin
      Ok := False;
      if Key = "name" then
         Parse_String (S, P, N_Buf, N_Buf'First, NLen, SOk);
         if not SOk then
            return;
         end if;
         NSet := True;
      elsif Key = "value" then
         Parse_String (S, P, V_Buf, V_Buf'First, VLen, SOk);
         if not SOk then
            return;
         end if;
         VSet := True;
      elsif Key = "signature" then
         Parse_String (S, P, S_Buf, S_Buf'First, SLen, SOk);
         if not SOk then
            return;
         end if;
         SSet := True;
      elsif P <= S'Last and then S (P) = '"' then
         Skip_String (S, P, SOk);
         if not SOk then
            return;
         end if;
      else
         Skip_Value (S, P, SOk);
         if not SOk then
            return;
         end if;
      end if;
      Ok := True;
   end Parse_Property_Value;

   --  Parse one property object at S(P)='{', appending to Props.
   procedure Parse_Property
     (S     : String;
      P     : in out Natural;
      Props : in out Property_Vector;
      Count : Natural;
      Ok    : out Boolean)
   is
      N_Buf : String (1 .. Max_Prop_Chars + 64) := [others => ' '];
      V_Buf : String (1 .. Max_Prop_Chars + 64) := [others => ' '];
      S_Buf : String (1 .. Max_Prop_Chars + 64) := [others => ' '];
      K_Buf : String (1 .. 64) := [others => ' '];
      NLen, VLen, SLen, KLen : Natural := 0;
      KOk, SOk  : Boolean;
      NSet, VSet : Boolean := False;
      SSet      : Boolean := False;
      First     : Boolean := True;
   begin
      Ok := False;
      Skip_WS (S, P);
      if P > S'Last or else S (P) /= '{' then
         return;
      end if;
      P := P + 1;
      loop
         Skip_WS (S, P);
         if P > S'Last then
            return;
         end if;
         if S (P) = '}' then
            P := P + 1;
            Store_Property (Props, Count, N_Buf, NLen, V_Buf, VLen,
                            S_Buf, SLen, NSet, VSet, SSet, SOk);
            Ok := SOk;
            return;
         end if;
         if not First then
            if S (P) /= ',' then
               return;
            end if;
            P := P + 1;
            Skip_WS (S, P);
            if P > S'Last then
               return;
            end if;
         end if;
         First := False;
         Parse_Key (S, P, K_Buf, KLen, KOk);
         if not KOk then
            return;
         end if;
         Parse_Property_Value (S, P, K_Buf (K_Buf'First .. K_Buf'First + KLen - 1),
                               N_Buf, NLen, V_Buf, VLen, S_Buf, SLen,
                               NSet, VSet, SSet, SOk);
         if not SOk then
            return;
         end if;
      end loop;
   end Parse_Property;

   --  Store the trailing '}' trailer of a document; sets Done on success.
   procedure Finish_Document
     (S : String; P : in out Natural; Id_Set, Name_Set : Boolean;
      Tmp_Id : String; Tmp_Id_Len : Natural;
      Tmp_N : String; Tmp_N_Len : Natural;
      Id_Buf : in out String; N_Buf : in out String;
      Id_Len : out Natural; N_Len : out Natural;
      Count : Natural; P_Count : out Natural;
      Done : out Boolean; Ok : out Boolean)
   is
   begin
      Done := False;
      Ok := False;
      P := P + 1;
      Skip_WS (S, P);
      if P <= S'Last then
         return; --  trailing garbage
      end if;
      if not Id_Set or else not Name_Set then
         return;
      end if;
      if Tmp_Id_Len > 0 then
         Id_Buf (Id_Buf'First .. Id_Buf'First + Tmp_Id_Len - 1) :=
           Tmp_Id (Tmp_Id'First .. Tmp_Id'First + Tmp_Id_Len - 1);
      end if;
      if Tmp_N_Len > 0 then
         N_Buf (N_Buf'First .. N_Buf'First + Tmp_N_Len - 1) :=
           Tmp_N (Tmp_N'First .. Tmp_N'First + Tmp_N_Len - 1);
      end if;
      Id_Len := Tmp_Id_Len;
      N_Len := Tmp_N_Len;
      P_Count := Count;
      Done := True;
      Ok := True;
   end Finish_Document;

   function Is_Id_Key (K_Buf : String; KLen : Natural) return Boolean is
   begin
      return KLen = 2
        and then K_Buf'Length >= 2
        and then K_Buf (K_Buf'First .. K_Buf'First + 1) = "id";
   end Is_Id_Key;

   function Is_Name_Key (K_Buf : String; KLen : Natural) return Boolean is
   begin
      return KLen = 4
        and then K_Buf'Length >= 4
        and then K_Buf (K_Buf'First .. K_Buf'First + 3) = "name";
   end Is_Name_Key;

   --  Parse one scalar id/name field value by key length tag.
   procedure Parse_Doc_Scalar
     (S : String; P : in out Natural; K_Buf : String; KLen : Natural;
      Tmp_Id : in out String; Tmp_Id_Len : in out Natural;
      Tmp_N : in out String; Tmp_N_Len : in out Natural;
      Id_Set : in out Boolean; Name_Set : in out Boolean;
      Ok : out Boolean)
   is
      SOk : Boolean;
   begin
      Ok := False;
      if Is_Id_Key (K_Buf, KLen) then
         Parse_String (S, P, Tmp_Id, Tmp_Id'First, Tmp_Id_Len, SOk);
         if not SOk then
            return;
         end if;
         Id_Set := True;
      elsif Is_Name_Key (K_Buf, KLen) then
         Parse_String (S, P, Tmp_N, Tmp_N'First, Tmp_N_Len, SOk);
         if not SOk then
            return;
         end if;
         Name_Set := True;
      else
         return;
      end if;
      Ok := True;
   end Parse_Doc_Scalar;

   --  Parse the properties array value at S(P)='['.
   procedure Parse_Doc_Properties
     (S : String; P : in out Natural;
      Props : in out Property_Vector; Count : in out Natural;
      Props_Seen : in out Boolean; Ok : out Boolean)
   is
      SOk : Boolean;
   begin
      Ok := False;
      if Props_Seen then
         return;
      end if;
      Props_Seen := True;
      if P > S'Last or else S (P) /= '[' then
         return;
      end if;
      P := P + 1;
      Skip_WS (S, P);
      if P <= S'Last and then S (P) = ']' then
         P := P + 1;
         Ok := True;
         return;
      end if;
      loop
         if Count >= Max_Properties then
            return; --  over bound => Ok=False
         end if;
         Parse_Property (S, P, Props, Count, SOk);
         if not SOk then
            return;
         end if;
         Count := Count + 1;
         Skip_WS (S, P);
         if P > S'Last then
            return;
         end if;
         if S (P) = ',' then
            P := P + 1;
         elsif S (P) = ']' then
            P := P + 1;
            exit;
         else
            return;
         end if;
      end loop;
      Ok := True;
   end Parse_Doc_Properties;

   --  Dispatch one document field by key to scalar/properties/skip.
   procedure Parse_Doc_Field
     (S : String; P : in out Natural; K_Buf : String; KLen : Natural;
      Tmp_Id : in out String; Tmp_Id_Len : in out Natural;
      Tmp_N : in out String; Tmp_N_Len : in out Natural;
      Id_Set : in out Boolean; Name_Set : in out Boolean;
      Props : in out Property_Vector; Count : in out Natural;
      Props_Seen : in out Boolean; Ok : out Boolean)
   is
      SOk : Boolean;
   begin
      Ok := False;
      if Is_Id_Key (K_Buf, KLen) or else Is_Name_Key (K_Buf, KLen) then
         Parse_Doc_Scalar (S, P, K_Buf, KLen, Tmp_Id, Tmp_Id_Len,
                           Tmp_N, Tmp_N_Len, Id_Set, Name_Set, SOk);
         Ok := SOk;
         return;
      end if;
      if KLen = 10
        and then K_Buf (K_Buf'First .. K_Buf'First + 9) = "properties"
      then
         Parse_Doc_Properties (S, P, Props, Count, Props_Seen, SOk);
         Ok := SOk;
         return;
      end if;
      --  Unknown top-level key: skip any JSON value.
      Skip_Value (S, P, SOk);
      Ok := SOk;
   end Parse_Doc_Field;

   --  Consume a document separator; positions P at next key or Close.
   procedure Parse_Doc_Separator
     (S : String; P : in out Natural; First : in out Boolean;
      Ok : out Boolean)
   is
   begin
      Ok := False;
      if not First then
         if P > S'Last or else S (P) /= ',' then
            return;
         end if;
         P := P + 1;
         Skip_WS (S, P);
         if P > S'Last then
            return;
         end if;
         if S (P) = '}' then
            return; --  trailing comma invalid
         end if;
      end if;
      First := False;
      Ok := True;
   end Parse_Doc_Separator;

   --  Parse top-level document, extracting id/name/properties.
   procedure Parse_Document
     (S       : String;
      Id_Buf  : out String;
      Id_Len  : out Natural;
      N_Buf   : out String;
      N_Len   : out Natural;
      Props   : out Property_Vector;
      P_Count : out Natural;
      Ok      : out Boolean)
   is
      P           : Natural := S'First;
      K_Buf       : String (1 .. 64) := [others => ' '];
      KLen        : Natural;
      KOk, SOk    : Boolean;
      FDone       : Boolean := False;
      First       : Boolean := True;
      Id_Set      : Boolean := False;
      Name_Set    : Boolean := False;
      Props_Seen  : Boolean := False;
      Tmp_Id      : String (1 .. 64) := [others => ' '];
      Tmp_N       : String (1 .. Max_Name_Chars + 64) := [others => ' '];
      Tmp_Id_Len  : Natural := 0;
      Tmp_N_Len   : Natural := 0;
      Count       : Natural := 0;
   begin
      Id_Buf := [Id_Buf'Range => ' '];
      N_Buf := [N_Buf'Range => ' '];
      Id_Len := 0;
      N_Len := 0;
      P_Count := 0;
      Ok := False;
      for I in Props'Range loop
         Props (I) := (Name      => Prop_Bounded.Null_Bounded_String,
                       Value     => Prop_Bounded.Null_Bounded_String,
                       Has_Sig   => False,
                       Signature => Prop_Bounded.Null_Bounded_String);
      end loop;
      Skip_WS (S, P);
      if P > S'Last or else S (P) /= '{' then
         return;
      end if;
      P := P + 1;
      loop
         Skip_WS (S, P);
         if P > S'Last then
            return;
         end if;
         if S (P) = '}' then
            Finish_Document (S, P, Id_Set, Name_Set, Tmp_Id, Tmp_Id_Len,
                             Tmp_N, Tmp_N_Len, Id_Buf, N_Buf,
                             Id_Len, N_Len, Count, P_Count, SOk, FDone);
            Ok := SOk and then FDone;
            return;
         end if;
         Parse_Doc_Separator (S, P, First, SOk);
         if not SOk then
            return;
         end if;
         Parse_Key (S, P, K_Buf, KLen, KOk);
         if not KOk then
            return;
         end if;
         if P > S'Last then
            return;
         end if;
         Parse_Doc_Field (S, P, K_Buf, KLen, Tmp_Id, Tmp_Id_Len,
                          Tmp_N, Tmp_N_Len, Id_Set, Name_Set,
                          Props, Count, Props_Seen, SOk);
         if not SOk then
            return;
         end if;
      end loop;
   end Parse_Document;

   function Map_Reject (Reason : Disconnect_Reason) return Auth_Result is
   begin
      return (Kind => Rejected, Reason => Reason);
   end Map_Reject;

   function Interpret_Reply (Reply : Http_Reply) return Auth_Result is
   begin
      if Reply.Transport_Failed then
         return Map_Reject (Auth_Service_Unavailable);
      end if;
      if Reply.Status = 204 then
         return Map_Reject (Auth_Failed);
      end if;
      if Reply.Status /= 200 then
         return Map_Reject (Auth_Service_Unavailable);
      end if;
      if Body_Bounded.Length (Reply.Body_Text) = 0 then
         return Map_Reject (Auth_Failed);
      end if;
      declare
         Text     : constant String := Body_Bounded.To_String (Reply.Body_Text);
         Id_Buf   : String (1 .. 64) := [others => ' '];
         Name_Buf : String (1 .. Max_Name_Chars + 64) := [others => ' '];
         Id_Len, Name_Len : Natural := 0;
         Props    : Property_Vector;
         Count    : Natural := 0;
         Ok       : Boolean := False;
      begin
         Parse_Document (Text, Id_Buf, Id_Len, Name_Buf, Name_Len,
                         Props, Count, Ok);
         if not Ok then
            return Map_Reject (Auth_Service_Unavailable);
         end if;
         if Id_Len /= 32
           or else not Is_32_Hex
             (Id_Buf (Id_Buf'First .. Id_Buf'First + Id_Len - 1))
         then
            return Map_Reject (Auth_Service_Unavailable);
         end if;
         if Name_Len = 0 or else Name_Len > Max_Name_Chars then
            return Map_Reject (Auth_Service_Unavailable);
         end if;
         declare
            P : Auth_Profile;
         begin
            P.Id := Hex_To_Uuid
              (Id_Buf (Id_Buf'First .. Id_Buf'First + 31));
            P.Name :=
              Profile_Name_Bounded.To_Bounded_String
                (Name_Buf (Name_Buf'First .. Name_Buf'First + Name_Len - 1));
            P.Properties := Props;
            P.Prop_Count := Count;
            return (Kind => Accepted, Profile => P);
         end;
      end;
   end Interpret_Reply;

end Adacraft.Auth.Session;
