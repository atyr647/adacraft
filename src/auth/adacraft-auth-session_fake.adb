with Ada.Strings.Bounded;
with Interfaces;

package body Adacraft.Auth.Session_Fake is
   use type Interfaces.Unsigned_8;

   function Is_Hex (C : Character) return Boolean is
   begin
      return (C in '0' .. '9') or else (C in 'a' .. 'f') or else (C in 'A' .. 'F');
   end Is_Hex;

   function Nibble (C : Character) return Interfaces.Unsigned_8 is
   begin
      if C in '0' .. '9' then
         return Interfaces.Unsigned_8 (Character'Pos (C) - Character'Pos ('0'));
      elsif C in 'a' .. 'f' then
         return Interfaces.Unsigned_8 (Character'Pos (C) - Character'Pos ('a') + 10);
      else
         return Interfaces.Unsigned_8 (Character'Pos (C) - Character'Pos ('A') + 10);
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
      R : Uuid := [others => 0];
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

   function Skip_WS (S : String; P : Natural) return Natural is
      Q : Natural := P;
   begin
      while Q <= S'Last
        and then (S (Q) = ' ' or else S (Q) = ASCII.HT
                  or else S (Q) = ASCII.LF or else S (Q) = ASCII.CR)
      loop
         Q := Q + 1;
      end loop;
      return Q;
   end Skip_WS;

   --  Parse a JSON string starting at S (P) = '"'. On success Ok=True,
   --  Next is the index just past the closing quote and Value holds the
   --  decoded characters (\" and \\ style escapes collapsed to the
   --  escaped char; \uXXXX collapsed to '?'). Truncation-safe: over-long
   --  values set Truncated but still consume input for structure checks.
   procedure Parse_String
     (S         : String;
      P         : Natural;
      Next      : out Natural;
      Value     : out String;
      VLen      : out Natural;
      Truncated : out Boolean;
      Ok        : out Boolean)
   is
      K       : Natural;
      Next_At : Natural;
   begin
      Value := [Value'Range => ' '];
      VLen := 0;
      Truncated := False;
      Next := P;
      Ok := False;
      if P > S'Last or else S (P) /= '"' then
         return;
      end if;
      K := P + 1;
      Next_At := Value'First;
      while K <= S'Last loop
         if S (K) = '\' then
            if K >= S'Last then
               return;
            end if;
            if Next_At <= Value'Last then
               if S (K + 1) = 'u' then
                  Value (Next_At) := '?';
               else
                  Value (Next_At) := S (K + 1);
               end if;
               Next_At := Next_At + 1;
            else
               Truncated := True;
            end if;
            if S (K + 1) = 'u' then
               if K + 5 > S'Last then
                  return;
               end if;
               for H in 1 .. 4 loop
                  if not Is_Hex (S (K + 1 + H)) then
                     return;
                  end if;
               end loop;
               K := K + 6;
            else
               K := K + 2;
            end if;
         elsif S (K) = '"' then
            VLen := Next_At - Value'First;
            Next := K + 1;
            Ok := True;
            return;
         elsif S (K) = ASCII.LF or else S (K) = ASCII.CR then
            return;
         else
            if Next_At <= Value'Last then
               Value (Next_At) := S (K);
               Next_At := Next_At + 1;
            else
               Truncated := True;
            end if;
            K := K + 1;
         end if;
      end loop;
   end Parse_String;

   --  Skip one JSON value starting at P. Validates structure so broken
   --  JSON fails closed. Next is just past the value.
   procedure Skip_Value (S : String; P : Natural; Next : out Natural; Ok : out Boolean) is
      Q    : Natural;
      Tmp  : String (1 .. 8) := [others => ' '];
      TL   : Natural;
      TR   : Boolean;
      SOK  : Boolean;
      Depth_O : Natural := 0;
      Depth_A : Natural := 0;
      In_Str  : Boolean := False;
      Esc     : Boolean := False;
   begin
      Next := P;
      Ok := False;
      if P > S'Last then
         return;
      end if;
      Q := Skip_WS (S, P);
      if Q > S'Last then
         return;
      end if;
      case S (Q) is
         when '"' =>
            Parse_String (S, Q, Next, Tmp, TL, TR, SOK);
            Ok := SOK;
            return;
         when '{' | '[' =>
            --  Raw scan with string awareness; validates brackets/quotes.
            for I in Q .. S'Last loop
               declare
                  C : constant Character := S (I);
               begin
                  if In_Str then
                     if Esc then
                        Esc := False;
                     elsif C = '\' then
                        Esc := True;
                     elsif C = '"' then
                        In_Str := False;
                     end if;
                  else
                     if C = '"' then
                        In_Str := True;
                     elsif C = '{' then
                        Depth_O := Depth_O + 1;
                     elsif C = '[' then
                        Depth_A := Depth_A + 1;
                     elsif C = '}' then
                        if Depth_O = 0 then
                           return;
                        end if;
                        Depth_O := Depth_O - 1;
                        if Depth_O = 0 and then Depth_A = 0 then
                           Next := I + 1;
                           Ok := True;
                           return;
                        end if;
                     elsif C = ']' then
                        if Depth_A = 0 then
                           return;
                        end if;
                        Depth_A := Depth_A - 1;
                        if Depth_O = 0 and then Depth_A = 0 then
                           Next := I + 1;
                           Ok := True;
                           return;
                        end if;
                     end if;
                  end if;
               end;
            end loop;
            return;
         when 't' =>
            if Q + 3 <= S'Last and then S (Q .. Q + 3) = "true" then
               Next := Q + 4;
               Ok := True;
            end if;
            return;
         when 'f' =>
            if Q + 4 <= S'Last and then S (Q .. Q + 4) = "false" then
               Next := Q + 5;
               Ok := True;
            end if;
            return;
         when 'n' =>
            if Q + 3 <= S'Last and then S (Q .. Q + 3) = "null" then
               Next := Q + 4;
               Ok := True;
            end if;
            return;
         when '-' | '0' .. '9' =>
            Q := Q + 1;
            while Q <= S'Last
              and then (S (Q) in '0' .. '9' | '.' | 'e' | 'E' | '+' | '-')
            loop
               Q := Q + 1;
            end loop;
            Next := Q;
            Ok := True;
            return;
         when others =>
            return;
      end case;
   end Skip_Value;

   --  Parse one property object at P ('{'). Consumes through '}'.
   procedure Parse_Property
     (S    : String;
      P    : Natural;
      Next : out Natural;
      Prop : out Auth_Property;
      Ok   : out Boolean)
   is
      Q         : Natural;
      Key_Buf   : String (1 .. 32) := [others => ' '];
      Key_Len   : Natural := 0;
      Key_Tr    : Boolean := False;
      Key_Ok    : Boolean := False;
      Val_Buf   : String (1 .. Max_Prop_Chars) := [others => ' '];
      Val_Len   : Natural := 0;
      Val_Tr    : Boolean := False;
      Val_Ok    : Boolean := False;
      V_Next    : Natural;
      N_Found   : Boolean := False;
      V_Found   : Boolean := False;
      S_Found   : Boolean := False;
      N_Buf     : String (1 .. Max_Prop_Chars) := [others => ' '];
      N_Len     : Natural := 0;
      V_Buf     : String (1 .. Max_Prop_Chars) := [others => ' '];
      V_Len2    : Natural := 0;
      Sg_Buf    : String (1 .. Max_Prop_Chars) := [others => ' '];
      Sg_Len    : Natural := 0;
      First     : Boolean := True;
   begin
      Prop := (Name      => Prop_Bounded.Null_Bounded_String,
               Value     => Prop_Bounded.Null_Bounded_String,
               Has_Sig   => False,
               Signature => Prop_Bounded.Null_Bounded_String);
      Next := P;
      Ok := False;
      if P > S'Last or else S (P) /= '{' then
         return;
      end if;
      Q := Skip_WS (S, P + 1);
      if Q <= S'Last and then S (Q) = '}' then
         Next := Q + 1;
         Ok := False; --  empty object: missing name/value
         return;
      end if;
      loop
         Q := Skip_WS (S, Q);
         if Q > S'Last or else S (Q) /= '"' then
            return;
         end if;
         Parse_String (S, Q, V_Next, Key_Buf, Key_Len, Key_Tr, Key_Ok);
         if not Key_Ok or else Key_Tr then
            return;
         end if;
         Q := Skip_WS (S, V_Next);
         if Q > S'Last or else S (Q) /= ':' then
            return;
         end if;
         Q := Skip_WS (S, Q + 1);
         if Q > S'Last then
            return;
         end if;
         if S (Q) = '"' then
            Parse_String (S, Q, V_Next, Val_Buf, Val_Len, Val_Tr, Val_Ok);
            if not Val_Ok or else Val_Tr then
               return;
            end if;
            declare
               K : constant String := Key_Buf (1 .. Key_Len);
            begin
               if K = "name" then
                  if Val_Len = 0 then
                     return;
                  end if;
                  N_Buf (1 .. Val_Len) := Val_Buf (1 .. Val_Len);
                  N_Len := Val_Len;
                  N_Found := True;
               elsif K = "value" then
                  if Val_Len = 0 then
                     return;
                  end if;
                  V_Buf (1 .. Val_Len) := Val_Buf (1 .. Val_Len);
                  V_Len2 := Val_Len;
                  V_Found := True;
               elsif K = "signature" then
                  Sg_Buf (1 .. Val_Len) := (if Val_Len > 0 then Val_Buf (1 .. Val_Len) else "");
                  Sg_Len := Val_Len;
                  S_Found := True;
               end if;
            end;
            Q := V_Next;
         else
            return; --  property fields must be strings
         end if;
         Q := Skip_WS (S, Q);
         if Q > S'Last then
            return;
         end if;
         First := False;
         if S (Q) = ',' then
            Q := Q + 1;
         elsif S (Q) = '}' then
            Next := Q + 1;
            exit;
         else
            return;
         end if;
      end loop;
      if not N_Found or else not V_Found then
         Ok := False;
         return;
      end if;
      Prop.Name := Prop_Bounded.To_Bounded_String (N_Buf (1 .. N_Len));
      Prop.Value := Prop_Bounded.To_Bounded_String (V_Buf (1 .. V_Len2));
      if S_Found then
         Prop.Has_Sig := True;
         Prop.Signature :=
           (if Sg_Len > 0 then Prop_Bounded.To_Bounded_String (Sg_Buf (1 .. Sg_Len))
            else Prop_Bounded.Null_Bounded_String);
      end if;
      Ok := True;
   end Parse_Property;

   --  Parse the properties array at P ('['). Enforces Max_Properties.
   procedure Parse_Properties
     (S     : String;
      P     : Natural;
      Next  : out Natural;
      Props : out Property_Vector;
      Count : out Natural;
      Ok    : out Boolean;
      Over  : out Boolean)
   is
      Q     : Natural;
      N     : Natural := 0;
      PNext : Natural;
      Pr    : Auth_Property;
      POk   : Boolean;
   begin
      Props := [others => (Name      => Prop_Bounded.Null_Bounded_String,
                           Value     => Prop_Bounded.Null_Bounded_String,
                           Has_Sig   => False,
                           Signature => Prop_Bounded.Null_Bounded_String)];
      Count := 0;
      Next := P;
      Ok := False;
      Over := False;
      if P > S'Last or else S (P) /= '[' then
         return;
      end if;
      Q := Skip_WS (S, P + 1);
      if Q <= S'Last and then S (Q) = ']' then
         Next := Q + 1;
         Ok := True;
         return;
      end if;
      loop
         Q := Skip_WS (S, Q);
         if Q > S'Last or else S (Q) /= '{' then
            return;
         end if;
         N := N + 1;
         if N > Max_Properties then
            Over := True;
            return;
         end if;
         Parse_Property (S, Q, PNext, Pr, POk);
         if not POk then
            return;
         end if;
         Props (N) := Pr;
         Q := Skip_WS (S, PNext);
         if Q > S'Last then
            return;
         end if;
         if S (Q) = ',' then
            Q := Q + 1;
         elsif S (Q) = ']' then
            Next := Q + 1;
            Count := N;
            Ok := True;
            return;
         else
            return;
         end if;
      end loop;
   end Parse_Properties;

   function Interpret_Reply (Reply : Http_Reply) return Auth_Result is
   begin
      if Reply.Transport_Failed then
         return (Kind => Rejected, Reason => Auth_Service_Unavailable);
      end if;
      if Reply.Status = 204 then
         return (Kind => Rejected, Reason => Auth_Failed);
      end if;
      if Reply.Status /= 200 then
         return (Kind => Rejected, Reason => Auth_Service_Unavailable);
      end if;
      if Body_Bounded.Length (Reply.Body_Text) = 0 then
         return (Kind => Rejected, Reason => Auth_Failed);
      end if;
      declare
         Text : constant String := Body_Bounded.To_String (Reply.Body_Text);
         Pos        : Natural;
         Id_Buf     : String (1 .. 64) := [others => ' '];
         Id_Len     : Natural := 0;
         Id_Tr      : Boolean := False;
         Id_Ok      : Boolean := False;
         Name_Buf   : String (1 .. Max_Name_Chars + 64) := [others => ' '];
         Name_Len   : Natural := 0;
         Name_Tr    : Boolean := False;
         Name_Ok    : Boolean := False;
         Key_Buf    : String (1 .. 32) := [others => ' '];
         Key_Len    : Natural := 0;
         Key_Tr     : Boolean := False;
         Key_Ok     : Boolean := False;
         Key_Next   : Natural;
         Val_Next   : Natural;
         Val_Ok     : Boolean;
         Id_Found   : Boolean := False;
         Name_Found : Boolean := False;
         Props      : Property_Vector;
         Prop_N     : Natural := 0;
         Props_Ok   : Boolean := True;
         Props_Over : Boolean := False;
         Props_Seen : Boolean := False;
         P          : Auth_Profile;
      begin
         Pos := Skip_WS (Text, Text'First);
         if Pos > Text'Last or else Text (Pos) /= '{' then
            return (Kind => Rejected, Reason => Auth_Service_Unavailable);
         end if;
         Pos := Skip_WS (Text, Pos + 1);
         if Pos <= Text'Last and then Text (Pos) = '}' then
            Pos := Skip_WS (Text, Pos + 1);
            if Pos <= Text'Last then
               return (Kind => Rejected, Reason => Auth_Service_Unavailable);
            end if;
            return (Kind => Rejected, Reason => Auth_Service_Unavailable);
         end if;
         loop
            Pos := Skip_WS (Text, Pos);
            if Pos > Text'Last or else Text (Pos) /= '"' then
               return (Kind => Rejected, Reason => Auth_Service_Unavailable);
            end if;
            Parse_String (Text, Pos, Key_Next, Key_Buf, Key_Len, Key_Tr, Key_Ok);
            if not Key_Ok or else Key_Tr then
               return (Kind => Rejected, Reason => Auth_Service_Unavailable);
            end if;
            Pos := Skip_WS (Text, Key_Next);
            if Pos > Text'Last or else Text (Pos) /= ':' then
               return (Kind => Rejected, Reason => Auth_Service_Unavailable);
            end if;
            Pos := Skip_WS (Text, Pos + 1);
            if Pos > Text'Last then
               return (Kind => Rejected, Reason => Auth_Service_Unavailable);
            end if;
            declare
               K : constant String := Key_Buf (1 .. Key_Len);
            begin
               if K = "id" then
                  if Text (Pos) /= '"' then
                     return (Kind => Rejected, Reason => Auth_Service_Unavailable);
                  end if;
                  Parse_String (Text, Pos, Val_Next, Id_Buf, Id_Len, Id_Tr, Id_Ok);
                  if not Id_Ok then
                     return (Kind => Rejected, Reason => Auth_Service_Unavailable);
                  end if;
                  Id_Found := True;
                  Pos := Val_Next;
               elsif K = "name" then
                  if Text (Pos) /= '"' then
                     return (Kind => Rejected, Reason => Auth_Service_Unavailable);
                  end if;
                  Parse_String (Text, Pos, Val_Next, Name_Buf, Name_Len, Name_Tr, Name_Ok);
                  if not Name_Ok then
                     return (Kind => Rejected, Reason => Auth_Service_Unavailable);
                  end if;
                  Name_Found := True;
                  Pos := Val_Next;
               elsif K = "properties" then
                  if Text (Pos) /= '[' then
                     return (Kind => Rejected, Reason => Auth_Service_Unavailable);
                  end if;
                  Parse_Properties (Text, Pos, Val_Next, Props, Prop_N, Props_Ok, Props_Over);
                  if Props_Over or else not Props_Ok then
                     return (Kind => Rejected, Reason => Auth_Service_Unavailable);
                  end if;
                  Props_Seen := True;
                  Pos := Val_Next;
               else
                  Skip_Value (Text, Pos, Val_Next, Val_Ok);
                  if not Val_Ok then
                     return (Kind => Rejected, Reason => Auth_Service_Unavailable);
                  end if;
                  Pos := Val_Next;
               end if;
            end;
            Pos := Skip_WS (Text, Pos);
            if Pos > Text'Last then
               return (Kind => Rejected, Reason => Auth_Service_Unavailable);
            end if;
            if Text (Pos) = ',' then
               Pos := Pos + 1;
            elsif Text (Pos) = '}' then
               Pos := Skip_WS (Text, Pos + 1);
               if Pos <= Text'Last then
                  return (Kind => Rejected, Reason => Auth_Service_Unavailable);
               end if;
               exit;
            else
               return (Kind => Rejected, Reason => Auth_Service_Unavailable);
            end if;
         end loop;
         if not Id_Found or else not Name_Found then
            return (Kind => Rejected, Reason => Auth_Service_Unavailable);
         end if;
         if Id_Tr or else not Id_Ok or else Id_Len /= 32
           or else not Is_32_Hex (Id_Buf (1 .. Id_Len))
         then
            return (Kind => Rejected, Reason => Auth_Service_Unavailable);
         end if;
         if Name_Tr or else not Name_Ok or else Name_Len = 0
           or else Name_Len > Max_Name_Chars
         then
            return (Kind => Rejected, Reason => Auth_Service_Unavailable);
         end if;
         P.Id := Hex_To_Uuid (Id_Buf (1 .. 32));
         P.Name := Profile_Name_Bounded.To_Bounded_String (Name_Buf (1 .. Name_Len));
         if Props_Seen then
            P.Properties := Props;
            P.Prop_Count := Prop_N;
         else
            P.Prop_Count := 0;
         end if;
         return (Kind => Accepted, Profile => P);
      end;
   end Interpret_Reply;

   overriding function Has_Joined
     (Self        : in out Fake_Check;
      Username    : Adacraft.Auth.Session_Fake.Username;
      Server_Hash : Adacraft.Auth.Session_Fake.Server_Hash;
      Client_Ip   : Optional_Ip) return Auth_Result
   is
   begin
      Self.Last_Username := Username;
      Self.Last_Hash := Server_Hash;
      Self.Last_Ip := Client_Ip;
      Self.Has_Last := True;
      if Self.Call_Count < Natural'Last then
         Self.Call_Count := Self.Call_Count + 1;
      end if;

      case Self.Mode is
         when Return_Accepted =>
            return (Kind => Accepted, Profile => Self.Scripted_Profile);
         when Fail_Transport =>
            return Interpret_Reply (Http_Reply'(Transport_Failed => True));
         when Replay_Reply =>
            return Interpret_Reply
              (Http_Reply'(Transport_Failed => False,
                           Status           => Self.Scripted_Status,
                           Body_Text        => Self.Scripted_Body));
      end case;
   end Has_Joined;

end Adacraft.Auth.Session_Fake;
