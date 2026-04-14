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

module Idunn.Linear.Mat
  ( Mat4x4,
    mkMat4x4,
    toConstantArray,
    identity,
    multiply,
    translate,
  )
where

import Data.Proxy
import Data.Vector.Storable qualified as VS
import Foreign.C
import Foreign.Storable
import GHC.Exts
import GHC.ForeignPtr
import GHC.IO
import HsBindgen.Runtime.ConstantArray qualified as CA
import Idunn.Linear.Vec

data Mat4x4 = Mat4x4 ByteArray#

mkMat4x4 :: Float -> Float -> Float -> Float -> Float -> Float -> Float -> Float -> Float -> Float -> Float -> Float -> Float -> Float -> Float -> Float -> Mat4x4
mkMat4x4 (F# m00) (F# m01) (F# m02) (F# m03) (F# m10) (F# m11) (F# m12) (F# m13) (F# m20) (F# m21) (F# m22) (F# m23) (F# m30) (F# m31) (F# m32) (F# m33) =
  unsafePerformIO $ IO $ \s0# -> do
    case newAlignedPinnedByteArray# 64# 16# s0# of
      (# s1, marr# #) ->
        let s2 = writeFloatArray# marr# 0# m00 s1
            s3 = writeFloatArray# marr# 1# m01 s2
            s4 = writeFloatArray# marr# 2# m02 s3
            s5 = writeFloatArray# marr# 3# m03 s4
            s6 = writeFloatArray# marr# 4# m10 s5
            s7 = writeFloatArray# marr# 5# m11 s6
            s8 = writeFloatArray# marr# 6# m12 s7
            s9 = writeFloatArray# marr# 7# m13 s8
            s10 = writeFloatArray# marr# 8# m20 s9
            s11 = writeFloatArray# marr# 9# m21 s10
            s12 = writeFloatArray# marr# 10# m22 s11
            s13 = writeFloatArray# marr# 11# m23 s12
            s14 = writeFloatArray# marr# 12# m30 s13
            s15 = writeFloatArray# marr# 13# m31 s14
            s16 = writeFloatArray# marr# 14# m32 s15
            s17 = writeFloatArray# marr# 15# m33 s16
         in case unsafeFreezeByteArray# marr# s17 of
              (# s18, arr# #) -> (# s18, Mat4x4 arr# #)

instance Storable Mat4x4 where
  sizeOf _ = 64
  alignment _ = 16
  poke (Ptr addr#) (Mat4x4 v#) = IO $ \s0# ->
    let s1# = copyByteArrayToAddr# v# 0# addr# 64# s0#
     in (# s1#, () #)
  peek (Ptr addr#) = IO $ \s0# ->
    case newAlignedPinnedByteArray# 64# 16# s0# of
      (# s1#, marr# #) ->
        let s2# = copyAddrToByteArray# addr# marr# 0# 64# s1#
         in case unsafeFreezeByteArray# marr# s2# of
              (# s3#, arr# #) -> (# s3#, Mat4x4 arr# #)

toConstantArray :: Mat4x4 -> CA.ConstantArray 16 CFloat
toConstantArray (Mat4x4 ba#) = do
  let fptr = ForeignPtr (byteArrayContents# ba#) (PlainPtr (unsafeCoerce# ba#))
  CA.fromVector (Proxy @16) $ VS.unsafeFromForeignPtr0 fptr 16

identity :: Mat4x4
identity = mkMat4x4 1 0 0 0 0 1 0 0 0 0 1 0 0 0 0 1

multiply :: Mat4x4 -> Mat4x4 -> Mat4x4
multiply (Mat4x4 p#) (Mat4x4 l#) = unsafePerformIO $ IO $ \s0# ->
  case newAlignedPinnedByteArray# 64# 16# s0# of
    (# s1#, marr# #) ->
      let at arr# i# = indexFloatArray# arr# i#
          writeRes# col# row# s# =
            let v# =
                  ((at p# row#) `timesFloat#` (at l# (col# *# 4#))) -- k=0: P[row,0] * L[0,col]
                    `plusFloat#` ((at p# (4# +# row#)) `timesFloat#` (at l# (col# *# 4# +# 1#))) -- k=1: P[row,1] * L[1,col]
                    `plusFloat#` ((at p# (8# +# row#)) `timesFloat#` (at l# (col# *# 4# +# 2#))) -- k=2: P[row,2] * L[2,col]
                    `plusFloat#` ((at p# (12# +# row#)) `timesFloat#` (at l# (col# *# 4# +# 3#))) -- k=3: P[row,3] * L[3,col]
             in writeFloatArray# marr# (col# *# 4# +# row#) v# s#
          s2 = writeRes# 0# 0# s1#
          s3 = writeRes# 0# 1# s2
          s4 = writeRes# 0# 2# s3
          s5 = writeRes# 0# 3# s4
          s6 = writeRes# 1# 0# s5
          s7 = writeRes# 1# 1# s6
          s8 = writeRes# 1# 2# s7
          s9 = writeRes# 1# 3# s8
          s10 = writeRes# 2# 0# s9
          s11 = writeRes# 2# 1# s10
          s12 = writeRes# 2# 2# s11
          s13 = writeRes# 2# 3# s12
          s14 = writeRes# 3# 0# s13
          s15 = writeRes# 3# 1# s14
          s16 = writeRes# 3# 2# s15
          s17 = writeRes# 3# 3# s16
       in case unsafeFreezeByteArray# marr# s17 of
            (# s18#, res# #) -> (# s18#, Mat4x4 res# #)

translate :: Mat4x4 -> Vec3 -> Mat4x4
translate (Mat4x4 m#) (Vec3 v#) =
  unsafePerformIO $ IO $ \s0# ->
    case newAlignedPinnedByteArray# 64# 16# s0# of
      (# s1#, marr# #) ->
        let vx# = indexFloatArray# v# 0#
            vy# = indexFloatArray# v# 1#
            vz# = indexFloatArray# v# 2#

            -- Lecture des axes de rotation/scale (Colonnes 0, 1, 2)
            m00# = indexFloatArray# m# 0#
            m10# = indexFloatArray# m# 1#
            m20# = indexFloatArray# m# 2#

            m01# = indexFloatArray# m# 4#
            m11# = indexFloatArray# m# 5#
            m21# = indexFloatArray# m# 6#

            m02# = indexFloatArray# m# 8#
            m12# = indexFloatArray# m# 9#
            m22# = indexFloatArray# m# 10#

            -- Lecture de la position actuelle (Colonne 3)
            mx# = indexFloatArray# m# 12#
            my# = indexFloatArray# m# 13#
            mz# = indexFloatArray# m# 14#

            -- Calcul de la nouvelle position en respectant la rotation/scale
            nx# = ((m00# `timesFloat#` vx#) `plusFloat#` (m01# `timesFloat#` vy#)) `plusFloat#` ((m02# `timesFloat#` vz#) `plusFloat#` mx#)
            ny# = ((m10# `timesFloat#` vx#) `plusFloat#` (m11# `timesFloat#` vy#)) `plusFloat#` ((m12# `timesFloat#` vz#) `plusFloat#` my#)
            nz# = ((m20# `timesFloat#` vx#) `plusFloat#` (m21# `timesFloat#` vy#)) `plusFloat#` ((m22# `timesFloat#` vz#) `plusFloat#` mz#)

            -- Copie de l'ancienne matrice, puis on écrase juste la colonne de translation
            s2# = copyByteArray# m# 0# marr# 0# 64# s1#
            s3# = writeFloatArray# marr# 12# nx# s2#
            s4# = writeFloatArray# marr# 13# ny# s3#
            s5# = writeFloatArray# marr# 14# nz# s4#
         in case unsafeFreezeByteArray# marr# s5# of
              (# s6#, res# #) -> (# s6#, Mat4x4 res# #)
