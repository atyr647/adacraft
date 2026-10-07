with Ada.Streams;
with Interfaces;
with Adacraft.Protocol.Frame;
with Adacraft.Protocol.Varnum;
with Adacraft.Protocol.State;
with Differential.Net;

package body Differential.Runner is

   package P renames Adacraft.Protocol;
   package St renames Adacraft.Protocol.State;
   use type St.Result_Kind;
   use type P.Status_Kind;
   use type Interfaces.Integer_32;
   use type P.Varnum.Status_Type;

   function To_Octets (Raw : Corpus.Byte_Vectors.Vector) return P.Octets is
      R : P.Octets (1 .. Natural (Raw.Length));
   begin
      for I in R'Range loop
         R (I) := P.Octet (Raw.Element (I));
      end loop;
      return R;
   end To_Octets;

   --  Reads a VarInt through Varnum at Pos; advances Pos.
   procedure Read_Var
     (Buf : P.Octets;
      Pos : in out Positive;
      Val : out Natural;
      Ok  : out Boolean)
   is
      V      : Interfaces.Integer_32;
      Used   : Natural;
      Status : P.Varnum.Status_Type;
   begin
      Val := 0;
      Ok := False;
      if Pos > Buf'Last then
         return;
      end if;
      P.Varnum.Decode (Buf, Pos, V, Used, Status);
      if Status /= P.Varnum.Ok or else V < 0 then
         return;
      end if;
      Pos := Pos + Used;
      Val := Natural (V);
      Ok := True;
   end Read_Var;

   --  Validates a serverbound step as exactly one frame; returns its id
   --  and the position of the first payload byte.
   procedure Prepare
     (S       : Corpus.Step;
      Id      : out Natural;
      Payload : out Positive)
   is
      Buf : constant P.Octets := To_Octets (S.Raw);
   begin
      Id := 0;
      Payload := 1;
      if Buf'Length = 0 then
         raise Step_Encoding_Error;
      end if;
      declare
         F : constant P.Frame.Frame_Decode := P.Frame.Decode_Frame (Buf, 1);
      begin
         if F.Status /= P.Ok or else F.Next /= Buf'Last + 1 then
            raise Step_Encoding_Error;
         end if;
         Id := F.Packet_Id;
         Payload := F.Payload_First;
      end;
      if S.Has_Packet_Id then
         Id := S.Packet_Id;
      end if;
   end Prepare;

   function Intent_Of
     (Raw : Corpus.Byte_Vectors.Vector; Payload : Positive)
      return St.Handshake_Intent
   is
      Buf : constant P.Octets := To_Octets (Raw);
      Pos : Positive := Payload;
      V   : Natural;
      Ok  : Boolean;
   begin
      Read_Var (Buf, Pos, V, Ok);           --  protocol version
      if not Ok then
         return 0;
      end if;
      Read_Var (Buf, Pos, V, Ok);           --  address length
      if not Ok or else Pos + V + 2 > Buf'Last + 1 then
         return 0;
      end if;
      Pos := Pos + V + 2;                   --  address, port
      Read_Var (Buf, Pos, V, Ok);
      if not Ok then
         return 0;
      end if;
      return St.Handshake_Intent (V);
   end Intent_Of;

   procedure Run
     (Host       : String;
      Port       : Natural;
      Timeout_Ms : Natural;
      Sc         : Corpus.Scenario;
      Result     : out Obs.Observation_Vectors.Vector)
   is
      use Ada.Streams;
      Conn  : Net.Connection;
      Ok    : Boolean;
      State : St.Connection_State := Sc.Initial;
      Id    : Natural;
      Pay   : Positive;
      Send_Ok : Boolean := True;
   begin
      Result.Clear;

      --  Validate every step before touching the network.
      for S of Sc.Steps loop
         if S.Dir = Corpus.Serverbound then
            Prepare (S, Id, Pay);
         end if;
      end loop;

      Net.Connect (Conn, Host, Port, Timeout_Ms, Ok);
      if not Ok then
         Result.Append ((Kind => Obs.Connect_Failed));
         return;
      end if;

      for S of Sc.Steps loop
         if S.Dir = Corpus.Serverbound then
            Prepare (S, Id, Pay);
            if Send_Ok then
               declare
                  Data : Stream_Element_Array
                    (1 .. Stream_Element_Offset (S.Raw.Length));
               begin
                  for I in Data'Range loop
                     Data (I) := Stream_Element (S.Raw.Element (Positive (I)));
                  end loop;
                  Send_Ok := Net.Send (Conn, Data);
               end;
            end if;
            declare
               Ev : St.Packet_Event :=
                 (Direction => St.Serverbound,
                  Id        => St.Packet_Id (Id),
                  Intent    => 0);
            begin
               if State = St.Handshake and then Id = 0 then
                  Ev.Intent := Intent_Of (S.Raw, Pay);
               end if;
               declare
                  T : constant St.Transition_Result :=
                    St.Transition (State, Ev);
               begin
                  if T.Kind /= St.Rejected then
                     State := T.Next_State;
                  end if;
               end;
            end;
         end if;
      end loop;

      while Natural (Result.Length) < Max_Observations loop
         declare
            R : Net.Receive_Result;
         begin
            Net.Receive_Frame (Conn, Timeout_Ms, R);
            case R.Kind is
               when Net.Frame_Received =>
                  declare
                     Pid : constant St.Packet_Id := St.Packet_Id (R.Packet_Id);
                     T   : constant St.Transition_Result :=
                       St.Transition
                         (State,
                          (Direction => St.Clientbound,
                           Id => Pid, Intent => 0));
                  begin
                     if T.Kind = St.Rejected then
                        Result.Append
                          ((Kind => Obs.Invalid_In_State,
                            Bad_State => State, Bad_Id => Pid));
                     else
                        Result.Append
                          ((Kind => Obs.Packet_Obs, State => State,
                            Direction => St.Clientbound, Id => Pid));
                        State := T.Next_State;
                     end if;
                  end;
               when Net.Closed =>
                  Result.Append ((Kind => Obs.Closed_By_Peer));
                  exit;
               when Net.Timed_Out =>
                  Result.Append ((Kind => Obs.Receive_Timeout));
                  exit;
               when Net.Bad_Frame =>
                  Result.Append ((Kind => Obs.Malformed, Reason => R.Reason));
                  exit;
            end case;
         end;
      end loop;
      Net.Close (Conn);
   exception
      when others =>
         Net.Close (Conn);
         raise;
   end Run;

end Differential.Runner;
