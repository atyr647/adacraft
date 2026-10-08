with Ada.Strings.Bounded;

package body Adacraft.Auth.Session_Fake is

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

   --  Extract a JSON string value for a top-level key "Key" (exact match).
   --  Returns Found=False when absent or malformed. Bounded linear scan.
   procedure Find_Key_String
     (S     : String;
      Key   : String;
      Value : out String;
      VLen  : out Natural;
      Found : out Boolean)
   is
      Pat : constant String := """" & Key & """";
      I   : Natural := S'First;
      J       : Natural;
      K       : Natural;
      Next_At : Natural;
   begin
      Value := [Value'Range => ' '];
      VLen := 0;
      Found := False;
      if S'Length = 0 or else Pat'Length > S'Length then
         return;
      end if;
      while I <= S'Last loop
         if I + Pat'Length - 1 <= S'Last and then S (I .. I + Pat'Length - 1) = Pat then
            J := Skip_WS (S, I + Pat'Length);
            if J <= S'Last and then S (J) = ':' then
               J := Skip_WS (S, J + 1);
               if J <= S'Last and then S (J) = '"' then
                  K := J + 1;
                  Next_At := Value'First;
                  while K <= S'Last loop
                     if S (K) = '\' and then K < S'Last then
                        if Next_At <= Value'Last then
                           Value (Next_At) := S (K + 1);
                           Next_At := Next_At + 1;
                        end if;
                        K := K + 2;
                     elsif S (K) = '"' then
                        VLen := Next_At - Value'First;
                        Found := True;
                        return;
                     else
                        if Next_At <= Value'Last then
                           Value (Next_At) := S (K);
                           Next_At := Next_At + 1;
                        end if;
                        K := K + 1;
                     end if;
                     exit when Next_At > Value'Last + 1;
                  end loop;
                  return;
               end if;
            end if;
         end if;
         I := I + 1;
      end loop;
   end Find_Key_String;

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
         Id_Buf   : String (1 .. 64) := [others => ' '];
         Name_Buf : String (1 .. Max_Name_Chars + 64) := [others => ' '];
         Id_Len, Name_Len : Natural := 0;
         Id_Found, Name_Found : Boolean := False;
      begin
         Find_Key_String (Text, "id", Id_Buf, Id_Len, Id_Found);
         Find_Key_String (Text, "name", Name_Buf, Name_Len, Name_Found);
         if not Id_Found or else not Name_Found then
            return (Kind => Rejected, Reason => Auth_Service_Unavailable);
         end if;
         if Id_Len /= 32 or else not Is_32_Hex (Id_Buf (1 .. Id_Len)) then
            return (Kind => Rejected, Reason => Auth_Service_Unavailable);
         end if;
         if Name_Len = 0 or else Name_Len > Max_Name_Chars then
            return (Kind => Rejected, Reason => Auth_Service_Unavailable);
         end if;
         declare
            P : Auth_Profile;
         begin
            P.Id := Hex_To_Uuid (Id_Buf (1 .. 32));
            P.Name := Profile_Name_Bounded.To_Bounded_String (Name_Buf (1 .. Name_Len));
            P.Prop_Count := 0;
            return (Kind => Accepted, Profile => P);
         end;
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
