with Ada.Command_Line;
with Ada.Containers;
with Ada.Directories;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;
with Ada.Text_IO;
with Adacraft.Corpus;
with Adacraft.Corpus.Loader;

procedure Test_Corpus_Loader is
   package C renames Adacraft.Corpus;
   package L renames Adacraft.Corpus.Loader;
   use Ada.Strings.Unbounded;
   use type Ada.Containers.Count_Type;

   LF : constant Character := ASCII.LF;
   Failures : Natural := 0;

   procedure Check (Cond : Boolean; Name : String) is
   begin
      if not Cond then
         Ada.Text_IO.Put_Line ("FAIL " & Name);
         Failures := Failures + 1;
      end if;
   end Check;

   Hdr : constant String := "corpus_format: 1" & LF;

   function Req
     (Id    : String := "a";
      Cat   : String := "handshake";
      Proto : String := "777";
      Prov  : String := "hand-authored";
      Init  : String := "HANDSHAKE";
      Extra : String := "") return String is
     ("id: " & Id & LF & "title: t" & LF & "description: d" & LF
      & "category: " & Cat & LF & "protocol: " & Proto & LF
      & "provenance: " & Prov & LF & "initial_state: " & Init & LF & Extra);

   function Stp
     (Dir : String := "serverbound";
      Inp : String := "01 00";
      Out_C : String := "rejected";
      Extra : String := "") return String is
     ("step:" & LF & "  direction: " & Dir & LF & "  input: " & Inp & LF
      & "  outcome: " & Out_C & LF & Extra);

   function Run (Text : String; Errs : out C.Error_Vectors.Vector)
     return Boolean
   is
      S : C.Scenario;
   begin
      Errs.Clear;
      return L.Parse (Text, "t.scenario", S, Errs);
   end Run;

   procedure Rejects (Text, Frag, Name : String) is
      Errs : C.Error_Vectors.Vector;
      Ok   : constant Boolean := Run (Text, Errs);
      Hit  : Boolean := False;
   begin
      for E of Errs loop
         if Ada.Strings.Fixed.Index (L.Format_Error (E), Frag) > 0
           and then Ada.Strings.Fixed.Index (L.Format_Error (E), "t.scenario:") = 1
         then
            Hit := True;
         end if;
      end loop;
      Check (not Ok and then Hit, Name);
   end Rejects;

   procedure Put_File (Path, Text : String) is
      F : Ada.Text_IO.File_Type;
   begin
      Ada.Text_IO.Create (F, Ada.Text_IO.Out_File, Path);
      Ada.Text_IO.Put (F, Text);
      Ada.Text_IO.Close (F);
   end Put_File;

   Good : constant String := Hdr & Req (Extra => "final_state: HANDSHAKE" & LF) & Stp;
   Dir  : constant String := "obj/corpus_scratch";
begin
   declare
      Errs : C.Error_Vectors.Vector;
   begin
      Check (Run (Good, Errs) and then Errs.Length = 0, "happy path");
      Check (Run (Hdr & "# c" & LF & Req (Extra => "future: x" & LF)
                  & Stp (Out_C => "accepted",
                         Extra => "  packet_id: 0x00" & LF
                                  & "  state_after: STATUS" & LF
                                  & "  canonical: true" & LF),
                  Errs), "accepted + unknown key");
   end;

   Rejects ("corpus_format: 2" & LF & Req & Stp, "corpus_format", "bad format");
   Rejects (Req & Stp, "corpus_format", "format not first");
   Rejects (Hdr & Stp, "missing required field id", "missing id");
   Rejects (Hdr & Req (Id => "a b") & Stp, "invalid id", "bad id");
   Rejects (Hdr & Req (Id => "") & Stp, "invalid id", "empty id");
   Rejects (Hdr & Req (Cat => "walk") & Stp, "invalid category", "bad category");
   Rejects (Hdr & Req (Proto => "778") & Stp, "777", "bad protocol");
   Rejects (Hdr & Req (Prov => "made-up") & Stp, "invalid provenance", "bad prov");
   Rejects (Hdr & Req (Prov => "regression") & Stp, "missing reference",
            "regression without reference");
   Rejects (Hdr & Req (Init => "NOPE") & Stp, "invalid initial_state", "bad init");
   Rejects (Hdr & Req (Extra => "final_state: NOPE" & LF) & Stp,
            "invalid final_state", "bad final");
   Rejects (Hdr & Req & Stp (Dir => "sideways"), "invalid direction", "bad dir");
   Rejects (Hdr & Req & Stp (Out_C => "maybe"), "invalid outcome", "bad outcome");
   Rejects (Hdr & Req & Stp (Extra => "  canonical: yes" & LF),
            "invalid canonical", "bad canonical");
   Rejects (Hdr & Req & Stp (Extra => "  canonical: true" & LF),
            "canonical only valid", "canonical on rejected");
   Rejects (Hdr & Req & Stp (Inp => "0G"), "invalid hex", "bad hex");
   Rejects (Hdr & Req & Stp (Inp => "012"), "odd number", "odd hex");
   Rejects (Hdr & Req & Stp (Inp => ""), "empty input", "empty input");
   Rejects (Hdr & Req, "no steps", "zero steps");
   Rejects (Hdr & Req & Stp & Stp, "terminal step must be last", "terminal not last");
   Rejects (Hdr & Req (Extra => "id: b" & LF) & Stp, "duplicate key", "dup top key");
   Rejects (Hdr & Req (Extra => "zzz: 1" & LF & "zzz: 2" & LF) & Stp,
            "duplicate key", "dup unknown key");
   Rejects (Hdr & Req & Stp (Extra => "  input: 00" & LF),
            "duplicate key", "dup step key");
   Rejects (Hdr & Req & "step:" & LF & "  direction: serverbound" & LF,
            "missing required field input", "missing step field");
   Rejects (Hdr & Req & Stp (Out_C => "accepted"),
            "missing required field packet_id", "accepted missing packet_id");

   declare
      Many : Unbounded_String;
      Errs : C.Error_Vectors.Vector;
   begin
      for I in 1 .. 1025 loop
         Append (Many, Stp (Out_C => "accepted",
                            Extra => "  packet_id: 0" & LF
                                     & "  state_after: STATUS" & LF));
      end loop;
      Check (not Run (Hdr & Req & To_String (Many), Errs), "too many steps");
   end;

   --  Discovery, ordering, ignore rule, size bound, duplicate ids.
   if Ada.Directories.Exists (Dir) then
      Ada.Directories.Delete_Tree (Dir);
   end if;
   Ada.Directories.Create_Path (Dir);
   Put_File (Dir & "/b.scenario", Hdr & Req (Id => "b") & Stp);
   Put_File (Dir & "/a.scenario", Hdr & Req (Id => "a") & Stp);
   Put_File (Dir & "/_c.scenario", Hdr & Req (Id => "c") & Stp);
   Put_File (Dir & "/d.scenario", Hdr & Req (Id => "a") & Stp);
   declare
      F : Ada.Text_IO.File_Type;
   begin
      Ada.Text_IO.Create (F, Ada.Text_IO.Out_File, Dir & "/big.scenario");
      for I in 1 .. 1050 loop
         Ada.Text_IO.Put_Line (F, "# " & (1 .. 1000 => 'x'));
      end loop;
      Ada.Text_IO.Close (F);
   end;
   declare
      Names : constant C.Name_Vectors.Vector := L.Discover (Dir);
      Sc    : C.Scenario_Vectors.Vector;
      Errs  : C.Error_Vectors.Vector;
      Dup, Big : Boolean := False;
   begin
      Check (Names.Length = 4, "discover count (ignores _ prefix)");
      Check (To_String (Names.First_Element) = Dir & "/a.scenario", "sorted first");
      Check (To_String (Names.Last_Element) = Dir & "/d.scenario", "sorted last");
      L.Load (Dir, Sc, Errs);
      Check (Sc.Length = 2, "loaded two scenarios");
      for E of Errs loop
         if Ada.Strings.Fixed.Index (L.Format_Error (E), "duplicate scenario id") > 0 then
            Dup := True;
         elsif Ada.Strings.Fixed.Index (L.Format_Error (E), "too large") > 0 then
            Big := True;
         end if;
      end loop;
      Check (Dup, "duplicate id reported");
      Check (Big, "size bound reported");
      Check (Errs.Length = 2, "all errors accumulated");
   end;
   Ada.Directories.Delete_Tree (Dir);

   if Failures > 0 then
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
   end if;
end Test_Corpus_Loader;
