with Adacraft.Auth;
with Adacraft.Protocol.Buffer;
with Adacraft.Protocol.Ids;
with Interfaces;

package body Adacraft.Protocol.Login is

   use type Auth.Server_Auth_Mode;
   use type Adacraft.Protocol.Status_Kind;
   --  VarInt decoding for Login Start goes through Buffer.Decode_String
   --  (which decodes the length prefix via Varnum); no local continuation-bit
   --  logic here. Protocol/version pins, where needed, come from
   --  Adacraft.Protocol.Version, not literals.

   function Is_Valid_Name (Name : String) return Boolean is
   begin
      if Name'Length < 1 or else Name'Length > Max_Name_Length then
         return False;
      end if;
      for Ch of Name loop
         if not Is_Valid_Name_Char (Ch) then
            return False;
         end if;
      end loop;
      return True;
   end Is_Valid_Name;

   function Null_Identity return Auth.Player_Identity is
     ((Kind => Auth.Offline, UUID => (others => 0),
       Name_Length => 0, Name => (others => ' ')));

   function Closed_Session return Login_Session is
     ((State => Closed, Success_Sent => False,
       Has_Identity => False, Identity => Null_Identity));

   function Decode_Login_Start (Payload : Octets) return Login_Start is
      Result : Login_Start;
      Dec    : Buffer.String_Decode;
   begin
      if Payload'Length = 0 then
         Result.Status := Malformed;
         return Result;
      end if;
      Dec := Buffer.Decode_String (Payload, Payload'First, Max_Name_Length);
      --  Buffer.Decode_String rejects prefix > bound (Rejected) and
      --  prefix > remaining (Need_More => truncated). Both are Malformed.
      if Dec.Status /= Adacraft.Protocol.Ok then
         Result.Status := Malformed;
         return Result;
      end if;
      if Dec.Length < 1 or else Dec.Length > Max_Name_Length then
         Result.Status := Malformed;
         return Result;
      end if;
      --  Must have exactly 16 bytes remaining for UUID, no trailing bytes.
      if Dec.Next > Payload'Last then
         Result.Status := Malformed;
         return Result;
      end if;
      if Payload'Last - Dec.Next + 1 /= 16 then
         Result.Status := Malformed;
         return Result;
      end if;
      declare
         Name : String (1 .. Dec.Length);
      begin
         for I in 1 .. Dec.Length loop
            Name (I) := Dec.Text (I);
         end loop;
         for I in 1 .. 16 loop
            Result.Client_Uuid (I) := Payload (Dec.Next + I - 1);
         end loop;
         Result.Name_Len := Dec.Length;
         for I in 1 .. Dec.Length loop
            Result.Name (I) := Name (I);
         end loop;
         if not Is_Valid_Name (Name) then
            Result.Status := Invalid_Name;
         else
            Result.Status := Ok;
         end if;
         return Result;
      end;
   end Decode_Login_Start;

   function Offline_UUID (Name : String) return Auth.Digest is
   begin
      return Auth.Offline_UUID (Name);
   end Offline_UUID;

   function Offline_Identity (Name : String) return Auth.Player_Identity is
      D  : constant Auth.Digest := Offline_UUID (Name);
      Id : Auth.Player_Identity := Null_Identity;
   begin
      Id.UUID := D;
      Id.Name_Length := Name'Length;
      for I in 1 .. Name'Length loop
         Id.Name (I) := Name (Name'First + I - 1);
      end loop;
      return Id;
   end Offline_Identity;

   function Is_Login_Acknowledged (Payload : Octets) return Boolean is
   begin
      return Payload'Length = 0;
   end Is_Login_Acknowledged;

   function To_Reason (R : String) return Start_Result is
      Result : Start_Result;
   begin
      Result.Outcome := Need_Disconnect_Close;
      Result.Session := Closed_Session;
      Result.Identity := Null_Identity;
      Result.Reason_Len :=
        (if R'Length > Result.Reason'Length
         then Result.Reason'Length else R'Length);
      for I in 1 .. Result.Reason_Len loop
         Result.Reason (I) := R (R'First + I - 1);
      end loop;
      return Result;
   end To_Reason;

   procedure Set_Reason (Buf : in out Start_Result; R : String) is
   begin
      Buf.Reason_Len :=
        (if R'Length > Buf.Reason'Length
         then Buf.Reason'Length else R'Length);
      for I in 1 .. Buf.Reason_Len loop
         Buf.Reason (I) := R (R'First + I - 1);
      end loop;
   end Set_Reason;

   function Handle_Start
     (S : Login_Session; Payload : Octets;
      Mode : Auth.Server_Auth_Mode) return Start_Result
   is
      Result : Start_Result;
      Dec : constant Login_Start := Decode_Login_Start (Payload);
   begin
      --  Only in Await_Start; duplicate Start or late Start closes.
      if S.State /= Await_Start then
         Result.Outcome := Protocol_Error_Close;
         Result.Session := Closed_Session;
         Result.Identity := Null_Identity;
         Result.Reason_Len := 0;
         return Result;
      end if;
      if Mode = Auth.Online then
         Result.Outcome := Refuse_Online;
         Result.Session := Closed_Session;
         Result.Identity := Null_Identity;
         Set_Reason (Result, Online_Not_Yet_Supported_Reason);
         return Result;
      end if;
      case Dec.Status is
         when Malformed =>
            Result.Outcome := Need_Disconnect_Close;
            Result.Session := Closed_Session;
            Result.Identity := Null_Identity;
            Set_Reason (Result, Malformed_Start_Reason);
            return Result;
         when Invalid_Name =>
            Result.Outcome := Need_Disconnect_Close;
            Result.Session := Closed_Session;
            Result.Identity := Null_Identity;
            Set_Reason (Result, Invalid_Name_Reason);
            return Result;
         when Ok =>
            null;
      end case;
      declare
         N : String (1 .. Dec.Name_Len);
      begin
         for I in 1 .. Dec.Name_Len loop
            N (I) := Dec.Name (I);
         end loop;
         Result.Identity := Offline_Identity (N);
      end;
      Result.Outcome := Ready_Success;
      Result.Session :=
        (State => Success_Sent, Success_Sent => True,
         Has_Identity => True, Identity => Result.Identity);
      Result.Reason_Len := 0;
      return Result;
   end Handle_Start;

   function Handle_Acknowledged
     (S : Login_Session; Payload : Octets) return Ack_Result
   is
      Result : Ack_Result;
   begin
      if S.State /= Success_Sent or else not S.Success_Sent then
         Result.Outcome := Protocol_Error_Close;
         Result.Session := Closed_Session;
         return Result;
      end if;
      if Payload'Length /= 0 then
         Result.Outcome := Protocol_Error_Close;
         Result.Session := Closed_Session;
         return Result;
      end if;
      Result.Outcome := To_Configuration;
      Result.Session :=
        (State => Configuration, Success_Sent => True,
         Has_Identity => True, Identity => S.Identity);
      return Result;
   end Handle_Acknowledged;

   procedure Encode_Login_Success
     (W : in out Buffer.Writer; Identity : Auth.Player_Identity)
   is
   begin
      Buffer.Put_Varint
        (W, Interfaces.Unsigned_32
           (Ids.Protocol_Id (Ids.Cb_Login_Login_Finished)));
      for I in 1 .. 16 loop
         Buffer.Put_Octet (W, Identity.UUID (I));
      end loop;
      declare
         Name : String (1 .. Identity.Name_Length);
      begin
         for I in 1 .. Identity.Name_Length loop
            Name (I) := Identity.Name (I);
         end loop;
         Buffer.Put_String (W, Name);
      end;
      Buffer.Put_Varint (W, 0);
   end Encode_Login_Success;

   procedure Encode_Login_Disconnect
     (W : in out Buffer.Writer; Reason : String)
   is
      JSON : constant String := "{""text"":""" & Reason & """}";
   begin
      Buffer.Put_Varint
        (W, Interfaces.Unsigned_32
           (Ids.Protocol_Id (Ids.Cb_Login_Login_Disconnect)));
      Buffer.Put_String (W, JSON);
   end Encode_Login_Disconnect;

   function Build_Login_Disconnect
     (Reason : String := Default_Disconnect_Reason) return Octets
   is
      W : Buffer.Writer (512);
   begin
      Encode_Login_Disconnect (W, Reason);
      if W.Failed or else W.Len = 0 then
         return (1 .. 2 => 0);
      end if;
      declare
         R : Octets (1 .. W.Len);
      begin
         for I in 1 .. W.Len loop
            R (I) := W.Data (I);
         end loop;
         return R;
      end;
   end Build_Login_Disconnect;

end Adacraft.Protocol.Login;
