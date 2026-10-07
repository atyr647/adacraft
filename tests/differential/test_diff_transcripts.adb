with Ada.Command_Line;
with Ada.Strings.Unbounded;
with Ada.Text_IO;
with Adacraft.Protocol;
with Differential.Client;
with Differential.Scenario;

--  DR-3: two runs of one scenario against different stub targets produce
--  byte-identical action transcripts.
procedure Test_Diff_Transcripts is
   package C renames Differential.Client;
   package D renames Differential.Scenario;
   package P renames Adacraft.Protocol;
   package SU renames Ada.Strings.Unbounded;
   use type SU.Unbounded_String;
   use type Ada.Containers.Count_Type;

   Failures : Natural := 0;

   procedure Check (Cond : Boolean; Name : String) is
   begin
      if not Cond then
         Ada.Text_IO.Put_Line ("FAIL " & Name);
         Failures := Failures + 1;
      end if;
   end Check;

   type Stub is limited new C.Transport with record
      Reply   : SU.Unbounded_String;
      Pending : Boolean := False;
      Sent    : SU.Unbounded_String;
   end record;

   overriding procedure Send
     (T : in out Stub; Data : P.Octets; Ok : out Boolean) is
   begin
      SU.Append (T.Sent, C.Hex (Data));
      T.Pending := True;
      Ok := True;
   end Send;

   overriding procedure Receive
     (T      : in out Stub;
      Wait   : Duration;
      Buffer : out P.Octets;
      Last   : out Natural;
      Status : out C.Recv_Status)
   is
      pragma Unreferenced (Wait);
      S : constant String := SU.To_String (T.Reply);
   begin
      if T.Pending and then S'Length > 0 then
         T.Pending := False;
         for I in S'Range loop
            Buffer (I - S'First + 1) := P.Octet (Character'Pos (S (I)));
         end loop;
         Last := S'Length;
         Status := C.Data;
      else
         Last := 0;
         Status := C.Quiet;
      end if;
   end Receive;

   procedure Add (A : in out D.Action; B : P.Octets) is
   begin
      for X of B loop
         A.Frame.Append (X);
      end loop;
   end Add;

   Proj : D.Projection;
   A1, A2 : D.Action;
   O1, O2, O3 : C.Run_Output;
   T1, T2 : Stub;
begin
   Proj.Id := SU.To_Unbounded_String ("stub-status");
   A1.Index := 1;
   A1.Timeout := 0.05;
   Add (A1, (16#10#, 16#00#, 16#89#, 16#06#, 16#09#,
             Character'Pos ('l'), Character'Pos ('o'), Character'Pos ('c'),
             Character'Pos ('a'), Character'Pos ('l'), Character'Pos ('h'),
             Character'Pos ('o'), Character'Pos ('s'), Character'Pos ('t'),
             16#63#, 16#DD#, 16#01#));
   A2.Index := 2;
   A2.Timeout := 0.05;
   Add (A2, (16#01#, 16#00#));
   Proj.Actions.Append (A1);
   Proj.Actions.Append (A2);

   --  Different canned replies; the transcript must not depend on them.
   T1.Reply := SU.To_Unbounded_String
     (Character'Val (2) & Character'Val (0) & 'A');
   T2.Reply := SU.Null_Unbounded_String;

   C.Execute (T1, Proj, O1);
   C.Execute (T2, Proj, O2);

   Check (not O1.Failed and then not O2.Failed, "runs succeed");
   Check (O1.Transcript = O2.Transcript, "transcripts byte-identical");
   Check (SU.Length (O1.Transcript) > 0, "transcript not empty");
   Check (T1.Sent = T2.Sent, "same bytes sent");
   Check (O1.Steps.Length = 2, "two step logs");

   if O1.Steps.Length = 2 then
      Check (O1.Steps (1).Packets.Length = 1, "packet extracted");
      if O1.Steps (1).Packets.Length = 1 then
         Check (O1.Steps (1).Packets (1).Id = 0
                and then SU.To_String (O1.Steps (1).Packets (1).Payload)
                         = "A", "packet id and payload");
      end if;
      Check (O1.Steps (1).State_After = C.PS.Status, "state after handshake");
      Check (O2.Steps (1).No_Data, "silent target logged as no data");
   end if;

   --  A different action list must change the transcript.
   declare
      Other : D.Projection := Proj;
      Stub3 : Stub;
   begin
      Other.Actions.Delete_Last;
      C.Execute (Stub3, Other, O3);
      Check (O3.Transcript /= O1.Transcript, "different actions differ");
   end;

   if Failures > 0 then
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
   end if;
end Test_Diff_Transcripts;
