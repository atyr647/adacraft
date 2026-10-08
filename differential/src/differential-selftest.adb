with Ada.Text_IO;
with Adacraft.Protocol.State;
with Differential.Compare;
with Differential.Transcript;

package body Differential.Selftest is

   use type Differential.Compare.Verdict;

   function Base_Result return Differential.Transcript.Transcript is
      T : Differential.Transcript.Transcript :=
        Differential.Transcript.Empty_Transcript
          (Differential.Transcript.Completed);
   begin
      Differential.Transcript.Append
        (T, (State     => Adacraft.Protocol.State.Handshake,
             Dir       => Differential.Transcript.Serverbound,
             Packet_Id => 0));
      Differential.Transcript.Append
        (T, (State     => Adacraft.Protocol.State.Status,
             Dir       => Differential.Transcript.Clientbound,
             Packet_Id => 1));
      return T;
   end Base_Result;

   function Clone_With_Outcome
     (T : Differential.Transcript.Transcript;
      O : Differential.Transcript.Terminal_Outcome)
      return Differential.Transcript.Transcript
   is
      N : Differential.Transcript.Transcript :=
        Differential.Transcript.Empty_Transcript (O);
   begin
      for I in 1 .. Differential.Transcript.Length (T) loop
         Differential.Transcript.Append
           (N, Differential.Transcript.Get (T, I));
      end loop;
      return N;
   end Clone_With_Outcome;

   function Check return Natural is
      use Ada.Text_IO;
      use type Differential.Transcript.Direction_T;
      use type Adacraft.Protocol.State.Connection_State;
      Base  : constant Differential.Transcript.Transcript := Base_Result;
      Same  : constant Differential.Transcript.Transcript := Base_Result;
      Passed : Natural := 0;
      Total  : constant Natural := 7;

      procedure Assert (Name : String; Got, Want : Differential.Compare.Verdict) is
      begin
         if Got = Want then
            Passed := Passed + 1;
         else
            Put_Line (Standard_Error, "selftest FAIL " & Name);
         end if;
      end Assert;
   begin
      --  1: identical -> MATCH.
      Assert ("identical",
        Differential.Compare.Compare (Base, Same),
        Differential.Compare.Match);
      --  2: different packet ID -> DIVERGE.
      declare
         B : Differential.Transcript.Transcript :=
           Clone_With_Outcome
             (Base, Differential.Transcript.Get_Outcome (Base));
         E : Differential.Transcript.Transcript_Entry :=
           Differential.Transcript.Get (B, 2);
      begin
         --  Rebuild with modified second entry.
         B := Differential.Transcript.Empty_Transcript
           (Differential.Transcript.Get_Outcome (Base));
         Differential.Transcript.Append
           (B, Differential.Transcript.Get (Base, 1));
         E.Packet_Id := E.Packet_Id + 1;
         Differential.Transcript.Append (B, E);
         Assert ("diff-id",
           Differential.Compare.Compare (Base, B),
           Differential.Compare.Diverge);
      end;
      --  3: different state -> DIVERGE.
      declare
         B : Differential.Transcript.Transcript :=
           Differential.Transcript.Empty_Transcript
             (Differential.Transcript.Get_Outcome (Base));
         E : Differential.Transcript.Transcript_Entry :=
           Differential.Transcript.Get (Base, 1);
      begin
         E.State := Adacraft.Protocol.State.Login;
         Differential.Transcript.Append (B, E);
         Differential.Transcript.Append
           (B, Differential.Transcript.Get (Base, 2));
         Assert ("diff-state",
           Differential.Compare.Compare (Base, B),
           Differential.Compare.Diverge);
      end;
      --  4: different direction -> DIVERGE.
      declare
         B : Differential.Transcript.Transcript :=
           Differential.Transcript.Empty_Transcript
             (Differential.Transcript.Get_Outcome (Base));
         E : Differential.Transcript.Transcript_Entry :=
           Differential.Transcript.Get (Base, 1);
      begin
         E.Dir := Differential.Transcript.Clientbound;
         Differential.Transcript.Append (B, E);
         Differential.Transcript.Append
           (B, Differential.Transcript.Get (Base, 2));
         Assert ("diff-direction",
           Differential.Compare.Compare (Base, B),
           Differential.Compare.Diverge);
      end;
      --  5: different length -> DIVERGE.
      declare
         B : Differential.Transcript.Transcript :=
           Differential.Transcript.Empty_Transcript
             (Differential.Transcript.Get_Outcome (Base));
      begin
         Differential.Transcript.Append
           (B, Differential.Transcript.Get (Base, 1));
         Assert ("diff-length",
           Differential.Compare.Compare (Base, B),
           Differential.Compare.Diverge);
      end;
      --  6: different outcome -> DIVERGE.
      declare
         B : constant Differential.Transcript.Transcript :=
           Clone_With_Outcome
             (Base, Differential.Transcript.Peer_Closed);
      begin
         Assert ("diff-outcome",
           Differential.Compare.Compare (Base, B),
           Differential.Compare.Diverge);
      end;
      --  7: payload-would-differ but tuples equal -> MATCH.
      --  No payload is stored, so a freshly built tuple-equal
      --  transcript must MATCH.
      declare
         B : Differential.Transcript.Transcript :=
           Differential.Transcript.Empty_Transcript
             (Differential.Transcript.Get_Outcome (Base));
      begin
         Differential.Transcript.Append
           (B, (State => Adacraft.Protocol.State.Handshake,
                Dir => Differential.Transcript.Serverbound,
                Packet_Id => 0));
         Differential.Transcript.Append
           (B, (State => Adacraft.Protocol.State.Status,
                Dir => Differential.Transcript.Clientbound,
                Packet_Id => 1));
         Assert ("tuple-equal",
           Differential.Compare.Compare (Base, B),
           Differential.Compare.Match);
      end;
      if Passed = Total then
         Put_Line ("selftest: passed 7/7");
         return 0;
      else
         Put_Line (Standard_Error, "selftest: FAILED");
         return 1;
      end if;
   end Check;

end Differential.Selftest;
