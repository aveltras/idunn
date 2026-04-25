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
{-# LANGUAGE FunctionalDependencies #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE UndecidableInstances #-}

module Idunn.Gpu
  ( Gpu,
    HasGpu (..),
    MonadGpu (..),
    initGpu,
    Surface,
    initSurface,
    Graphics (..),
    HasGraphics (..),
    MonadGraphics (..),
    initGraphics,
    Mesh (..),
    prepareRender,
    render,
  )
where

import Apecs (Map)
import Apecs.Core
import Apecs.Experimental.Reactive
import Control.Monad (forM_, void, when)
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
import Debug.Trace (traceShowId)
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

newtype Command s = Command {ptr :: Ptr Void}

newtype Surface = Surface {ptr :: Ptr Void}

newtype Buffer (item :: Type) = Buffer {ptr :: Ptr Void}

newtype Pipeline = Pipeline {ptr :: Ptr Void}

newtype Sampler = Sampler {ptr :: Ptr Void}

newtype Texture = Texture {ptr :: Ptr Void}

class MonadGpu m where
  getGpuM :: m Gpu

class HasGpu env where
  getGpu :: env -> Gpu

-- instance (MonadReader env m, HasGpu env) => MonadGpu m where
--   getGpuM = asks getGpu

class (Monad m, Storable vertex, Typeable vertex) => MonadGraphics vertex m | m -> vertex where
  getGraphicsM :: m (Graphics vertex)

class HasGraphics vertex env where
  getGraphics :: env -> Graphics vertex

-- instance (MonadGraphics m) => MonadGraphics (SystemT w m) where
--   type GraphicsVertex (SystemT w m) = GraphicsVertex m
--   getGraphicsM = lift getGraphicsM

initGpu :: (MonadResource m) => Text -> Word32 -> m Gpu
initGpu appName appVersion = snd <$> allocate up down
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

initSurface :: (MonadResource m) => Gpu -> Ptr Void -> Word32 -> Word32 -> m Surface
initSurface gpu pWindow width height = snd <$> allocate up down
  where
    up =
      alloca $ \pSurface ->
        alloca $ \pConfig -> do
          let config = Idunn_gpu_surface_config width height pWindow
          poke pConfig config
          idunn_gpu_surface_init gpu.ptr pConfig pSurface
          Surface <$> peek pSurface
    down surface = idunn_gpu_surface_uninit surface.ptr

data MeshLocation = MeshLocation
  { indexOffset :: Word32,
    indexCount :: Word32,
    vertexOffset :: Int32,
    vertexCount :: Word32
  }

prepareRender :: forall vertex w m. (MonadIO m, Has w m (Mesh vertex), Has w m WorldTransform) => Gpu -> Graphics vertex -> SystemT w m ()
prepareRender gpu graphics = do
  shouldSync <- readIORef graphics.shouldSync
  when shouldSync $ do
    writeIORef graphics.shouldSync False
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
              traceShowId $
                Idunn_gpu_draw
                  { idunn_gpu_draw_indexCount = meshLocation.indexCount,
                    idunn_gpu_draw_instanceCount = fromIntegral $ IntSet.size entities,
                    idunn_gpu_draw_firstIndex = meshLocation.indexOffset,
                    idunn_gpu_draw_vertexOffset = meshLocation.vertexOffset,
                    idunn_gpu_draw_firstInstance = 0
                  }
          -- TODO: handle missing transform
          forM_ (IntSet.elems entities) $ \entity -> do
            transformIdx <- readPinned transforms.sparse entity
            void $
              appendPinned graphics.meshInstances $
                Idunn_gpu_mesh_instance
                  { idunn_gpu_mesh_instance_transformIdx = transformIdx
                  }

    liftIO $ submitCommands gpu $ \command -> do
      transformBuffer <- readIORef transforms.dense.bufferRef
      transformSize <- liftIO $ peek transforms.dense.size
      writeBuffer graphics.transformBuffer command (getRawPtr transformBuffer) (transformSize * transforms.dense.itemSize) False
      drawsSize <- liftIO $ peek graphics.draws.size
      drawBuffer <- readIORef graphics.draws.bufferRef
      putStrLn "draws size:"
      print drawsSize
      writeBuffer graphics.indirectBuffer command (getRawPtr drawBuffer) (drawsSize * graphics.draws.itemSize) False
      instancesSize <- liftIO $ peek graphics.meshInstances.size
      instanceBuffer <- readIORef graphics.meshInstances.bufferRef
      putStrLn "instance size:"
      print instancesSize
      writeBuffer graphics.instanceBuffer command (getRawPtr instanceBuffer) (instancesSize * graphics.meshInstances.itemSize) False

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
    draws :: PinnedVector Idunn_gpu_draw,
    meshInstances :: PinnedVector Idunn_gpu_mesh_instance,
    mainPipeline :: Pipeline,
    shouldSync :: IORef Bool
  }

-- #ifndef NDEBUG
--   vertexBufferDesc.debugName = "Vertex Buffer";
--   indexBufferDesc.debugName = "Index Buffer";
--   indirectBufferDesc.debugName = "Indirect Buffer";
--   transformBufferDesc.debugName = "Transform Buffer";
--   drawBufferDesc.debugName = "Draw Buffer";
--   pipelineDesc.debugName = "Pipeline";
-- #endif

initGraphics :: (MonadResource m) => Gpu -> m (Graphics vertex)
initGraphics gpu = do
  vertexBuffer <- initBuffer gpu 1024 IDUNN_GPU_BUFFER_USAGE_VERTEX
  vertexCount <- newIORef 0
  indexBuffer <- initBuffer gpu 1024 IDUNN_GPU_BUFFER_USAGE_INDEX
  indexCount <- newIORef 0
  indirectBuffer <- initBuffer gpu 1024 IDUNN_GPU_BUFFER_USAGE_INDIRECT
  instanceBuffer <- initBuffer gpu 1024 IDUNN_GPU_BUFFER_USAGE_STORAGE
  transformBuffer <- initBuffer gpu 1024 IDUNN_GPU_BUFFER_USAGE_STORAGE
  mainPipeline <- initPipeline gpu IDUNN_GPU_PIPELINE_WINDING_ORDER_CLOCKWISE
  loadedMeshes <- newIORef mempty
  meshReferences <- newIORef mempty
  draws <- newPinned 10
  meshInstances <- newPinned 10
  shouldSync <- newIORef True
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
        mainPipeline = mainPipeline,
        draws = draws,
        meshInstances = meshInstances,
        shouldSync = shouldSync
      }

render :: (MonadIO m) => Surface -> Graphics vertex -> Mat4x4 -> Word32 -> Word32 -> m ()
render surface graphics projection width height = liftIO $ do
  alloca $ \pInfo -> do
    meshCount <- peek graphics.draws.size
    poke pInfo $
      Idunn_gpu_render_info
        { idunn_gpu_render_info_indexBuffer = graphics.indexBuffer.ptr,
          idunn_gpu_render_info_vertexBuffer = graphics.vertexBuffer.ptr,
          idunn_gpu_render_info_indirectBuffer = graphics.indirectBuffer.ptr,
          idunn_gpu_render_info_transformBuffer = graphics.transformBuffer.ptr,
          idunn_gpu_render_info_instanceBuffer = graphics.instanceBuffer.ptr,
          idunn_gpu_render_info_projection = toConstantArray projection,
          idunn_gpu_render_info_pipeline = graphics.mainPipeline.ptr,
          idunn_gpu_render_info_instanceCount = fromIntegral meshCount
        }
    idunn_gpu_surface_render surface.ptr pInfo

uploadMesh :: forall vertex m. (MonadIO m, Storable vertex) => Gpu -> Graphics vertex -> Mesh vertex -> m ()
uploadMesh gpu graphics mesh = do
  loadedMeshes <- readIORef graphics.loadedMeshes
  case Map.lookup mesh loadedMeshes of
    Just _meshLocation -> pure ()
    Nothing -> do
      indexOffset <- readIORef graphics.indexCount
      vertexOffset <- readIORef graphics.vertexCount
      let meshLocation =
            MeshLocation
              { indexOffset = indexOffset,
                indexCount = fromIntegral $ VS.length mesh.indices,
                vertexOffset = fromIntegral vertexOffset,
                vertexCount = fromIntegral $ VS.length mesh.vertices
              }
      writeIORef graphics.indexCount $ indexOffset + meshLocation.indexCount
      writeIORef graphics.vertexCount $ vertexOffset + meshLocation.vertexCount
      writeIORef graphics.loadedMeshes $ Map.insert mesh meshLocation loadedMeshes

      liftIO $ withRunInIO $ \runInIO -> do
        submitCommands gpu $ \command -> do
          putStrLn "SUBMIT VERTICES & INDICES"
          print $ ("indexWriteSize", fromIntegral (sizeOf @Word32 undefined) * fromIntegral meshLocation.indexCount)
          VS.unsafeWith mesh.indices $ \pIndices -> runInIO $ writeBuffer graphics.indexBuffer command pIndices (fromIntegral (sizeOf @Word32 undefined) * fromIntegral meshLocation.indexCount) True
          VS.unsafeWith mesh.vertices $ \pVertices -> runInIO $ writeBuffer graphics.vertexBuffer command pVertices (fromIntegral (sizeOf @vertex undefined) * fromIntegral meshLocation.vertexCount) True

      writeIORef graphics.shouldSync True

submitCommands :: (MonadUnliftIO m) => Gpu -> (forall s. Command s -> m a) -> m a
submitCommands gpu f = do
  withRunInIO $ \runInIO -> do
    liftIO $ alloca $ \pCommand -> runInIO $ do
      liftIO $ idunn_gpu_command_init gpu.ptr pCommand
      command <- liftIO $ peek pCommand
      result <- f $ Command command
      liftIO $ idunn_gpu_command_submit gpu.ptr command
      pure result

initBuffer :: (MonadResource m) => Gpu -> Word64 -> Idunn_gpu_buffer_usage -> m (Buffer item)
initBuffer gpu initialCapacity bufferUsage = snd <$> allocate up down
  where
    down buffer = idunn_gpu_buffer_uninit buffer.ptr
    up =
      alloca $ \pBuffer -> do
        alloca $ \pConfig -> do
          poke pConfig $ Idunn_gpu_buffer_config initialCapacity bufferUsage
          idunn_gpu_buffer_init gpu.ptr pConfig pBuffer
          Buffer <$> peek pBuffer

writeBuffer :: (MonadIO m) => Buffer item -> Command s -> Ptr item -> CSize -> Bool -> m ()
writeBuffer buffer command items writeSize doAppend = liftIO $ do
  alloca $ \pInfo -> do
    print ("WRITE SIZE" :: String, writeSize)
    poke pInfo $ Idunn_gpu_buffer_write_info (castPtr items) writeSize $ fromBool doAppend
    idunn_gpu_buffer_write buffer.ptr command.ptr pInfo

initPipeline :: (MonadResource m) => Gpu -> Idunn_gpu_pipeline_winding_order -> m Pipeline
initPipeline gpu windingOrder = snd <$> allocate up down
  where
    down pipeline = idunn_gpu_pipeline_uninit pipeline.ptr
    up =
      withCString "basic" $ \c'shader ->
        alloca $ \pPipeline ->
          alloca $ \pConfig -> do
            poke pConfig $ Idunn_gpu_pipeline_config windingOrder (ConstPtr c'shader)
            idunn_gpu_pipeline_init gpu.ptr pConfig pPipeline
            Pipeline <$> peek pPipeline

data Mesh (vertex :: Type) = Mesh
  { key :: Int,
    vertices :: VS.Vector vertex,
    indices :: VS.Vector Word32
  }
  deriving stock (Typeable)

instance Eq (Mesh vertex) where
  (==) x y = x.key == y.key

instance Ord (Mesh vertex) where
  compare x y = compare x.key y.key

instance Component (Mesh vertex) where
  type Storage (Mesh vertex) = Reactive (MeshLoader vertex) (Map (Mesh vertex))

data MeshLoader vertex = MeshLoader

type instance Elem (MeshLoader vertex) = Mesh vertex

instance (MonadIO m, MonadGpu m, MonadGraphics vertex m) => Reacts m (MeshLoader vertex) where
  {-# INLINE rempty #-}
  rempty = do
    graphics :: Graphics vertex <- getGraphicsM
    pure MeshLoader
  {-# INLINE react #-}
  react _ Nothing Nothing _ = pure ()
  react (Entity entity) oldMeshM newMeshM loader = do
    graphics :: Graphics vertex <- getGraphicsM
    (meshToUnloadM, meshToLoadM) <- atomicModifyIORef' graphics.meshReferences updateReferences
    -- TODO: meshToUnloadM
    case meshToLoadM of
      Nothing -> pure ()
      Just meshToLoad -> do
        gpu <- getGpuM
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
