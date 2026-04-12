{-
 Copyright (C) 2026 Romain Viallard

 This program is free software: you can redistribute it and/or modify
 it under the terms of the GNU Affero General Public License as
 published by the Free Software Foundation, either version 3 of the
 License, or (at your option) any later version.

 This program is distributed in the hope that it will be useful,
 but WITHOUT ANY WARRANTY; without even the implied warranty of
 MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 GNU Affero General Public License for more details.

 You should have received a copy of the GNU Affero General Public License
 along with this program. If not, see <http://www.gnu.org/licenses/>.
-}
{-# LANGUAGE MagicHash #-}
{-# LANGUAGE UnboxedTuples #-}

module Idunn.Vector where

import Control.Monad (when)
import Control.Monad.IO.Class
import Data.IORef
import Foreign
import Foreign.C
import GHC.Exts
import GHC.IO hiding (liftIO)

data MutableBuffer = MutableBuffer (MutableByteArray# RealWorld)

data PinnedVector a = PinnedVector
  { bufferPtr :: Ptr (Ptr a),
    dirtyPtr :: Ptr CBool,
    sizePtr :: Ptr CSize,
    capPtr :: Ptr CSize,
    itemSize :: CSize,
    bufferRef :: IORef MutableBuffer
  }

dataPtr :: PinnedVector a -> IO (Ptr a)
dataPtr v = peek v.bufferPtr

getRawPtr :: MutableBuffer -> Ptr a
getRawPtr (MutableBuffer m#) = Ptr $ byteArrayContents# $ unsafeCoerce# m#

newVector :: forall a m. (Storable a, MonadIO m) => CSize -> m (PinnedVector a)
newVector initialCapacity = liftIO $ do
  let bytesPerItem = fromIntegral $ sizeOf @a undefined
  let totalBytes = initialCapacity * bytesPerItem

  buf <- IO $ \s# ->
    case newPinnedByteArray# (unI# (fromIntegral totalBytes)) s# of
      (# s1#, m# #) -> (# s1#, MutableBuffer m# #)

  pBuf <- malloc
  pDirty <- malloc
  pSize <- malloc
  pCap <- malloc

  poke pBuf $ getRawPtr buf
  poke pDirty $ fromBool False
  poke pSize 0
  poke pCap initialCapacity

  ref <- newIORef buf

  pure
    PinnedVector
      { bufferPtr = pBuf,
        dirtyPtr = pDirty,
        sizePtr = pSize,
        capPtr = pCap,
        itemSize = bytesPerItem,
        bufferRef = ref
      }

freeVector :: PinnedVector a -> IO ()
freeVector v = do
  free v.sizePtr
  free v.capPtr

unI# :: Int -> Int#
unI# (I# i) = i

resize :: PinnedVector a -> CSize -> IO ()
resize v newCapacity = do
  currentSize <- peek v.sizePtr
  oldData <- peek v.bufferPtr
  let newBytes = newCapacity * v.itemSize
  let oldBytes = currentSize * v.itemSize
  IO $ \s0# ->
    case newPinnedByteArray# (unI# (fromIntegral newBytes)) s0# of
      (# s1#, newMarr# #) -> do
        let newPData = Ptr (byteArrayContents# (unsafeCoerce# newMarr#))
        let s2# = copyAddrToByteArray# (case oldData of Ptr a# -> a#) newMarr# 0# (unI# (fromIntegral oldBytes)) s1#
        unIO
          ( do
              poke v.bufferPtr newPData
              poke v.capPtr newCapacity
          )
          s2#

pushBack :: (Storable a) => PinnedVector a -> a -> IO ()
pushBack v item = do
  sz <- peek v.sizePtr
  cp <- peek v.capPtr
  when (sz >= cp) $ resize v $ if cp == 0 then 1 else cp * 2
  pData <- peek v.bufferPtr
  let destAddr = pData `plusPtr` fromIntegral (sz * v.itemSize)
  poke destAddr item
  poke v.sizePtr (sz + 1)
  poke v.dirtyPtr $ fromBool True

cap :: PinnedVector a -> IO CSize
cap v = peek (capPtr v)

{-# INLINE readIndex #-}
readIndex :: (Storable a) => PinnedVector a -> Int -> IO a
readIndex v (I# i#) = do
  ptr <- dataPtr v
  IO $ \s# -> unIO (peekElemOff ptr (I# i#)) s#

{-# INLINE writeIndex #-}
writeIndex :: (Storable a) => PinnedVector a -> Int -> a -> IO ()
writeIndex v idx item = do
  ptr <- dataPtr v
  pokeElemOff ptr idx item
  poke v.dirtyPtr $ fromBool True
