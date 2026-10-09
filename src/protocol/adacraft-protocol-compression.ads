package Adacraft.Protocol.Compression is

   Max_Decompressed_Size : constant := 8_388_608;

   subtype Threshold_Type is Natural;

   type Reject_Reason is
     (None,
      Oversize,
      Below_Threshold,
      Empty_Body,
      Bad_Data_Length,
      Truncated,
      Size_Mismatch,
      Corrupt_Data,
      Trailing_Bytes);

   type Byte_Array_Access is access Octets;

   type Encode_Result (Ok : Boolean := False) is record
      case Ok is
         when True =>
            Data : Byte_Array_Access;
         when False =>
            Reason : Reject_Reason;
      end case;
   end record;

   type Decode_Result (Ok : Boolean := False) is record
      case Ok is
         when True =>
            Data : Byte_Array_Access;
         when False =>
            Reason : Reject_Reason;
      end case;
   end record;

   procedure Free (X : in out Byte_Array_Access);
   procedure Free (R : in out Encode_Result);
   procedure Free (R : in out Decode_Result);

   procedure Encode
     (Threshold    : Threshold_Type;
      Uncompressed : Octets;
      R            : out Encode_Result);

   procedure Decode
     (Threshold : Threshold_Type;
      Input     : Octets;
      R         : out Decode_Result);

end Adacraft.Protocol.Compression;
