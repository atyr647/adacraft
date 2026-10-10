with Ada.Streams;
with Interfaces;
with Adacraft.Protocol.Buffer;
with Adacraft.Protocol.Frame;
with Adacraft.Protocol.Login;
with Adacraft.Protocol.Login;

package Adacraft.Ingress is
   --  Per-connection framing wiring: one frame decoder per connection.

   subtype Byte is Ada.Streams.Stream_Element;
   subtype Byte_Array is Protocol.Frame.Byte_Array;

   type Body_Consumer is access procedure (Data : Byte_Array);
   type Close_Action is access procedure;

   type Connection_Type is limited private;

   procedure Initialize
     (Connection : out Connection_Type;
      On_Body    : Body_Consumer;
      On_Close   : Close_Action);
   --  Opens the connection. Raises Program_Error on a null callback.
   --  Call once on a freshly declared connection.

   procedure Receive
     (Connection : in out Connection_Type;
      Bytes      : Byte_Array);
   --  Feeds any chunk (including empty) through the connection's decoder.
   --  On a framing error the connection closes and On_Close runs once;
   --  bytes received after closing are discarded.

   function Is_Closed (Connection : Connection_Type) return Boolean;

   type Session is record
      State       : Protocol.State.Connection_State := Protocol.State.Handshake;
      Version     : Interfaces.Unsigned_32 := 0;
      Login_State : Protocol.Login.Login_Session;
   end record;

   procedure Ingest
     (S         : in out Session;
      Incoming  : Protocol.Octets;
      From      : Positive;
      Consumed  : out Natural;
      Outgoing  : in out Protocol.Buffer.Writer;
      Close_Now : out Boolean);

private

   type Connection_Type is limited record
      Decoder  : Protocol.Frame.Decoder_Type;
      On_Body  : Body_Consumer := null;
      On_Close : Close_Action := null;
      Closed   : Boolean := True;
   end record;

end Adacraft.Ingress;
