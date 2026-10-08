with Adacraft.Protocol.Buffer;
with Adacraft.Protocol.State;

package Adacraft.Protocol.Handshake_Exchange is
   type Disposition_Kind is (Progress, Silent_Close);

   procedure Handle
     (Input          : Adacraft.Protocol.Octets;
      Current_State  : in out State.Connection_State;
      Client_Version : out Natural;
      Disposition    : out Disposition_Kind;
      Output         : in out Buffer.Writer);
end Adacraft.Protocol.Handshake_Exchange;
