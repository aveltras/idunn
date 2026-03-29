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

module Idunn.Linear.Vec
  ( Vec3,
    mkVec3,
  )
where

import Foreign.Storable
import GHC.Exts
import GHC.IO

data Vec3 = Vec3 ByteArray#

instance Storable Vec3 where
  sizeOf _ = 12
  alignment _ = 4
  poke (Ptr addr#) (Vec3 v#) = IO $ \s0# ->
    let s1# = copyByteArrayToAddr# v# 0# addr# 12# s0#
     in (# s1#, () #)
  peek (Ptr addr#) = IO $ \s0# ->
    case newPinnedByteArray# 12# s0# of
      (# s1#, marr# #) ->
        let s2# = copyAddrToByteArray# addr# marr# 0# 12# s1#
         in case unsafeFreezeByteArray# marr# s2# of
              (# s3#, arr# #) -> (# s3#, Vec3 arr# #)

mkVec3 :: Float -> Float -> Float -> Vec3
mkVec3 (F# x) (F# y) (F# z) =
  unsafeDupablePerformIO $ IO $ \s0# -> do
    case newAlignedPinnedByteArray# 12# 8# s0# of
      (# s1, marr# #) ->
        let s2 = writeFloatArray# marr# 0# x s1
            s3 = writeFloatArray# marr# 1# y s2
            s4 = writeFloatArray# marr# 2# z s3
         in case unsafeFreezeByteArray# marr# s4 of
              (# s5, arr# #) -> (# s5, Vec3 arr# #)

instance Show Vec3 where
  show (Vec3 arr#) =
    let x = F# (indexFloatArray# arr# 0#)
        y = F# (indexFloatArray# arr# 1#)
        z = F# (indexFloatArray# arr# 2#)
     in "(" ++ show x ++ ", " ++ show y ++ ", " ++ show z ++ ")"
