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

module Idunn.Gpu where

import Data.Text
import Data.Text.Foreign qualified as T
import Data.Void
import Foreign
import Foreign.C
import Foreign.C.ConstPtr
import Idunn.Gpu.FFI
import Paths_idunn qualified as Cabal
import UnliftIO.Resource

data Gpu = Gpu
  { ptr :: Ptr Void
  }

initGpu :: (MonadResource m) => Text -> Word32 -> m Gpu
initGpu appName version = snd <$> allocate up down
  where
    up =
      alloca $ \pGpu ->
        alloca $ \pConfig ->
          T.withCString appName $ \c'appName -> do
            shadersPath <- Cabal.getDataFileName "shaders"
            withCString shadersPath $ \c'shadersPath -> do
              let config = Idunn_gpu_config (ConstPtr c'appName) version (ConstPtr c'shadersPath)
              poke pConfig config
              idunn_gpu_init pConfig pGpu
              Gpu <$> peek pGpu
    down gpu = idunn_gpu_uninit gpu.ptr
