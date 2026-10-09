with Ada.Command_Line;
with Ada.Text_IO;
with Interfaces.C;
with Interfaces.C.Strings;
with System;
with Adacraft.Protocol.Zlib;

procedure Test_Protocol_Compression is
   package Z renames Adacraft.Protocol.Zlib;
   use type Interfaces.C.int;
   use type Interfaces.C.unsigned_long;
   use type Interfaces.C.unsigned;

   Failures : Natural := 0;

   procedure Check (Condition : Boolean; Name : String) is
   begin
      if not Condition then
         Failures := Failures + 1;
         Ada.Text_IO.Put_Line ("FAIL: " & Name);
      end if;
   end Check;

   subtype Stream_Box is Z.Z_Stream_Access;

   procedure Round_Trip (Name : String; Input : String) is
      use Interfaces.C.Strings;
      In_Buf  : aliased Interfaces.C.char_array (0 .. 511) :=
        (others => Interfaces.C.nul);
      Out_Buf : aliased Interfaces.C.char_array (0 .. 511) :=
        (others => Interfaces.C.nul);
      Back    : aliased Interfaces.C.char_array (0 .. 511) :=
        (others => Interfaces.C.nul);
      S       : Stream_Box := new Z.Z_Stream;
      Ver     : chars_ptr := New_String (Z.Zlib_Version);
      Rc      : Interfaces.C.int;
   begin
      for I in Input'Range loop
         In_Buf (Interfaces.C.size_t (I - Input'First)) :=
           Interfaces.C.char'Val (Character'Pos (Input (I)));
      end loop;
      Z.Init_Stream (S.all);
      Z.Set_Input (S.all, In_Buf'Address,
                   Interfaces.C.unsigned (Input'Length));
      Z.Set_Output (S.all, Out_Buf'Address, 512);
      Rc := Z.Deflate_Init (S, Z.Z_Default_Compression, Ver,
                            Z.Stream_Size);
      Check (Rc = Z.Z_Ok, Name & " deflate init");
      if Rc /= Z.Z_Ok then
         Free (Ver);
         return;
      end if;
      Rc := Z.Deflate (S, Z.Z_Finish);
      Check (Rc = Z.Z_Stream_End, Name & " deflate finish");
      declare
         Produced : constant Interfaces.C.unsigned_long := Z.Total_Out (S.all);
         Rc_End   : constant Interfaces.C.int := Z.Deflate_End (S);
      begin
         Check (Rc_End = Z.Z_Ok, Name & " deflate end");
         Check ((Produced > 0) = (Input'Length > 0),
                Name & " produced bytes");
         Z.Init_Stream (S.all);
         Z.Set_Input (S.all, Out_Buf'Address,
                      Interfaces.C.unsigned (Produced));
         Z.Set_Output (S.all, Back'Address, 512);
         Rc := Z.Inflate_Init (S, Ver, Z.Stream_Size);
         Check (Rc = Z.Z_Ok, Name & " inflate init");
         if Rc = Z.Z_Ok then
            Rc := Z.Inflate (S, Z.Z_Finish);
            Check (Rc = Z.Z_Stream_End, Name & " inflate finish");
            Check (Z.Total_Out (S.all) =
                     Interfaces.C.unsigned_long (Input'Length),
                   Name & " inflate size");
            Check (Z.Avail_In (S.all) = 0, Name & " no trailing bytes");
            Rc := Z.Inflate_End (S);
            Check (Rc = Z.Z_Ok, Name & " inflate end");
         end if;
      end;
      Free (Ver);
   end Round_Trip;

begin
   Check (Z.Stream_Size > 0, "stream size positive");
   Check (Z.Compress_Bound (0) > 0, "compress bound zero");
   Check (Z.Compress_Bound (100) >= 100, "compress bound grows");
   Round_Trip ("hello", "hello world");
   Round_Trip ("empty", "");

   if Failures = 0 then
      Ada.Text_IO.Put_Line ("compression tests passed");
   else
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
   end if;
end Test_Protocol_Compression;
