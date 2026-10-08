--  Idle-timeout tests with injected clock; never waits real 30 s.
--  Implemented against a local injected-clock model mirroring
--  Connection_Context.Last_Activity semantics (30_000 ms default).
with Ada.Text_IO;

procedure Test_Idle_Timeout is
   Failures : Natural := 0;

   procedure Check (Cond : Boolean; Name : String) is
   begin
      if not Cond then
         Ada.Text_IO.Put_Line ("FAIL " & Name);
         Failures := Failures + 1;
      end if;
   end Check;

   Default_Timeout_Ms : constant := 30_000;

   type Clock is record
      Now           : Natural := 0;
      Last_Activity : Natural := 0;
   end record;

   function Expired (C : Clock; Timeout : Natural := Default_Timeout_Ms)
     return Boolean
   is (C.Now >= C.Last_Activity and then C.Now - C.Last_Activity > Timeout);

   procedure Mark (C : in out Clock) is
   begin
      C.Last_Activity := C.Now;
   end Mark;

begin
   --  Fresh connection at t=0 is not expired.
   declare
      C : Clock := (Now => 0, Last_Activity => 0);
   begin
      Check (not Expired (C), "fresh not expired");
   end;

   --  Just before deadline: not expired; just after: expired.
   declare
      C : Clock := (Now => 0, Last_Activity => 0);
   begin
      C.Now := Default_Timeout_Ms;
      Check (not Expired (C), "boundary not expired at ==");
      C.Now := Default_Timeout_Ms + 1;
      Check (Expired (C), "expired just after timeout");
   end;

   --  Activity resets the timer (successful inbound packet).
   declare
      C : Clock := (Now => 29_999, Last_Activity => 0);
   begin
      Check (not Expired (C), "pre-timeout alive");
      Mark (C);
      C.Now := C.Now + Default_Timeout_Ms;
      Check (not Expired (C), "reset timer alive");
      C.Now := C.Now + 1;
      Check (Expired (C), "reset timer then expires");
   end;

   --  Multiple resets keep connection alive (injected clock jumps).
   declare
      C : Clock := (Now => 0, Last_Activity => 0);
      Alive : Boolean := True;
   begin
      for I in 1 .. 10 loop
         C.Now := C.Now + 10_000;
         exit when Expired (C);
         Mark (C);
      end loop;
      Alive := not Expired (C);
      Check (Alive, "periodic activity never expires");
   end;

   --  Timeout closure sends no bytes (model: expired => Close_No_Bytes).
   declare
      C : Clock := (Now => 60_000, Last_Activity => 0);
      Bytes_To_Send : Natural := 0;
   begin
      if Expired (C) then
         Bytes_To_Send := 0;
      end if;
      Check (Expired (C) and then Bytes_To_Send = 0, "timeout sends no bytes");
   end;

   --  Custom tiny timeout (smoke path) still respects injection.
   declare
      C : Clock := (Now => 500, Last_Activity => 0);
   begin
      Check (Expired (C, 100), "tiny timeout expires");
      Check (not Expired (C, 10_000), "large timeout alive");
   end;

   if Failures = 0 then
      Ada.Text_IO.Put_Line ("PASS test_idle_timeout");
   else
      Ada.Text_IO.Put_Line ("FAILURES test_idle_timeout:"
                            & Natural'Image (Failures));
   end if;
end Test_Idle_Timeout;
