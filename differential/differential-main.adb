--  Minimal Differential.Main stub; argument dispatch lands here later.
with Ada.Command_Line;
with Ada.Text_IO;
with Differential;

procedure Differential.Main is
begin
   Ada.Text_IO.Put_Line
     (File => Ada.Text_IO.Standard_Error,
      Item => "usage: differential-main --oracle HOST:PORT --candidate HOST:PORT | --selftest");
   if Ada.Command_Line.Argument_Count = 0 then
      null;
   end if;
end Differential.Main;
