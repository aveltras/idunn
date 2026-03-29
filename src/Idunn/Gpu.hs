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

module Idunn.Gpu
  ( Gpu (..),
    GpuWorld (..),
    initGpu,
    initGpuWorld,
  )
where

import Data.Kind (Type)
import Data.Text
import Data.Text.Foreign qualified as T
import Data.Void
import Foreign
import Foreign.C
import Foreign.C.ConstPtr
import Idunn.Gpu.FFI
import Idunn.Linear.Mat (Mat4x4)
import Idunn.Vector
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

data GpuWorld (vertex :: Type) = GpuWorld
  { handle :: Word64,
    vertices :: PinnedVector vertex,
    indices :: PinnedVector Word32,
    meshes :: PinnedVector Idunn_gpu_mesh,
    transforms :: PinnedVector Mat4x4,
    configPtr :: Ptr Idunn_gpu_world_config
  }

initGpuWorld :: forall vertex m. (MonadResource m) => Gpu -> PinnedVector vertex -> PinnedVector Word32 -> PinnedVector Idunn_gpu_mesh -> PinnedVector Mat4x4 -> m (GpuWorld vertex)
initGpuWorld gpu vertices indices meshes transforms = snd <$> allocate up down
  where
    up = alloca $ \pGpuWorld -> do
      configPtr <- malloc
      vertexCount <- peek vertices.sizePtr
      indexCount <- peek indices.sizePtr
      meshCount <- peek meshes.sizePtr
      poke configPtr $
        Idunn_gpu_world_config
          { idunn_gpu_world_config_vertexSize = fromIntegral vertices.itemSize,
            idunn_gpu_world_config_vertexCount = vertexCount,
            idunn_gpu_world_config_vertexData = castPtr @vertex @Void $ dataPtr vertices,
            idunn_gpu_world_config_indexSize = fromIntegral $ sizeOf @Word32 undefined,
            idunn_gpu_world_config_indexCount = indexCount,
            idunn_gpu_world_config_indexData = dataPtr indices,
            idunn_gpu_world_config_meshCount = meshCount,
            idunn_gpu_world_config_meshData = dataPtr meshes,
            idunn_gpu_world_config_transformData = castPtr $ dataPtr transforms
          }
      idunn_gpu_world_init gpu.ptr configPtr pGpuWorld
      handle <- peek pGpuWorld
      pure $
        GpuWorld
          { handle = handle,
            vertices = vertices,
            indices = indices,
            meshes = meshes,
            transforms = transforms,
            configPtr = configPtr
          }

    down world = do
      free world.configPtr
      idunn_gpu_world_uninit gpu.ptr world.handle
