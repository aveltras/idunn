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
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE UnboxedTuples #-}

module Idunn.Vector where

import Apecs.Core
import Control.Monad (unless, void, when)
import Control.Monad.IO.Class
import Data.Array.Byte (ByteArray (ByteArray))
import Data.IORef
import Data.Vector.Primitive qualified as PV
import Data.Vector.Unboxed.Base (Vector (V_Int))
import Foreign hiding (void)
import Foreign.C
import GHC.Exts
import GHC.IO hiding (liftIO)
import GHC.Word

data SparseVector a = SparseVector
  { sparse :: PinnedVector' Int,
    dense :: PinnedVector' a,
    denseToSparse :: PinnedVector' Int
  }

type instance Elem (SparseVector c) = c

instance (Storable c, MonadIO m) => ExplInit m (SparseVector c) where
  explInit = liftIO $ newSparseVector 0

instance (MonadIO m, Storable c) => ExplGet m (SparseVector c) where
  {-# INLINE explExists #-}
  explExists store entity = liftIO $ do
    sparseCapacity <- peek store.sparse.capacity
    if fromIntegral entity >= sparseCapacity
      then pure False
      else do
        denseIdx <- readPinned store.sparse entity
        pure $ denseIdx /= -1

  {-# INLINE explGet #-}
  explGet store entity = liftIO $ do
    denseIdx <- readPinned store.sparse entity
    readPinned store.dense denseIdx

instance (MonadIO m, Storable c) => ExplSet m (SparseVector c) where
  {-# INLINE explSet #-}
  explSet = insert

instance (MonadIO m, Storable c) => ExplDestroy m (SparseVector c) where
  {-# INLINE explDestroy #-}
  explDestroy = delete

instance (MonadIO m) => ExplMembers m (SparseVector c) where
  {-# INLINE explMembers #-}
  explMembers store = liftIO $ do
    size <- peek store.denseToSparse.size
    (MutableBuffer m#) <- readIORef store.denseToSparse.bufferRef
    IO $ \s# ->
      case unsafeFreezeByteArray# m# s# of
        (# s1#, ba# #) ->
          let primVec = PV.Vector 0 (fromIntegral size) (ByteArray ba#)
              unboxedVec = V_Int primVec
           in (# s1#, unboxedVec #)

newSparseVector :: (MonadIO m, Storable a) => CSize -> m (SparseVector a)
newSparseVector initialCap = liftIO $ do
  dense <- newPinned initialCap
  sparse <- newPinned initialCap
  denseToSparse <- newPinned initialCap
  fillSparseWithMinusOne sparse
  pure $ SparseVector sparse dense denseToSparse

insert :: (MonadIO m, Storable a) => SparseVector a -> Int -> a -> m ()
insert v sparseIdx value = liftIO $ do
  sparseCapacity <- peek v.sparse.capacity
  when (fromIntegral sparseIdx >= sparseCapacity) $ do
    let newCapacity = max (sparseCapacity * 2) (fromIntegral sparseIdx + 64)
    resizePinned v.sparse newCapacity
    fillSparseWithMinusOne v.sparse
  denseIdx <- readPinned v.sparse sparseIdx
  if denseIdx /= -1
    then writePinned v.dense denseIdx value
    else do
      newDenseIdx <- appendPinned v.dense value
      void $ appendPinned v.denseToSparse sparseIdx
      writePinned v.sparse sparseIdx newDenseIdx

fillSparseWithMinusOne :: PinnedVector' Int -> IO ()
fillSparseWithMinusOne v = do
  (MutableBuffer m#) <- readIORef v.bufferRef
  capacity <- peek v.capacity
  size <- peek v.size
  let diff = capacity - size
  unless (diff == 0) $ do
    let !(CSize (W64# offW#)) = size
        !(CSize (W64# lenW#)) = diff
    IO $ \s# ->
      let wordSize# = 8#
          byteOff# = word2Int# (word64ToWord# offW#) *# wordSize#
          byteLen# = word2Int# (word64ToWord# lenW#) *# wordSize#
          val# = 255#
          s1# = setByteArray# m# byteOff# byteLen# val# s#
       in (# s1#, () #)
    poke v.size capacity

delete :: (MonadIO m, Storable a) => SparseVector a -> Int -> m ()
delete v sparseIdx = liftIO $ do
  denseIdx <- readPinned v.sparse sparseIdx
  unless (denseIdx == -1) $ do
    denseSize <- peek v.dense.size
    let lastDenseIdx = fromIntegral $ denseSize - 1
    unless (denseIdx == lastDenseIdx) $ do
      lastDense <- readPinned v.dense lastDenseIdx
      lastSparseIdx <- readPinned v.denseToSparse lastDenseIdx
      writePinned v.dense denseIdx lastDense
      writePinned v.denseToSparse denseIdx lastSparseIdx
      writePinned v.sparse lastSparseIdx denseIdx
    writePinned v.sparse sparseIdx (-1)
    poke v.dense.size $ denseSize - 1
    poke v.denseToSparse.size $ denseSize - 1

data PinnedVector' a = PinnedVector'
  { bufferPtr :: Ptr (Ptr a),
    bufferRef :: IORef MutableBuffer,
    itemSize :: CSize,
    capacity :: Ptr CSize,
    size :: Ptr CSize
  }

newPinned :: forall m a. (MonadIO m, Storable a) => CSize -> m (PinnedVector' a)
newPinned capacity = liftIO $ do
  let itemSize = fromIntegral $ sizeOf (undefined :: a)
  buf <- allocateBuffer (capacity * itemSize)
  pCapacity <- malloc
  poke pCapacity capacity
  pSize <- malloc
  poke pSize 0
  pBuf <- malloc
  poke pBuf $ getRawPtr buf
  ref <- newIORef buf
  pure $ PinnedVector' pBuf ref itemSize pCapacity pSize

resizePinned :: (MonadIO m) => PinnedVector' a -> CSize -> m ()
resizePinned v newCapacity = do
  currentSize <- liftIO $ peek v.size
  oldData <- liftIO $ peek v.bufferPtr
  let newBytes = newCapacity * v.itemSize
  let oldBytes = currentSize * v.itemSize
  liftIO $ IO $ \s0# ->
    case newAlignedPinnedByteArray# (unI# (fromIntegral newBytes)) 16# s0# of
      (# s1#, newMarr# #) -> do
        let newPData = Ptr (byteArrayContents# (unsafeCoerce# newMarr#))
        let s2# = copyAddrToByteArray# (case oldData of Ptr a# -> a#) newMarr# 0# (unI# (fromIntegral oldBytes)) s1#
        unIO
          ( do
              poke v.bufferPtr newPData
              poke v.capacity newCapacity
              writeIORef v.bufferRef (MutableBuffer newMarr#)
          )
          s2#

appendPinned :: (MonadIO m, Storable a) => PinnedVector' a -> a -> m Int
appendPinned v item = liftIO $ do
  currentSize <- peek v.size
  currentCapacity <- peek v.capacity
  when (currentSize >= currentCapacity) $ resizePinned v $ min 1 (currentCapacity * 2)
  let writeIdx = fromIntegral currentSize
  writePinned v writeIdx item
  poke v.size $ currentSize + 1
  pure writeIdx

readPinned :: (MonadIO m, Storable a) => PinnedVector' a -> Int -> m a
readPinned v idx = liftIO $ do
  ptr <- peek v.bufferPtr
  peekElemOff ptr idx

clearPinned :: (MonadIO m) => PinnedVector' a -> m ()
clearPinned v = liftIO $ poke v.size 0

writePinned :: (Storable a) => PinnedVector' a -> Int -> a -> IO ()
writePinned v idx val = do
  ptr <- peek v.bufferPtr
  pokeElemOff ptr idx val

data MutableBuffer = MutableBuffer (MutableByteArray# RealWorld)

allocateBuffer :: CSize -> IO MutableBuffer
allocateBuffer (CSize (W64# bytes#)) = IO $ \s# ->
  case newAlignedPinnedByteArray# (word2Int# $ word64ToWord# bytes#) 16# s# of
    (# s1#, m# #) -> (# s1#, MutableBuffer m# #)

getRawPtr :: MutableBuffer -> Ptr a
getRawPtr (MutableBuffer m#) = Ptr $ byteArrayContents# $ unsafeCoerce# m#

data PinnedVector a = PinnedVector
  { bufferPtr :: Ptr (Ptr a),
    dirtyPtr :: Ptr CBool,
    sizePtr :: Ptr CSize,
    capPtr :: Ptr CSize,
    itemSize :: CSize,
    bufferRef :: IORef MutableBuffer
  }

dataPtr :: (MonadIO m) => PinnedVector a -> m (Ptr a)
dataPtr v = liftIO $ peek v.bufferPtr

newVector :: forall a m. (Storable a, MonadIO m) => CSize -> m (PinnedVector a)
newVector initialCapacity = liftIO $ do
  let bytesPerItem = fromIntegral $ sizeOf @a undefined
  let totalBytes = initialCapacity * bytesPerItem

  buf <- IO $ \s# ->
    case newAlignedPinnedByteArray# (unI# (fromIntegral totalBytes)) 16# s# of
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
  free v.bufferPtr
  free v.dirtyPtr

unI# :: Int -> Int#
unI# (I# i) = i

resize :: (MonadIO m) => PinnedVector a -> CSize -> m ()
resize v newCapacity = do
  currentSize <- liftIO $ peek v.sizePtr
  oldData <- liftIO $ peek v.bufferPtr
  let newBytes = newCapacity * v.itemSize
  let oldBytes = currentSize * v.itemSize
  liftIO $ IO $ \s0# ->
    case newAlignedPinnedByteArray# (unI# (fromIntegral newBytes)) 16# s0# of
      (# s1#, newMarr# #) -> do
        let newPData = Ptr (byteArrayContents# (unsafeCoerce# newMarr#))
        let s2# = copyAddrToByteArray# (case oldData of Ptr a# -> a#) newMarr# 0# (unI# (fromIntegral oldBytes)) s1#
        unIO
          ( do
              poke v.bufferPtr newPData
              poke v.capPtr newCapacity
              writeIORef v.bufferRef (MutableBuffer newMarr#)
          )
          s2#

pushBack :: (MonadIO m, Storable a) => PinnedVector a -> a -> m ()
pushBack v item = do
  sz <- liftIO $ peek v.sizePtr
  cp <- liftIO $ peek v.capPtr
  when (sz >= cp) $ resize v $ if cp == 0 then 1 else cp * 2
  pData <- liftIO $ peek v.bufferPtr
  let destAddr = pData `plusPtr` fromIntegral (sz * v.itemSize)
  liftIO $ poke destAddr item
  liftIO $ poke v.sizePtr (sz + 1)
  liftIO $ poke v.dirtyPtr $ fromBool True

cap :: PinnedVector a -> IO CSize
cap v = peek (capPtr v)

{-# INLINE readIndex #-}
readIndex :: (MonadIO m, Storable a) => PinnedVector a -> Int -> m a
readIndex v (I# i#) = do
  ptr <- dataPtr v
  liftIO $ IO $ \s# -> unIO (peekElemOff ptr (I# i#)) s#

{-# INLINE writeIndex #-}
writeIndex :: (MonadIO m, Storable a) => PinnedVector a -> Int -> a -> m ()
writeIndex v idx item = do
  ptr <- dataPtr v
  liftIO $ pokeElemOff ptr idx item
  liftIO $ poke v.dirtyPtr $ fromBool True
