with Ada.Calendar;
with Ada.Streams;
with Interfaces;
with Adacraft.Protocol;
with Adacraft.Protocol.Buffer;
with Adacraft.Protocol.Frame;
with Adacraft.Protocol.Status_Info;

package Adacraft.Ingress is
   --  Per-connection framing wiring: one frame decoder per connection.
   --  Phase 2: read-frame/dispatch/handle/write-or-Close_No_Bytes loop
   --  with injected clock and 30 s idle timeout, plus LOGIN stub.

   subtype Byte is Ada.Streams.Stream_Element;
   subtype Byte_Array is Protocol.Frame.Byte_Array;

   --  Idle timeout: 30 seconds, reset after each successfully completed
   --  inbound packet while in HANDSHAKE/STATUS (and the LOGIN stub).
   Default_Idle_Timeout : constant Duration := 30.0;

   --  Injected clock. Defaults to the real clock; tests inject a fake.
   --  Returns the current time; compared with Difference against
   --  Session.Last_Activity.
   type Clock_Access is access function return Ada.Calendar.Time;

   function Real_Clock return Ada.Calendar.Time;

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

   --  Read-only status snapshot shared by all connections.
   function Default_Status return Protocol.Status_Info.Status_Info;

   type Session is record
      State         : Protocol.Protocol_State := Protocol.Handshake;
      Version       : Interfaces.Unsigned_32 := 0;
      --  Connection-local handshake storage (handover for #122).
      Has_Handshake : Boolean := False;
      Hs_Version    : Interfaces.Unsigned_32 := 0;
      Hs_Addr_Len   : Natural := 0;
      Hs_Address    : String (1 .. 255) := (others => ' ');
      Hs_Port       : Interfaces.Unsigned_16 := 0;
      Hs_Intent     : Interfaces.Unsigned_32 := 0;
      --  Idle activity stamp; reset on each completed packet.
      Last_Activity : Ada.Calendar.Time := Ada.Calendar.Clock;
   end record;

   function Is_Idle_Expired
     (S       : Session;
      Now     : Ada.Calendar.Time;
      Timeout : Duration := Default_Idle_Timeout) return Boolean;
   --  True when Now - Last_Activity > Timeout. Timeout closure sends
   --  no bytes (Close_No_Bytes).

   procedure Mark_Activity
     (S   : in out Session;
      Now : Ada.Calendar.Time);
   --  Reset the idle timer after a successfully completed packet.

   procedure Close_No_Bytes
     (Outgoing  : in out Protocol.Buffer.Writer;
      Close_Now : out Boolean);
   --  Violation path: discard any buffered output, send nothing,
   --  signal close. Identical input => identical outcome.

   procedure Handle_Login_Stub
     (S         : in out Session;
      Outgoing  : in out Protocol.Buffer.Writer;
      Close_Now : out Boolean);
   --  LOGIN stub (IF-2 seam for #122): any inbound packet in LOGIN
   --  closes with no bytes. Replaced by real LOGIN handling in #122.

   procedure Ingest
     (S         : in out Session;
      Incoming  : Protocol.Octets;
      From      : Positive;
      Consumed  : out Natural;
      Outgoing  : in out Protocol.Buffer.Writer;
      Close_Now : out Boolean);

   procedure Ingest_With_Clock
     (S         : in out Session;
      Incoming  : Protocol.Octets;
      From      : Positive;
      Consumed  : out Natural;
      Outgoing  : in out Protocol.Buffer.Writer;
      Close_Now : out Boolean;
      Now       : Ada.Calendar.Time;
      Info      : Protocol.Status_Info.Status_Info);
   --  Same as Ingest but stamps Last_Activity with the injected Now
   --  after each completed packet and uses Info for status responses.
   --  Handlers receive only (Session, Status_Info): no kernel access.

private

   type Connection_Type is limited record
      Decoder  : Protocol.Frame.Decoder_Type;
      On_Body  : Body_Consumer := null;
      On_Close : Close_Action := null;
      Closed   : Boolean := True;
   end record;

end Adacraft.Ingress;
