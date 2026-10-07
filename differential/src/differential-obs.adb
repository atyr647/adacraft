package body Differential.Obs is

   function Is_Compared_Field (Name : String) return Boolean is
     (Name = F_Status_Version_Name
      or else Name = F_Status_Version_Protocol
      or else Name = F_Status_Players_Max
      or else Name = F_Status_Players_Online
      or else Name = F_Status_Description
      or else Name = F_Login_Outcome
      or else Name = F_Login_Reason);

   function Image (O : Outcome) return String is
     (case O is
         when Ok           => "ok",
         when Disconnected => "disconnected",
         when Rejected     => "rejected",
         when Malformed    => "malformed",
         when Timeout      => "timeout",
         when Terminal     => "terminal");

   procedure Set_Field
     (Step  : in out Step_Observation;
      Name  : String;
      Value : String;
      Added : out Boolean) is
   begin
      Added := Is_Compared_Field (Name);
      if Added then
         Step.Fields.Include (Name, Value);
      end if;
   end Set_Field;

   procedure Add_Unlisted
     (Step    : in out Step_Observation;
      Path    : String;
      Summary : String) is
   begin
      Step.Unlisted.Include (Path, Summary);
   end Add_Unlisted;

end Differential.Obs;
