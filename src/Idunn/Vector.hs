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

import Foreign
import Foreign.C
import GHC.Exts
import GHC.IO

data PinnedVector a = PinnedVector
  { buffer :: MutableByteArray# RealWorld,
    sizePtr :: Ptr CSize,
    capPtr :: Ptr CSize,
    itemSize :: CSize
  }

dataPtr :: PinnedVector a -> Ptr a
dataPtr v = Ptr $ byteArrayContents# $ unsafeCoerce# $ buffer v

newVector :: forall a. (Storable a) => CSize -> IO (PinnedVector a)
newVector initialCapacity = IO $ \s0# ->
  let bytesPerItem = sizeOf @a undefined
      !(I# totalBytes#) = fromIntegral initialCapacity * bytesPerItem
   in case newPinnedByteArray# totalBytes# s0# of
        (# s1#, marr# #) ->
          case unIO malloc s1# of
            (# s2#, pSize #) ->
              case unIO malloc s2# of
                (# s3#, pCap #) ->
                  case unIO (poke pSize 0) s3# of
                    (# s4#, _ #) ->
                      case unIO (poke pCap initialCapacity) s4# of
                        (# s5#, _ #) ->
                          (# s5#, PinnedVector marr# pSize pCap (fromIntegral bytesPerItem) #)

freeVector :: PinnedVector a -> IO ()
freeVector v = do
  free v.sizePtr
  free v.capPtr

resize :: PinnedVector a -> CSize -> IO (PinnedVector a)
resize v newCapacity = do
  currentSize <- cap v
  IO $ \s0# -> do
    let !(I# newBytes#) = fromIntegral $ newCapacity * v.itemSize
        !(I# oldBytes#) = fromIntegral $ currentSize * v.itemSize
     in case newPinnedByteArray# newBytes# s0# of
          (# s1#, newMarr# #) ->
            let s2# = copyMutableByteArray# (buffer v) 0# newMarr# 0# oldBytes# s1#
             in case unIO (poke (capPtr v) newCapacity) s2# of
                  (# s3#, _ #) -> (# s3#, v {buffer = newMarr#} #)

pushBack :: forall a. (Storable a) => PinnedVector a -> a -> IO (PinnedVector a)
pushBack v item = do
  sz <- peek v.sizePtr
  cp <- peek v.capPtr
  v' <-
    if sz >= cp
      then resize v (if cp == 0 then 1 else cp * 2)
      else pure v
  let baseAddr = Ptr (byteArrayContents# (unsafeCoerce# (buffer v')))
      destAddr = baseAddr `plusPtr` fromIntegral (sz * v'.itemSize)
  poke destAddr item
  poke v'.sizePtr $ sz + 1
  pure v'

cap :: PinnedVector a -> IO CSize
cap v = peek (capPtr v)

{-# INLINE readIndex #-}
readIndex :: (Storable a) => PinnedVector a -> Int -> IO a
readIndex v (I# i#) = IO $ \s# -> unIO (peekElemOff (dataPtr v) (I# i#)) s#

{-# INLINE writeIndex #-}
writeIndex :: (Storable a) => PinnedVector a -> Int -> a -> IO ()
writeIndex v idx item = do
  let ptr = dataPtr v
  pokeElemOff ptr idx item
