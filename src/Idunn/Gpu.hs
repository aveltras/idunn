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
    Mesh,
    initGpu,
    initGpuWorld,
    spawnMesh,
  )
where

import Control.Monad (forM_)
import Data.Kind (Type)
import Data.Text hiding (length, show)
import Data.Text.Foreign qualified as T
import Data.Void
import Foreign
import Foreign.C
import Foreign.C.ConstPtr
import Idunn.Gpu.FFI
import Idunn.Linear.Mat (Mat4x4)
import Idunn.Logger
import Idunn.Vector
import Paths_idunn qualified as Cabal
import System.Environment (lookupEnv)
import UnliftIO
import UnliftIO.Directory (canonicalizePath)
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
            mPath <- lookupEnv "IDUNN_SHADERS_PATH"
            shadersPath <- case mPath of
              Just path -> canonicalizePath path
              Nothing -> Cabal.getDataFileName "shaders"
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
    transforms :: PinnedVector Mat4x4
  }

initGpuWorld :: forall vertex m. (MonadResource m) => Gpu -> PinnedVector vertex -> PinnedVector Word32 -> PinnedVector Idunn_gpu_mesh -> PinnedVector Mat4x4 -> m (GpuWorld vertex)
initGpuWorld gpu vertices indices meshes transforms = snd <$> allocate up down
  where
    up = alloca $ \pGpuWorld -> do
      alloca $ \configPtr -> do
        meshPtr <- peek meshes.bufferPtr
        transformPtr <- peek transforms.bufferPtr
        poke configPtr $
          Idunn_gpu_world_config
            { idunn_gpu_world_config_vertexSize = fromIntegral vertices.itemSize,
              idunn_gpu_world_config_vertexCount = vertices.sizePtr,
              idunn_gpu_world_config_vertexData = castPtr @(Ptr vertex) @(Ptr Void) vertices.bufferPtr,
              idunn_gpu_world_config_indexSize = fromIntegral $ sizeOf @Word32 undefined,
              idunn_gpu_world_config_indexCount = indices.sizePtr,
              idunn_gpu_world_config_indexData = indices.bufferPtr,
              idunn_gpu_world_config_meshCount = meshes.sizePtr,
              idunn_gpu_world_config_meshData = meshes.bufferPtr,
              idunn_gpu_world_config_transformData = castPtr transforms.bufferPtr
            }
        idunn_gpu_world_init gpu.ptr configPtr pGpuWorld
        worldHandle <- peek pGpuWorld
        pure $
          GpuWorld
            { handle = worldHandle,
              vertices = vertices,
              indices = indices,
              meshes = meshes,
              transforms = transforms
            }

    down world = do
      idunn_gpu_world_uninit gpu.ptr world.handle

newtype Mesh = Mesh Int

spawnMesh :: (MonadIO m, Storable vertex) => GpuWorld vertex -> [vertex] -> [Word32] -> m Mesh
spawnMesh world vertices indices = liftIO $ do
  vertexOffset <- fromIntegral <$> peek world.vertices.sizePtr
  indexOffset <- fromIntegral <$> peek world.indices.sizePtr
  forM_ vertices $ pushBack world.vertices
  forM_ indices $ pushBack world.indices
  meshOffset <- peek world.meshes.sizePtr
  pushBack world.meshes $
    Idunn_gpu_mesh
      { idunn_gpu_mesh_indexOffset = indexOffset,
        idunn_gpu_mesh_indexCount = fromIntegral $ length indices,
        idunn_gpu_mesh_vertexOffset = vertexOffset,
        idunn_gpu_mesh_vertexCount = fromIntegral $ length vertices
      }
  pure $ Mesh $ fromIntegral meshOffset
