with Ada.Text_IO;
with Ada.Strings.Unbounded;
with Adacraft.Protocol.State;
with Differential.Compare;
with Differential.Report;
with Differential.Transcript;

package body Differential.Selftest is
   use type Differential.Compare.Difference_Kind;
   use type Differential.Transcript.Direction_T;
   use type Differential.Transcript.Terminal_Outcome;
   use type Adacraft.Protocol.State.Connection_State;
   use type Adacraft.Protocol.State.Packet_Id;

   subtype Transcript is Differential.Transcript.Transcript;

   function Make_Base return Transcript is
      Result : Transcript;
   begin
      Result.Entries.Append
        ((State     => Adacraft.Protocol.State.Handshake,
          Direction => Differential.Transcript.Serverbound,
          Packet_Id => 0));
      Result.Entries.Append
        ((State     => Adacraft.Protocol.State.Status,
          Direction => Differential.Transcript.Clientbound,
          Packet_Id => 1));
      return Result;
   end Make_Base;

   function With_Entry
     (Base  : Transcript;
      Index : Positive;
      Item  : Differential.Transcript.Transcript_Entry) return Transcript
   is
      Result : Transcript := Base;
   begin
      Result.Entries.Replace_Element (Index, Item);
      return Result;
   end With_Entry;

   function Has_Difference
     (Left, Right : Transcript;
      Expected    : Differential.Compare.Difference_Kind) return Boolean
   is
   begin
      return Differential.Compare.Compare (Left, Right).Difference = Expected;
   end Has_Difference;

   function Base_Result return Boolean is
      Base : constant Transcript := Make_Base;
      Changed : Transcript;
      Verdict : Differential.Compare.Verdict;
      First_Report, Second_Report : String (1 .. 1_000);
      First_Length, Second_Length : Natural := 0;
   begin
      if not Differential.Compare.Compare (Base, Base).Is_Match then
         return False;
      end if;

      Changed := With_Entry
        (Base, 1,
         (State     => Adacraft.Protocol.State.Handshake,
          Direction => Differential.Transcript.Serverbound,
          Packet_Id => 7));
      if not Has_Difference
        (Base, Changed, Differential.Compare.Packet_Id_Difference)
      then
         return False;
      end if;

      Changed := With_Entry
        (Base, 1,
         (State     => Adacraft.Protocol.State.Status,
          Direction => Differential.Transcript.Serverbound,
          Packet_Id => 0));
      if not Has_Difference
        (Base, Changed, Differential.Compare.State_Difference)
      then
         return False;
      end if;

      Changed := With_Entry
        (Base, 1,
         (State     => Adacraft.Protocol.State.Handshake,
          Direction => Differential.Transcript.Clientbound,
          Packet_Id => 0));
      if not Has_Difference
        (Base, Changed, Differential.Compare.Direction_Difference)
      then
         return False;
      end if;

      Changed := Base;
      Changed.Outcome := Differential.Transcript.Closed_By_Peer;
      if not Has_Difference
        (Base, Changed, Differential.Compare.Outcome_Difference)
      then
         return False;
      end if;

      Changed := Base;
      Changed.Entries.Delete_Last;
      if not Has_Difference
        (Base, Changed, Differential.Compare.Length_Difference)
      then
         return False;
      end if;

      declare
         use Ada.Strings.Unbounded;
         Results : Differential.Report.Scenario_Result_Vectors.Vector;
         Name : constant Unbounded_String := To_Unbounded_String ("selftest");
      begin
         Verdict := Differential.Compare.Compare (Base, Base);
         Results.Append ((Name => Name, Verdict => Verdict));
         declare
            Text : constant String := Differential.Report.Format (Results);
         begin
            First_Length := Text'Length;
            First_Report (1 .. First_Length) := Text;
         end;
         declare
            Text : constant String := Differential.Report.Format (Results);
         begin
            Second_Length := Text'Length;
            Second_Report (1 .. Second_Length) := Text;
         end;
      end;

      return First_Length = Second_Length
        and then First_Report (1 .. First_Length) =
          Second_Report (1 .. Second_Length);
   end Base_Result;

   procedure Check is
   begin
      if Base_Result then
         Ada.Text_IO.Put_Line ("Differential selftest: PASS");
      else
         Ada.Text_IO.Put_Line ("Differential selftest: FAIL");
      end if;
   end Check;
end Differential.Selftest;
