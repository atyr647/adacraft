with Ada.Containers.Indefinite_Ordered_Maps;
with Ada.Containers.Vectors;
with Ada.Strings.Unbounded;
with Adacraft.Protocol.State;

--  Observation model: per step, (state after step, semantic field map,
--  outcome). Steps are tagged so later phases can extend them with
--  gameplay fields without changing this schema.
package Differential.Obs is

   type Outcome is (Ok, Disconnected, Rejected, Malformed, Timeout, Terminal);

   --  Phase-1 compared field names (the comparison schema, A8).
   F_Status_Version_Name     : constant String := "status.version.name";
   F_Status_Version_Protocol : constant String := "status.version.protocol";
   F_Status_Players_Max      : constant String := "status.players.max";
   F_Status_Players_Online   : constant String := "status.players.online";
   F_Status_Description      : constant String := "status.description";
   F_Login_Outcome           : constant String := "login.outcome";
   F_Login_Reason            : constant String := "login.reason";

   function Is_Compared_Field (Name : String) return Boolean;

   function Image (O : Outcome) return String;

   --  Values are canonical text (JSON text for structured values).
   package Field_Maps is new Ada.Containers.Indefinite_Ordered_Maps
     (Key_Type => String, Element_Type => String);

   type Step_Observation is tagged record
      State    : Adacraft.Protocol.State.Connection_State :=
        Adacraft.Protocol.State.Handshake;
      Result   : Outcome := Ok;
      Fields   : Field_Maps.Map;  --  compared semantic fields only
      Unlisted : Field_Maps.Map;  --  path -> stable summary; never compared
   end record;

   --  Records a compared field; False (and nothing stored) if Name is not
   --  in the comparison schema.
   procedure Set_Field
     (Step  : in out Step_Observation;
      Name  : String;
      Value : String;
      Added : out Boolean);

   --  Records a field outside the schema in the unlisted inventory.
   procedure Add_Unlisted
     (Step    : in out Step_Observation;
      Path    : String;
      Summary : String);

   package Step_Vectors is new Ada.Containers.Vectors
     (Positive, Step_Observation);

   type Observation is record
      Scenario_Id : Ada.Strings.Unbounded.Unbounded_String;
      Steps       : Step_Vectors.Vector;
   end record;

end Differential.Obs;
