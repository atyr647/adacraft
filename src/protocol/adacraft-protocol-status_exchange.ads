with Adacraft.Protocol.Buffer;
with Adacraft.Protocol.State;

package Adacraft.Protocol.Status_Exchange is
   type Disposition_Kind is (Progress, Close_After_Send, Silent_Close);

   procedure Handle
     (Input         : Adacraft.Protocol.Octets;
      Current_State : Adacraft.Protocol.State.Connection_State;
      Status_Sent   : in out Boolean;
      Disposition   : out Disposition_Kind;
      Output        : in out Buffer.Writer);
end Adacraft.Protocol.Status_Exchange;
