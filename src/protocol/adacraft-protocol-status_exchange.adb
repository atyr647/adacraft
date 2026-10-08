with Interfaces;
with Adacraft.Protocol.Ids;
with Adacraft.Protocol.Packets;

package body Adacraft.Protocol.Status_Exchange is
   use type Adacraft.Protocol.State.Connection_State;
   use type Adacraft.Protocol.Status_Kind;

   Status_JSON : constant String :=
     "{""version"":{""name"":""26.3"",""protocol"":777},"
     & """players"":{""max"":20,""online"":0},"
     & """description"":{""text"":""An AdaCraft Server""}}";

   procedure Handle
     (Input         : Adacraft.Protocol.Octets;
      Current_State : Adacraft.Protocol.State.Connection_State;
      Status_Sent   : in out Boolean;
      Disposition   : out Disposition_Kind;
      Output        : in out Buffer.Writer)
   is
      Request_Id : constant Natural :=
        Adacraft.Protocol.Ids.Protocol_Id
          (Adacraft.Protocol.Ids.Sb_Status_Status_Request);
      Ping_Id : constant Natural :=
        Adacraft.Protocol.Ids.Protocol_Id
          (Adacraft.Protocol.Ids.Sb_Status_Ping_Request);
   begin
      Buffer.Reset (Output);
      Disposition := Silent_Close;

      if Current_State /= Adacraft.Protocol.State.Status
        or else Input'Length = 0
      then
         return;
      end if;

      if Natural (Input (Input'First)) = Request_Id then
         if Status_Sent or else Input'Length /= 1 then
            return;
         end if;

         declare
            Body_Writer : Buffer.Writer (512);
         begin
            Buffer.Put_Varint
              (Body_Writer,
               Interfaces.Unsigned_32
                 (Adacraft.Protocol.Ids.Protocol_Id
                    (Adacraft.Protocol.Ids.Cb_Status_Status_Response)));
            Buffer.Put_String (Body_Writer, Status_JSON);

            if Body_Writer.Failed
              or else not Adacraft.Protocol.Packets.Frame (Output, Body_Writer)
            then
               Buffer.Reset (Output);
               return;
            end if;
         end;

         Status_Sent := True;
         Disposition := Progress;
      elsif Natural (Input (Input'First)) = Ping_Id then
         if Input'Length /= 9 then
            return;
         end if;

         declare
            Body_Writer : Buffer.Writer (16);
            Echo : Adacraft.Protocol.Octets (1 .. 8);
         begin
            for I in Echo'Range loop
               Echo (I) := Input (Input'First + I);
            end loop;

            Buffer.Put_Varint
              (Body_Writer,
               Interfaces.Unsigned_32
                 (Adacraft.Protocol.Ids.Protocol_Id
                    (Adacraft.Protocol.Ids.Cb_Status_Pong_Response)));
            Buffer.Put_Bytes (Body_Writer, Echo);

            if Body_Writer.Failed
              or else not Adacraft.Protocol.Packets.Frame (Output, Body_Writer)
            then
               Buffer.Reset (Output);
               return;
            end if;
         end;

         Disposition := Close_After_Send;
      end if;
   end Handle;
end Adacraft.Protocol.Status_Exchange;
