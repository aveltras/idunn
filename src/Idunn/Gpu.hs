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
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE UndecidableInstances #-}

module Idunn.Gpu
  ( Gpu (..),
    HasGpu (..),
    GpuWorld (..),
    GpuMesh (..),
    initGpu,
    -- getGpuWorld,
    -- setNodeMesh,
  )
where

import Apecs (($=))
import Apecs.Core
import Control.Monad (forM_)
import Control.Monad.Reader.Class
import Data.Kind (Type)
import Data.Text hiding (length, show)
import Data.Text.Foreign qualified as T
import Data.Vector.Generic.Mutable qualified as MV
import Data.Void
import Foreign
import Foreign.C
import Foreign.C.ConstPtr
import Idunn.Gpu.FFI
import Idunn.Linear.Mat (Mat4x4)
import Idunn.Linear.Vec
import Idunn.Logger
import Idunn.Vector
import Idunn.World (HasWorldInit (..), Vertex (..), WorldInit (..))
import Paths_idunn qualified as Cabal
import System.Environment (lookupEnv)
import UnliftIO
import UnliftIO.Directory (canonicalizePath)
import UnliftIO.Resource

data Gpu = Gpu
  { ptr :: Ptr Void
  }

class HasGpu env where
  getGpu :: env -> Gpu

instance HasGpu Gpu where
  getGpu = id

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

newtype GpuWorld = GpuWorld
  { handle :: Word64
  }

instance (MonadIO m) => ExplGet m (GpuStore GpuWorld) where
  explExists _ _ = pure True
  explGet store _ = pure store.handle

data GpuStore c = GpuStore
  { handle :: GpuWorld,
    vertices :: PinnedVector Vertex,
    indices :: PinnedVector Word32,
    meshes :: PinnedVector Idunn_gpu_mesh
  }

instance (MonadIO m, MonadReader env m, HasGpu env, HasWorldInit env, MonadResource m) => ExplInit m (GpuStore GpuWorld) where
  explInit = do
    gpu <- asks getGpu
    meshes <- newVector 0
    vertices <- newVector 0
    indices <- newVector 0
    worldInit <- asks getWorldInit
    worldTransforms <- readIORef worldInit.worldTransforms
    gpuWorld <- initGpuWorld gpu vertices indices meshes worldTransforms
    pure $
      GpuStore
        { handle = gpuWorld,
          vertices = vertices,
          indices = indices,
          meshes = meshes
        }

instance (MonadIO m, Has w m GpuWorld) => Has w m GpuMesh where
  getStore = (castGpuStore :: GpuStore GpuWorld -> GpuStore GpuMesh) <$> getStore

castGpuStore :: GpuStore a -> GpuStore b
castGpuStore (GpuStore a b c d) = GpuStore a b c d

instance Component GpuWorld where
  type Storage GpuWorld = GpuStore GpuWorld

type instance Elem (GpuStore GpuWorld) = GpuWorld

data GpuMesh = GpuMesh
  { vertices :: [Vertex],
    indices :: [Word32]
  }

instance Component GpuMesh where
  type Storage GpuMesh = GpuStore GpuMesh

type instance Elem (GpuStore GpuMesh) = GpuMesh

instance (MonadIO m) => ExplSet m (GpuStore GpuMesh) where
  explSet store _entity gpuMesh = do
    _gpuMesh <- spawnMesh store.handle store.vertices store.indices store.meshes gpuMesh.vertices gpuMesh.indices
    pure ()

newtype GpuMeshHandle = GpuMeshHandle Int

spawnMesh :: (MonadIO m, Storable vertex) => GpuWorld -> PinnedVector vertex -> PinnedVector Word32 -> PinnedVector Idunn_gpu_mesh -> [vertex] -> [Word32] -> m GpuMeshHandle
spawnMesh world vertices indices meshes newVertices newIndices = liftIO $ do
  vertexOffset <- fromIntegral <$> peek vertices.sizePtr
  indexOffset <- fromIntegral <$> peek indices.sizePtr
  forM_ newVertices $ pushBack vertices
  forM_ newIndices $ pushBack indices
  meshOffset <- peek meshes.sizePtr
  pushBack meshes $
    Idunn_gpu_mesh
      { idunn_gpu_mesh_indexOffset = indexOffset,
        idunn_gpu_mesh_indexCount = fromIntegral $ length newIndices,
        idunn_gpu_mesh_vertexOffset = vertexOffset,
        idunn_gpu_mesh_vertexCount = fromIntegral $ length newVertices
      }
  pure $ GpuMeshHandle $ fromIntegral meshOffset

initGpuWorld :: forall vertex m. (MonadResource m) => Gpu -> PinnedVector vertex -> PinnedVector Word32 -> PinnedVector Idunn_gpu_mesh -> PinnedVector Mat4x4 -> m GpuWorld
initGpuWorld gpu vertices indices meshes transforms = snd <$> allocate up down
  where
    up = alloca $ \pGpuWorld -> do
      alloca $ \configPtr -> do
        poke configPtr $
          Idunn_gpu_world_config
            { idunn_gpu_world_config_vertexSize = fromIntegral vertices.itemSize,
              idunn_gpu_world_config_vertexCount = vertices.sizePtr,
              idunn_gpu_world_config_vertexDirty = vertices.dirtyPtr,
              idunn_gpu_world_config_vertexData = castPtr @(Ptr vertex) @(Ptr Void) vertices.bufferPtr,
              idunn_gpu_world_config_indexSize = fromIntegral $ sizeOf @Word32 undefined,
              idunn_gpu_world_config_indexCount = indices.sizePtr,
              idunn_gpu_world_config_indexDirty = indices.dirtyPtr,
              idunn_gpu_world_config_indexData = indices.bufferPtr,
              idunn_gpu_world_config_meshCount = meshes.sizePtr,
              idunn_gpu_world_config_meshDirty = meshes.dirtyPtr,
              idunn_gpu_world_config_meshData = meshes.bufferPtr,
              idunn_gpu_world_config_transformDirty = transforms.dirtyPtr,
              idunn_gpu_world_config_transformData = castPtr transforms.bufferPtr
            }
        idunn_gpu_world_init gpu.ptr configPtr pGpuWorld
        worldHandle <- peek pGpuWorld
        pure $ GpuWorld worldHandle

    down world = do
      idunn_gpu_world_uninit gpu.ptr world.handle
