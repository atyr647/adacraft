with Ada.Streams;
with Adacraft.Protocol.Frame;
with Differential.Capture.Wire;
with GNAT.Sockets;

package body Differential.Capture is

   function Make_Target (Host : String; Port : Natural) return Target_Info is
   begin
      return (Host => To_Unbounded_String (Host), Port => Port);
   end Make_Target;

   function Scenario_Name (S : Scenario) return String is
   begin
      return To_String (S.Name);
   end Scenario_Name;

   function Empty_Provider return Scenario_List is
   begin
      return Scenario_Vectors.Empty_Vector;
   end Empty_Provider;

   function To_Direction (D : Adacraft.Protocol.State.Packet_Direction)
     return Transcript.Direction_Kind
   is
   begin
      if D = Adacraft.Protocol.State.Serverbound then
         return Transcript.Serverbound;
      else
         return Transcript.Clientbound;
      end if;
   end To_Direction;

   procedure Append_Entry
     (T   : in out Transcript.Transcript;
      St  : Adacraft.Protocol.State.Connection_State;
      Dir : Transcript.Direction_Kind;
      Id  : Natural)
   is
      Item : Transcript.Transcript_Entry;
   begin
      Item.State := St;
      Item.Direction := Dir;
      Item.Packet_Id := Id;
      Transcript.Append (T, Item);
   end Append_Entry;

   function Next_State
     (Current   : Adacraft.Protocol.State.Connection_State;
      Dir       : Adacraft.Protocol.State.Packet_Direction;
      Id        : Natural;
      Intent    : Integer) return Adacraft.Protocol.State.Connection_State
   is
      use Adacraft.Protocol.State;
      Ev : constant Packet_Event :=
        (Direction => Dir,
         Id        => Packet_Id (Id),
         Intent    => Handshake_Intent (Intent));
      R : constant Transition_Result := Transition (Current, Ev);
   begin
      if R.Kind = Rejected then
         return Current;
      else
         return R.Next_State;
      end if;
   end Next_State;

   procedure Capture_For_Target
     (Host     : String;
      Port     : Natural;
      Item     : Scenario;
      Result   : out Transcript.Transcript;
      Initial  : Adacraft.Protocol.State.Connection_State :=
        Adacraft.Protocol.State.Handshake)
   is
      Sock    : GNAT.Sockets.Socket_Type;
      Current : Adacraft.Protocol.State.Connection_State := Initial;
      Ok      : Boolean := False;
   begin
      Transcript.Clear (Result);
      Result.Outcome := Transcript.Completed;
      Wire.Open (Host, Port, Sock, Ok);
      if not Ok then
         Transcript.Set_Outcome (Result, Transcript.Connect_Failure);
         return;
      end if;
      --  Send each serverbound packet: minimal body holding the id only.
      --  Real payload encoding lands with the corpus loader (Q1).
      for I in 0 .. Natural (Item.Items.Length) - 1 loop
         declare
            It   : constant Serverbound_Item := Item.Items.Element (I);
            Body : Adacraft.Protocol.Frame.Byte_Array (1 .. 1);
            Sent_Ok : Boolean := False;
         begin
            Body (1) := Ada.Streams.Stream_Element (It.Packet_Id mod 128);
            Append_Entry (Result, Current, Transcript.Serverbound,
              It.Packet_Id);
            Current := Next_State (Current,
              Adacraft.Protocol.State.Serverbound, It.Packet_Id, It.Intent);
            Wire.Send_Body (Sock, Body, Sent_Ok);
            if not Sent_Ok then
               Transcript.Set_Outcome (Result, Transcript.Peer_Closed);
               exit;
            end if;
         end;
      end loop;
      --  Read clientbound frames until the wire reports a terminal outcome.
      if Result.Outcome = Transcript.Completed then
         declare
            Data : Wire.Recv_Data;
         begin
            Wire.Recv_Until_Terminal (Sock, Data);
            for I in 0 .. Natural (Data.Ids.Length) - 1 loop
               declare
                  Id : constant Natural := Data.Ids.Element (I);
               begin
                  Append_Entry (Result, Current,
                    Transcript.Clientbound, Id);
                  Current := Next_State (Current,
                    Adacraft.Protocol.State.Clientbound, Id, 0);
               end;
            end loop;
            Transcript.Set_Outcome (Result, Data.Outcome);
         end;
      end if;
      Wire.Close (Sock);
   exception
      when others =>
         Transcript.Set_Outcome (Result, Transcript.Protocol_Error);
   end Capture_For_Target;

end Differential.Capture;
