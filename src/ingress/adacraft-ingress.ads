with Interfaces;
with Adacraft.Protocol.Buffer;

package Adacraft.Ingress is
   type Session is record
      State    : Protocol.Protocol_State := Protocol.Handshake;
      Version  : Interfaces.Unsigned_32 := 0;
   end record;

   procedure Ingest
     (S         : in out Session;
      Incoming  : Protocol.Octets;
      From      : Positive;
      Consumed  : out Natural;
      Outgoing  : in out Protocol.Buffer.Writer;
      Close_Now : out Boolean);
end Adacraft.Ingress;
