with Interfaces;

package body Adacraft.Auth.Session is
   use type Interfaces.Unsigned_8;

   function Is_Hex (C : Character) return Boolean is
   begin
      return (C in '0' .. '9')
        or else (C in 'a' .. 'f')
        or else (C in 'A' .. 'F');
   end Is_Hex;

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
            if P + 1 > S'Last then
               return;
            end if;
            declare
               E : constant Character := S (P + 1);
               C : Character;
            begin
               case E is
                  when '"'    => C := '"';
                  when '\'    => C := '\';
                  when '/'    => C := '/';
                  when 'b'    => C := ASCII.BS;
                  when 'f'    => C := ASCII.FF;
                  when 'n'    => C := ASCII.LF;
                  when 'r'    => C := ASCII.CR;
                  when 't'    => C := ASCII.HT;
                  when 'u'    =>
                     --  Skip 4 hex digits; store placeholder.
                     if P + 5 > S'Last then
                        return;
                     end if;
                     for K in P + 2 .. P + 5 loop
                        if not Is_Hex (S (K)) then
                           return;
                        end if;
                     end loop;
                     C := '?';
                     if Out_Next > Cap then
                        return;
                     end if;
                     Buf (Out_Next) := C;
                     Out_Next := Out_Next + 1;
                     P := P + 6;
                     goto Continue_Loop;
                  when others =>
                     return;
               end case;
               if Out_Next > Cap then
                  return;
               end if;
               Buf (Out_Next) := C;
               Out_Next := Out_Next + 1;
               P := P + 2;
               <<Continue_Loop>>
               null;
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
            loop
               Skip_WS (S, P);
               if P > S'Last then
                  return;
               end if;
               if S (P) = '}' then
                  P := P + 1;
                  Ok := True;
                  return;
               end if;
               if S (P) /= '"' then
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
               Skip_Value (S, P, SOk);
               if not SOk then
                  return;
               end if;
               Skip_WS (S, P);
               if P > S'Last then
                  return;
               end if;
               if S (P) = ',' then
                  P := P + 1;
               elsif S (P) = '}' then
                  P := P + 1;
                  Ok := True;
                  return;
               else
                  return;
               end if;
            end loop;
         when '[' =>
            P := P + 1;
            Skip_WS (S, P);
            if P <= S'Last and then S (P) = ']' then
               P := P + 1;
               Ok := True;
               return;
            end if;
            loop
               Skip_Value (S, P, SOk);
               if not SOk then
                  return;
               end if;
               Skip_WS (S, P);
               if P > S'Last then
                  return;
               end if;
               if S (P) = ',' then
                  P := P + 1;
               elsif S (P) = ']' then
                  P := P + 1;
                  Ok := True;
                  return;
               else
                  return;
               end if;
            end loop;
         when 't' =>
            if P + 3 <= S'Last and then S (P .. P + 3) = "true" then
               P := P + 4;
               Ok := True;
            end if;
            return;
         when 'f' =>
            if P + 4 <= S'Last and then S (P .. P + 4) = "false" then
               P := P + 5;
               Ok := True;
            end if;
            return;
         when 'n' =>
            if P + 3 <= S'Last and then S (P .. P + 3) = "null" then
               P := P + 4;
               Ok := True;
            end if;
            return;
         when '-' | '0' .. '9' =>
            if S (P) = '-' then
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
               while P <= S'Last and then S (P) in '0' .. '9' loop
                  P := P + 1;
               end loop;
            else
               return;
            end if;
            if P <= S'Last and then S (P) = '.' then
               P := P + 1;
               if P > S'Last or else S (P) not in '0' .. '9' then
                  return;
               end if;
               while P <= S'Last and then S (P) in '0' .. '9' loop
                  P := P + 1;
               end loop;
            end if;
            if P <= S'Last and then (S (P) = 'e' or else S (P) = 'E') then
               P := P + 1;
               if P <= S'Last and then (S (P) = '+' or else S (P) = '-') then
                  P := P + 1;
               end if;
               if P > S'Last or else S (P) not in '0' .. '9' then
                  return;
               end if;
               while P <= S'Last and then S (P) in '0' .. '9' loop
                  P := P + 1;
               end loop;
            end if;
            Ok := True;
            return;
         when others =>
            return;
      end case;
   end Skip_Value;

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
            if P + 1 > S'Last then
               return;
            end if;
            if S (P + 1) = 'u' then
               if P + 5 > S'Last then
                  return;
               end if;
               for K in P + 2 .. P + 5 loop
                  if not Is_Hex (S (K)) then
                     return;
                  end if;
               end loop;
               P := P + 6;
            else
               case S (P + 1) is
                  when '"' | '\' | '/' | 'b' | 'f' | 'n' | 'r' | 't' =>
                     P := P + 2;
                  when others =>
                     return;
               end case;
            end if;
         elsif S (P) = '"' then
            P := P + 1;
            Ok := True;
            return;
         else
            P := P + 1;
         end if;
      end loop;
   end Skip_String;

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
            if not NSet or else not VSet then
               return;
            end if;
            if NLen = 0 or else NLen > Max_Prop_Chars
              or else VLen > Max_Prop_Chars
              or else (SSet and then SLen > Max_Prop_Chars)
            then
               return;
            end if;
            if Count + 1 > Max_Properties then
               return;
            end if;
            Props (Count + 1).Name :=
              Prop_Bounded.To_Bounded_String (N_Buf (1 .. NLen));
            Props (Count + 1).Value :=
              (if VLen = 0 then Prop_Bounded.Null_Bounded_String
               else Prop_Bounded.To_Bounded_String (V_Buf (1 .. VLen)));
            Props (Count + 1).Has_Sig := SSet;
            Props (Count + 1).Signature :=
              (if not SSet or else SLen = 0 then Prop_Bounded.Null_Bounded_String
               else Prop_Bounded.To_Bounded_String (S_Buf (1 .. SLen)));
            Ok := True;
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
         Parse_String (S, P, K_Buf, 1, KLen, KOk);
         if not KOk then
            return;
         end if;
         Skip_WS (S, P);
         if P > S'Last or else S (P) /= ':' then
            return;
         end if;
         P := P + 1;
         Skip_WS (S, P);
         if K_Buf (1 .. KLen) = "name" then
            Parse_String (S, P, N_Buf, 1, NLen, SOk);
            if not SOk then
               return;
            end if;
            NSet := True;
         elsif K_Buf (1 .. KLen) = "value" then
            Parse_String (S, P, V_Buf, 1, VLen, SOk);
            if not SOk then
               return;
            end if;
            VSet := True;
         elsif K_Buf (1 .. KLen) = "signature" then
            Parse_String (S, P, S_Buf, 1, SLen, SOk);
            if not SOk then
               return;
            end if;
            SSet := True;
         else
            --  Unknown key: value must be string per Mojang shape;
            --  accept and skip any value.
            if P <= S'Last and then S (P) = '"' then
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
         end if;
      end loop;
   end Parse_Property;

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
            P := P + 1;
            Skip_WS (S, P);
            if P <= S'Last then
               return; --  trailing garbage
            end if;
            if not Id_Set or else not Name_Set then
               return;
            end if;
            Id_Buf (1 .. Tmp_Id_Len) := Tmp_Id (1 .. Tmp_Id_Len);
            N_Buf (1 .. Tmp_N_Len) := Tmp_N (1 .. Tmp_N_Len);
            Id_Len := Tmp_Id_Len;
            N_Len := Tmp_N_Len;
            P_Count := Count;
            Ok := True;
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
            if S (P) = '}' then
               return; --  trailing comma invalid
            end if;
         end if;
         First := False;
         Parse_String (S, P, K_Buf, 1, KLen, KOk);
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
         if K_Buf (1 .. KLen) = "id" then
            Parse_String (S, P, Tmp_Id, 1, Tmp_Id_Len, SOk);
            if not SOk then
               return;
            end if;
            Id_Set := True;
         elsif K_Buf (1 .. KLen) = "name" then
            Parse_String (S, P, Tmp_N, 1, Tmp_N_Len, SOk);
            if not SOk then
               return;
            end if;
            Name_Set := True;
         elsif K_Buf (1 .. KLen) = "properties" then
            if Props_Seen then
               return;
            end if;
            Props_Seen := True;
            if S (P) /= '[' then
               return;
            end if;
            P := P + 1;
            Skip_WS (S, P);
            if P <= S'Last and then S (P) = ']' then
               P := P + 1;
            else
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
            end if;
         else
            --  Unknown top-level key: skip any JSON value.
            Skip_Value (S, P, SOk);
            if not SOk then
               return;
            end if;
         end if;
      end loop;
   end Parse_Document;

   function Map_No_Profile return Auth_Result is
   begin
      return (Kind => Rejected, Reason => Auth_Failed);
   end Map_No_Profile;

   function Map_Error return Auth_Result is
   begin
      return (Kind => Rejected, Reason => Auth_Service_Unavailable);
   end Map_Error;

   function Interpret_Reply (Reply : Http_Reply) return Auth_Result is
   begin
      if Reply.Transport_Failed then
         return Map_Error;
      end if;
      if Reply.Status = 204 then
         return Map_No_Profile;
      end if;
      if Reply.Status /= 200 then
         return Map_Error;
      end if;
      if Body_Bounded.Length (Reply.Body_Text) = 0 then
         return Map_No_Profile;
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
            return Map_Error;
         end if;
         if Id_Len /= 32 or else not Is_32_Hex (Id_Buf (1 .. Id_Len)) then
            return Map_Error;
         end if;
         if Name_Len = 0 or else Name_Len > Max_Name_Chars then
            return Map_Error;
         end if;
         declare
            P : Auth_Profile;
         begin
            P.Id := Hex_To_Uuid (Id_Buf (1 .. 32));
            P.Name :=
              Profile_Name_Bounded.To_Bounded_String (Name_Buf (1 .. Name_Len));
            P.Properties := Props;
            P.Prop_Count := Count;
            return (Kind => Accepted, Profile => P);
         end;
      end;
   end Interpret_Reply;

end Adacraft.Auth.Session;
