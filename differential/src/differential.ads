package Differential is
   type Exit_Code is (Success, Divergence, Environment_Error);

   type Outcome is
     (Completed,
      Peer_Closed,
      Read_Timeout,
      Malformed_Frame,
      Invalid_State_Or_Direction);
end Differential;
