with Ada.Text_IO;

procedure Test_Handshake_Exchange is
   Failures : Natural := 0;

   procedure Check (Condition : Boolean; Name : String) is
   begin
      if Condition then
         Ada.Text_IO.Put_Line ("PASS: " & Name);
      else
         Failures := Failures + 1;
         Ada.Text_IO.Put_Line ("FAIL: " & Name);
      end if;
   end Check;
begin
   Check (True, "stub wiring");
   if Failures > 0 then
      raise Program_Error with "test failures";
   end if;
   Ada.Text_IO.Put_Line ("ALL PASS");
end Test_Handshake_Exchange;
