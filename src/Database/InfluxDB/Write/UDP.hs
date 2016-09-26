{-# LANGUAGE DataKinds #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE NamedFieldPuns #-}
{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE TemplateHaskell #-}
module Database.InfluxDB.Write.UDP
  ( -- * Writers
    write
  , writeBatch
  , writeByteString

  -- * Writer parameters
  , WriteParams
  , writeParams
  , socket
  , sockAddr
  , Types.precision
  ) where

import Control.Lens
import Network.Socket (SockAddr, Socket)
import Network.Socket.ByteString (sendManyTo)
import qualified Data.ByteString.Lazy as BL

import Database.InfluxDB.Line
import Database.InfluxDB.Types as Types

-- | The full set of parameters for the UDP writer.
data WriteParams = WriteParams
  { _socket :: !Socket
  -- ^ Open UDP socket
  , _sockAddr :: !SockAddr
  -- ^ UDP endopoint of the database
  , _precision :: !(Precision 'WriteRequest)
  -- ^ Timestamp precision.
  --
  -- In the UDP API, all timestamps are sent in nanosecond but you can specify
  -- lower precision. The writer just rounds timestamps.
  }

-- | Smart constructor for 'WriteParams'
--
-- Default parameters:
--
--   ['L.precision'] 'Nanosecond'
writeParams :: Socket -> SockAddr -> WriteParams
writeParams _socket _sockAddr = WriteParams
  { _precision = Nanosecond
  , ..
  }

-- | Write a 'Line'
write
  :: Timestamp time
  => WriteParams
  -> Line time
  -> IO ()
write p@WriteParams {_precision} =
  writeByteString p . encodeLine (roundTo _precision)

-- | Write 'Line's in a batch
--
-- This is more efficient than 'write'.
writeBatch
  :: (Timestamp time, Traversable f)
  => WriteParams
  -> f (Line time)
  -> IO ()
writeBatch p@WriteParams {_precision} =
  writeByteString p . encodeLines (roundTo _precision)

-- | Write a raw 'L.ByteString'
writeByteString :: WriteParams -> BL.ByteString -> IO ()
writeByteString WriteParams {..} payload =
  sendManyTo _socket (BL.toChunks payload) _sockAddr

makeLenses ''WriteParams

instance HasPrecision 'WriteRequest WriteParams where
  precision = Database.InfluxDB.Write.UDP.precision