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
    initGpu,
    Graphics (..),
    HasGraphics (..),
    initGraphics,
    Mesh,
    prepareRender,
    render,
  )
where

import Apecs (Map)
import Apecs.Core
import Apecs.Experimental.Reactive
import Control.Monad (forM_, void)
import Control.Monad.Reader
import Data.IntMap.Strict
import Data.IntSet (IntSet)
import Data.IntSet qualified as IntSet
import Data.Kind (Type)
import Data.Map.Strict qualified as Map
import Data.Text hiding (length, show)
import Data.Text.Foreign qualified as T
import Data.Vector.Storable qualified as VS
import Data.Void
import Foreign hiding (void)
import Foreign.C
import Foreign.C.ConstPtr
import Idunn.Gpu.FFI
import Idunn.Linear.Mat
import Idunn.Linear.Vec
import Idunn.Vector
import Idunn.World
import Paths_idunn qualified as Cabal
import System.Environment (lookupEnv)
import UnliftIO
import UnliftIO.Directory (canonicalizePath)
import UnliftIO.Resource

newtype Gpu = Gpu {ptr :: Ptr Void}

class HasGpu env where
  getGpu :: env -> Gpu

newtype Surface = Surface {ptr :: Ptr Void}

newtype Buffer (item :: Type) = Buffer {ptr :: Ptr Void}

newtype Pipeline = Pipeline {ptr :: Ptr Void}

newtype Sampler = Sampler {ptr :: Ptr Void}

newtype Texture = Texture {ptr :: Ptr Void}

initGpu :: (MonadResource m) => Text -> Word32 -> m Gpu
initGpu appName appVersion = do
  snd <$> allocate up down
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
              let config = Idunn_gpu_config (ConstPtr c'appName) appVersion (ConstPtr c'shadersPath)
              poke pConfig config
              idunn_gpu_init pConfig pGpu
              Gpu <$> peek pGpu
    down gpu = idunn_gpu_uninit gpu.ptr

data MeshLocation = MeshLocation
  { indexOffset :: Word32,
    indexCount :: Word32,
    vertexOffset :: Int32,
    vertexCount :: Word32
  }

prepareRender :: forall vertex w m. (MonadIO m, Has w m (Mesh vertex), Has w m WorldTransform) => Gpu -> Graphics vertex -> SystemT w m ()
prepareRender gpu graphics = do
  transforms :: SparseVector WorldTransform <- getStore
  meshReferences <- readIORef graphics.meshReferences
  loadedMeshes <- readIORef graphics.loadedMeshes
  clearPinned graphics.draws
  clearPinned graphics.meshInstances
  forM_ (Map.toList meshReferences) $ \(mesh, entities) -> do
    case Map.lookup mesh loadedMeshes of
      Nothing -> pure ()
      Just meshLocation -> do
        void $
          appendPinned graphics.draws $
            Idunn_gpu_draw
              { idunn_gpu_draw_indexCount = meshLocation.indexCount,
                idunn_gpu_draw_instanceCount = fromIntegral $ IntSet.size entities,
                idunn_gpu_draw_firstIndex = meshLocation.indexOffset,
                idunn_gpu_draw_vertexOffset = meshLocation.vertexOffset,
                idunn_gpu_draw_firstInstance = 0
              }
        forM_ (IntSet.elems entities) $ \entity -> do
          transformIdx <- readPinned transforms.sparse entity
          void $
            appendPinned graphics.meshInstances $
              Idunn_gpu_mesh_instance
                { idunn_gpu_mesh_instance_transformIdx = fromIntegral transformIdx
                }

  drawsSize <- liftIO $ peek graphics.draws.size
  drawBuffer <- readIORef graphics.draws.bufferRef
  writeBuffer gpu graphics.indirectBuffer (getRawPtr drawBuffer) (fromIntegral drawsSize) False

  instancesSize <- liftIO $ peek graphics.meshInstances.size
  instanceBuffer <- readIORef graphics.meshInstances.bufferRef
  writeBuffer gpu graphics.instanceBuffer (getRawPtr drawBuffer) (fromIntegral instancesSize) False

class HasGraphics vertex env where
  getGraphics :: env -> Graphics vertex

data Graphics (vertex :: Type) = Graphics
  { vertexBuffer :: Buffer vertex,
    vertexCount :: IORef Word32,
    indexBuffer :: Buffer Word32,
    indexCount :: IORef Word32,
    indirectBuffer :: Buffer Idunn_gpu_draw,
    instanceBuffer :: Buffer (),
    transformBuffer :: Buffer Mat4x4,
    loadedMeshes :: IORef (Map.Map (Mesh vertex) MeshLocation),
    meshReferences :: IORef (Map.Map (Mesh vertex) IntSet),
    draws :: PinnedVector' Idunn_gpu_draw,
    meshInstances :: PinnedVector' Idunn_gpu_mesh_instance
  }

initGraphics :: (MonadResource m) => Gpu -> m (Graphics vertex)
initGraphics gpu = do
  vertexBuffer <- initBuffer gpu 1024 IDUNN_GPU_BUFFER_USAGE_VERTEX
  vertexCount <- newIORef 0
  indexBuffer <- initBuffer gpu 1024 IDUNN_GPU_BUFFER_USAGE_INDEX
  indexCount <- newIORef 0
  indirectBuffer <- initBuffer gpu 1024 IDUNN_GPU_BUFFER_USAGE_INDIRECT
  instanceBuffer <- initBuffer gpu 1024 IDUNN_GPU_BUFFER_USAGE_STORAGE
  transformBuffer <- initBuffer gpu 1024 IDUNN_GPU_BUFFER_USAGE_STORAGE
  loadedMeshes <- newIORef mempty
  meshReferences <- newIORef mempty
  draws <- newPinned 10
  meshInstances <- newPinned 10
  pure
    Graphics
      { vertexBuffer = vertexBuffer,
        vertexCount = vertexCount,
        indexBuffer = indexBuffer,
        indexCount = indexCount,
        indirectBuffer = indirectBuffer,
        instanceBuffer = instanceBuffer,
        transformBuffer = transformBuffer,
        loadedMeshes = loadedMeshes,
        meshReferences = meshReferences,
        draws = draws,
        meshInstances = meshInstances
      }

render :: (MonadIO m) => Gpu -> Surface -> Graphics vertex -> Mat4x4 -> Word32 -> Word32 -> m ()
render gpu surface graphics projection width height = liftIO $ do
  alloca $ \pInfo -> do
    poke pInfo $
      Idunn_gpu_render_info
        { idunn_gpu_render_info_indexBuffer = graphics.indexBuffer.ptr,
          idunn_gpu_render_info_vertexBuffer = graphics.vertexBuffer.ptr,
          idunn_gpu_render_info_indirectBuffer = graphics.indirectBuffer.ptr,
          idunn_gpu_render_info_transformBuffer = graphics.transformBuffer.ptr,
          idunn_gpu_render_info_instanceBuffer = graphics.instanceBuffer.ptr,
          idunn_gpu_render_info_projection = toConstantArray projection
        }
    idunn_gpu_render gpu.ptr surface.ptr pInfo

uploadMesh :: (MonadUnliftIO m, Storable vertex) => Gpu -> Graphics vertex -> Mesh vertex -> m ()
uploadMesh gpu graphics meshDescription = do
  loadedMeshes <- readIORef graphics.loadedMeshes
  case Map.lookup meshDescription loadedMeshes of
    Just meshLocation -> pure ()
    Nothing -> do
      (indices, vertices) <- resolveMeshData meshDescription
      indexOffset <- readIORef graphics.indexCount
      vertexOffset <- readIORef graphics.vertexCount
      let meshLocation =
            MeshLocation
              { indexOffset = indexOffset,
                indexCount = fromIntegral $ VS.length indices,
                vertexOffset = fromIntegral vertexOffset,
                vertexCount = fromIntegral $ VS.length vertices
              }
      writeIORef graphics.indexCount $ indexOffset + meshLocation.indexCount
      writeIORef graphics.vertexCount $ vertexOffset + meshLocation.vertexCount
      writeIORef graphics.loadedMeshes $ Map.insert meshDescription meshLocation loadedMeshes
      withRunInIO $ \runInIO -> do
        VS.unsafeWith indices $ \pIndices -> runInIO $ writeBuffer gpu graphics.indexBuffer pIndices meshLocation.indexCount True
        VS.unsafeWith vertices $ \pVertices -> runInIO $ writeBuffer gpu graphics.vertexBuffer pVertices meshLocation.vertexCount True

resolveMeshData :: (MonadIO m) => Mesh vertex -> m (VS.Vector Word32, VS.Vector vertex)
resolveMeshData meshDescription = error "todo: resolveMeshData"

initBuffer :: (MonadResource m) => Gpu -> Word64 -> Idunn_gpu_buffer_usage -> m (Buffer item)
initBuffer gpu initialCapacity bufferUsage = snd <$> allocate up down
  where
    down buffer = idunn_gpu_buffer_uninit gpu.ptr buffer.ptr
    up =
      alloca $ \pBuffer -> do
        alloca $ \pConfig -> do
          poke pConfig $ Idunn_gpu_buffer_config initialCapacity bufferUsage
          idunn_gpu_buffer_init gpu.ptr pConfig pBuffer
          Buffer <$> peek pBuffer

writeBuffer :: (MonadIO m) => Gpu -> Buffer item -> Ptr item -> Word32 -> Bool -> m ()
writeBuffer gpu buffer items itemCount doAppend = liftIO $ do
  alloca $ \pInfo -> do
    poke pInfo $ Idunn_gpu_buffer_write_info (castPtr items) (fromIntegral itemCount) $ fromBool doAppend
    idunn_gpu_buffer_write gpu.ptr buffer.ptr pInfo

data Mesh (vertex :: Type) = MeshBox Float
  deriving stock (Eq, Ord)

instance Component (Mesh vertex) where
  type Storage (Mesh vertex) = Reactive (MeshLoader vertex) (Map (Mesh vertex))

data MeshLoader vertex = MeshLoader

type instance Elem (MeshLoader vertex) = Mesh vertex

instance (MonadUnliftIO m, MonadReader env m, HasGpu env, HasGraphics vertex env, Storable vertex) => Reacts m (MeshLoader vertex) where
  {-# INLINE rempty #-}
  rempty = do
    graphics :: Graphics vertex <- asks getGraphics
    pure MeshLoader
  {-# INLINE react #-}
  react _ Nothing Nothing _ = pure ()
  react (Entity entity) oldMeshM newMeshM loader = do
    graphics :: Graphics vertex <- asks getGraphics
    (meshToUnloadM, meshToLoadM) <- atomicModifyIORef' graphics.meshReferences updateReferences
    -- TODO: meshToUnloadM
    case meshToLoadM of
      Nothing -> pure ()
      Just meshToLoad -> do
        gpu <- asks getGpu
        uploadMesh gpu graphics meshToLoad
    where
      updateReferences refs =
        let (meshToUnloadM, refs') =
              case oldMeshM of
                Nothing -> (Nothing, refs)
                Just oldMesh ->
                  let (shouldUnload, refs'') = Map.alterF decr oldMesh refs
                   in (if shouldUnload then Just oldMesh else Nothing, refs')
            (meshToLoadM, refs'') =
              case newMeshM of
                Nothing -> (Nothing, refs')
                Just newMesh ->
                  let (shouldLoad, refs'') = Map.alterF incr newMesh refs'
                   in (if shouldLoad then Just newMesh else Nothing, refs'')
         in (refs'', (meshToUnloadM, meshToLoadM))
      decr = \case
        Nothing -> (False, Nothing)
        Just current -> (IntSet.size current == 1, Just $ IntSet.insert entity current)
      incr = \case
        Nothing -> (True, Just $ IntSet.singleton entity)
        Just current -> (False, Just $ IntSet.insert entity current)
