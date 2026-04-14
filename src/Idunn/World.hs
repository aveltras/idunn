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

module Idunn.World
  ( World (..),
    World3D,
    MonadWorld (..),
    Transform (..),
    Node (..),
    initWorld,
    spawnNodeImpl,
    WorldTransform (..),
    LocalTransform (..),
    WorldTransformUpdated (..),
    propagateWorldTransformUpdates,
    -- update,
    -- spawn,
    -- spawnChildOf,
    -- setMesh,
    -- setRigidBody,
    -- withPhysics,
  )
where

-- import Idunn.Gpu (HasGpu (getGpu))
-- import Idunn.Gpu qualified as Gpu

-- import Idunn.Physics (HasPhysics (..), IsPhysicsSystem)
-- import Idunn.Physics qualified as Physics

import Apecs
import Apecs.Core
import Apecs.Experimental.Children
import Control.Monad (forM_, unless, when)
import Control.Monad.Reader
import Data.IntMap.Strict (IntMap)
import Data.IntMap.Strict qualified as IntMap
import Data.Unique
import Data.Vector.Generic.Mutable qualified as MV
import Data.Vector.Mutable (MVector)
import Data.Word (Word32)
import Foreign (Storable)
import GHC.Exts (RealWorld)
import Idunn.Linear.Mat
import Idunn.Linear.Vec
import Idunn.Vector
import Language.Haskell.TH
import UnliftIO
import UnliftIO.Resource (MonadResource)

newtype WorldTransform = WorldTransform Mat4x4
  deriving newtype (Storable)

instance Component WorldTransform where
  type Storage WorldTransform = SparseVector WorldTransform

newtype LocalTransform = LocalTransform Mat4x4
  deriving newtype (Storable)

instance Component LocalTransform where
  type Storage LocalTransform = SparseVector LocalTransform

data WorldTransformUpdated = WorldTransformUpdated
  deriving stock (Show)

instance Component WorldTransformUpdated where
  type Storage WorldTransformUpdated = Map WorldTransformUpdated

propagateWorldTransformUpdates ::
  ( MonadIO m,
    Has w m WorldTransformUpdated,
    Has w m WorldTransform,
    Has w m (ChildList LocalTransform),
    Has w m (Child LocalTransform)
  ) =>
  SystemT w m ()
propagateWorldTransformUpdates = do
  hasUpdatedChildrenRef <- newIORef False
  cmapM $ \(WorldTransformUpdated, WorldTransform worldTransform, ChildList children :: ChildList LocalTransform) -> do
    writeIORef hasUpdatedChildrenRef True
    forM_ children $ \child -> do
      ChildValue (LocalTransform childTransform) <- get child
      child $= (WorldTransformUpdated, WorldTransform (multiplyTransform worldTransform childTransform))
    pure $ Not @WorldTransformUpdated
  hasUpdatedChildren <- readIORef hasUpdatedChildrenRef
  when hasUpdatedChildren propagateWorldTransformUpdates

type World3D = World Mat4x4

data HierarchyNode = HierarchyNode
  { parent :: Int,
    firstChild :: Int,
    nextSibling :: Int,
    level :: Int,
    hasBody :: Bool -- TODO: merge with level into data field
  }

data World transform = World
  { hierarchy :: IORef (MVector RealWorld HierarchyNode),
    maxNodeLevel :: IORef Int,
    dirtyNodes :: IORef (MVector RealWorld (Int, MVector RealWorld Int)),
    localTransforms :: PinnedVector transform,
    worldTransforms :: PinnedVector transform
  }

-- syncWorldTransforms :: (MonadIO m, Storable transform, Transform transform) => World transform -> m ()
-- syncWorldTransforms world = do
--   hierarchy <- readIORef world.hierarchy
--   dirtyNodes <- readIORef world.dirtyNodes
--   currentMaxLevel <- readIORef world.maxNodeLevel
--   forM_ [1 .. currentMaxLevel] $ \level -> do
--     (size, levelDirtyNodes) <- liftIO $ MV.unsafeRead dirtyNodes level
--     unless (size == 0) $ do
--       forM_ [0 .. size - 1] $ \offset -> do
--         nodeIdx <- liftIO $ MV.unsafeRead levelDirtyNodes offset
--         node <- liftIO $ MV.unsafeRead hierarchy nodeIdx
--         unless node.hasBody $ do
--           parentWorldTransform <- readIndex world.worldTransforms node.parent
--           localTransform <- readIndex world.localTransforms nodeIdx
--           let worldTransform = multiplyTransform parentWorldTransform localTransform
--           writeIndex world.worldTransforms nodeIdx worldTransform
--       liftIO $ MV.unsafeWrite dirtyNodes level (0, levelDirtyNodes)

class HasWorld env transform where
  getWorld :: env -> World transform

initWorld :: (MonadIO m, Storable transform) => m (World transform)
initWorld = do
  hierarchy <- liftIO $ newIORef =<< MV.new 0
  worldTransforms <- newVector 0
  localTransforms <- newVector 0
  dirtyNodes <- liftIO $ newIORef =<< MV.new 0
  nodeMaxLevel <- newIORef (-1)
  pure
    World
      { hierarchy = hierarchy,
        maxNodeLevel = nodeMaxLevel,
        dirtyNodes = dirtyNodes,
        worldTransforms = worldTransforms,
        localTransforms = localTransforms
      }

-- update :: (MonadIO m, Has w m Node, Has w m Transform) => Float -> w -> m (Gpu.World Vertex)
-- update deltaTime = runSystem $ do
--   store :: WorldStore Node <- getStore
--   frameStartAt <- readIORef store.time
--   let frameEndAt = frameStartAt + deltaTime
--   writeIORef store.time frameEndAt
--   physicsSystems <- readIORef store.physicsSystems
--   forM_ physicsSystems $ \(APhysicsSystem physicsSystem) -> do
--     let period = 1 / 60
--     let shouldTrigger = floor (frameStartAt / period) /= (floor (frameEndAt / period) :: Integer)
--     when shouldTrigger $ Physics.update physicsSystem $ \nodeIdx -> markDirty store $ Node nodeIdx
--   syncWorldTransforms
--   pure store.gpuWorld

-- spawn :: (MonadIO m, Has w m Node, Has w m EntityCounter) => Mat4x4 -> SystemT w m NodeEntity
-- spawn transform = do
--   entity <- newEntity (Transform Nothing transform)
--   node <- get entity
--   pure $ NodeEntity node entity

-- spawnChildOf :: (MonadIO m, Has w m Node, Has w m EntityCounter) => NodeEntity -> Mat4x4 -> SystemT w m NodeEntity
-- spawnChildOf parent transform = do
--   entity <- newEntity (Transform (Just parent.node) transform)
--   node <- get entity
--   pure $ NodeEntity node entity

-- setMesh :: (MonadIO m, Has w m Node, Has w m Mesh) => NodeEntity -> [Vertex] -> [Word32] -> SystemT w m ()
-- setMesh nodeEntity vertices indices = do
--   store :: WorldStore Node <- getStore
--   mesh <- Gpu.initMesh store.gpuWorld vertices indices
--   set nodeEntity.entity $ Mesh mesh

-- setRigidBody ::
--   ( MonadIO m,
--     Has w m RigidBody,
--     IsPhysicsSystem broadPhaseLayer objectLayer,
--     Physics.Shape shape
--   ) =>
--   NodeEntity ->
--   Physics.System s broadPhaseLayer objectLayer ->
--   Vec3 ->
--   Physics.MotionType ->
--   objectLayer ->
--   Physics.ShapeSettings shape ->
--   SystemT w m ()
-- setRigidBody nodeEntity physicsSystem position motionType objectLayer shapeSettings = do
--   Physics.initRigidBody physicsSystem nodeEntity.node.unNode3D position motionType objectLayer shapeSettings
--   set nodeEntity.entity $ RigidBody nodeEntity.node

-- data APhysicsSystem
--   = forall broadPhaseLayer objectLayer s.
--     (IsPhysicsSystem broadPhaseLayer objectLayer) =>
--     APhysicsSystem (Physics.System s broadPhaseLayer objectLayer)

-- withPhysics ::
--   forall broadPhaseLayer objectLayer env w m a.
--   ( IsPhysicsSystem broadPhaseLayer objectLayer,
--     HasPhysics env,
--     MonadReader env m,
--     MonadResource m,
--     Has w m Node
--   ) =>
--   Proxy broadPhaseLayer ->
--   Proxy objectLayer ->
--   (forall s. Physics.System s broadPhaseLayer objectLayer -> SystemT w m a) ->
--   SystemT w m a
-- withPhysics p1 p2 f = do
--   store :: WorldStore Node <- getStore
--   uniq <- liftIO newUnique
--   let systemId = hashUnique uniq -- TODO: handle collision
--   system <- lift $ Physics.initSystem p1 p2 store.worldTransforms
--   atomicModifyIORef' store.physicsSystems $ \systems -> (IntMap.insert systemId (APhysicsSystem system) systems, ())
--   f system

-- newtype RigidBody = RigidBody
--   { unRigidBody :: Node
--   }

-- instance Component RigidBody where
--   type Storage RigidBody = WorldStore RigidBody

-- type instance Elem (WorldStore RigidBody) = RigidBody

-- instance (MonadIO m) => ExplSet m (WorldStore RigidBody) where
--   explSet store entity body = liftIO $ do
--     hierarchy <- readIORef store.hierarchy
--     let nodeIdx = body.unRigidBody.unNode3D
--     node <- MV.unsafeRead hierarchy nodeIdx
--     MV.unsafeWrite hierarchy nodeIdx $ node {hasBody = True}
--     atomicModifyIORef' store.entityToRigidBody $ \mapping -> (IntMap.insert entity body mapping, ())

-- -- instance (MonadIO m) => ExplGet m (WorldStore LocalTransform) where
-- --   explExists store entity = do
-- --     entityToNode <- readIORef store.entityToNode
-- --     pure $ IntMap.member entity entityToNode
-- --   explGet store entity = liftIO $ do
-- --     entityToNode <- readIORef store.entityToNode
-- --     let nodeIdx = entityToNode IntMap.! entity
-- --     currentLocalTransform <- readIndex store.localTransforms nodeIdx
-- --     pure $ LocalTransform currentLocalTransform

-- data Transform = Transform (Maybe Node) Mat4x4

-- newtype LocalTransform = LocalTransform Mat4x4

-- type instance Elem (WorldStore LocalTransform) = LocalTransform

-- instance Component LocalTransform where
--   type Storage LocalTransform = WorldStore LocalTransform

-- newtype Mesh = Mesh Gpu.Mesh

-- instance Component Mesh where
--   type Storage Mesh = WorldStore Mesh

-- type instance Elem (WorldStore Mesh) = Mesh

-- instance (MonadIO m) => ExplSet m (WorldStore Mesh) where
--   explSet store entity mesh = liftIO $ do
--     atomicModifyIORef' store.entityToMesh $ \mapping -> (IntMap.insert entity mesh mapping, ())

-- instance (MonadIO m) => ExplGet m (WorldStore LocalTransform) where
--   explExists store entity = do
--     entityToNode <- readIORef store.entityToNode
--     pure $ IntMap.member entity entityToNode
--   explGet store entity = liftIO $ do
--     entityToNode <- readIORef store.entityToNode
--     let nodeIdx = entityToNode IntMap.! entity
--     currentLocalTransform <- readIndex store.localTransforms nodeIdx
--     pure $ LocalTransform currentLocalTransform

-- instance (MonadIO m) => ExplSet m (WorldStore LocalTransform) where
--   explSet store entity (LocalTransform transform) = liftIO $ do
--     entityToNode <- readIORef store.entityToNode
--     let nodeIdx = entityToNode IntMap.! entity
--     writeIndex store.localTransforms nodeIdx transform
--     markDirty store $ Node nodeIdx

-- instance (MonadIO m, Has w m Node) => Has w m RigidBody where
--   getStore = (cast :: WorldStore Node -> WorldStore RigidBody) <$> getStore

-- instance (MonadIO m, Has w m Node) => Has w m Mesh where
--   getStore = (cast :: WorldStore Node -> WorldStore Mesh) <$> getStore

-- instance (MonadIO m, Has w m Node) => Has w m Transform where
--   getStore = (cast :: WorldStore Node -> WorldStore Transform) <$> getStore

-- instance Component Transform where
--   type Storage Transform = WorldStore Transform

-- type instance Elem (WorldStore Transform) = Transform

-- instance (MonadIO m) => ExplGet m (WorldStore Node) where
--   explGet nodes entity = liftIO $ do
--     mapping <- readIORef nodes.entityToNode
--     pure $ Node $ mapping IntMap.! entity
--   explExists nodes entity = liftIO $ do
--     mapping <- readIORef nodes.entityToNode
--     pure $ IntMap.member entity mapping

-- instance (MonadIO m) => ExplSet m (WorldStore Transform) where
--   explSet nodes entity (Transform mParent localTransform) = liftIO $ do
--     pushBack nodes.localTransforms localTransform
--     pushBack nodes.worldTransforms identity
--     currentHierarchy <- readIORef nodes.hierarchy
--     let nodeIdx = MV.length currentHierarchy
--     newHierarchy <- MV.unsafeGrow currentHierarchy 1
--     atomicModifyIORef' nodes.entityToNode $ \mapping -> (IntMap.insert entity nodeIdx mapping, ())
--     let nodeID = Node nodeIdx
--     level <-
--       case mParent of
--         Nothing -> pure 0
--         Just (Node parent) -> do
--           parentNode <- MV.unsafeRead newHierarchy parent
--           if parentNode.firstChild == -1
--             then MV.unsafeModify newHierarchy (\n -> n {firstChild = nodeIdx}) parent
--             else do
--               let updateChild childIdx = do
--                     childNode <- MV.unsafeRead newHierarchy childIdx
--                     if childNode.nextSibling == -1
--                       then MV.unsafeWrite newHierarchy childIdx $ childNode {nextSibling = nodeIdx}
--                       else updateChild childNode.nextSibling
--               updateChild parentNode.firstChild
--           pure $ parentNode.level + 1
--     MV.unsafeWrite newHierarchy nodeIdx $ HierarchyNode (maybe (-1) unNode3D mParent) (-1) (-1) level False
--     writeIORef nodes.hierarchy newHierarchy
--     currentMaxLevel <- readIORef nodes.maxNodeLevel
--     if currentMaxLevel >= level
--       then markDirty nodes nodeID
--       else do
--         previousDirtyNodes <- readIORef nodes.dirtyNodes
--         dirtyNodes <- MV.unsafeGrow previousDirtyNodes 1
--         newLevelNodes <- MV.replicateM 1 $ pure nodeIdx
--         MV.unsafeWrite dirtyNodes level (1, newLevelNodes)
--         writeIORef nodes.dirtyNodes dirtyNodes
--         writeIORef nodes.maxNodeLevel $ currentMaxLevel + 1

-- markDirty :: (MonadIO m) => WorldStore c -> Node -> m ()
-- markDirty store (Node nodeIdx) = do
--   hierarchy <- readIORef store.hierarchy
--   dirtyNodes <- readIORef store.dirtyNodes
--   node <- liftIO $ MV.unsafeRead hierarchy nodeIdx
--   (size, levelDirtyNodes) <- liftIO $ MV.unsafeRead dirtyNodes node.level
--   levelDirtyNodes' <-
--     if MV.length levelDirtyNodes == size
--       then liftIO $ MV.unsafeGrow levelDirtyNodes 1
--       else pure levelDirtyNodes
--   liftIO $ MV.unsafeWrite levelDirtyNodes' size nodeIdx
--   liftIO $ MV.unsafeWrite dirtyNodes node.level (size + 1, levelDirtyNodes')
--   -- let markDirtyChild childIdx = do
--   --       childNode <- MV.unsafeRead nodes childIdx
--   --       markDirty world $ NodeID childIdx
--   --       unless (childNode.nextSibling == -1) $ markDirtyChild childNode.nextSibling
--   unless (node.firstChild == -1) $
--     markDirty store (Node node.firstChild)
--   -- markDirtyChild node.firstChild
--   unless (node.nextSibling == -1) $
--     markDirty store (Node node.nextSibling)

-- data WorldStore c = WorldStore
--   { entityToNode :: IORef (IntMap Int),
--     entityToMesh :: IORef (IntMap Mesh),
--     entityToRigidBody :: IORef (IntMap RigidBody),
--     time :: IORef Float,
--     hierarchy :: IORef (MVector RealWorld HierarchyNode),
--     maxNodeLevel :: IORef Int,
--     dirtyNodes :: IORef (MVector RealWorld (Int, MVector RealWorld Int)),
--     worldTransforms :: PinnedVector Mat4x4,
--     localTransforms :: PinnedVector Mat4x4,
--     gpuWorld :: Gpu.World Vertex,
--     physicsSystems :: IORef (IntMap APhysicsSystem)
--   }

-- cast :: WorldStore a -> WorldStore b
-- cast (WorldStore a b c d e f g h i j k) = WorldStore a b c d e f g h i j k

-- instance (MonadIO m, MonadResource m, MonadReader env m, HasGpu env) => ExplInit m (WorldStore Node) where
--   explInit = do
--     entityToNode <- newIORef mempty
--     entityToMesh <- newIORef mempty
--     entityToRigidBody <- newIORef mempty
--     time <- newIORef 0
--     hierarchy <- liftIO $ newIORef =<< MV.new 0
--     worldTransforms <- newVector 0
--     localTransforms <- newVector 0
--     dirtyNodes <- liftIO $ newIORef =<< MV.new 0
--     nodeMaxLevel <- newIORef (-1)
--     gpu <- asks getGpu
--     gpuWorld <- Gpu.initWorld gpu worldTransforms
--     physicsSystems <- newIORef mempty
--     pure
--       WorldStore
--         { entityToNode = entityToNode,
--           entityToMesh = entityToMesh,
--           entityToRigidBody = entityToRigidBody,
--           time = time,
--           hierarchy = hierarchy,
--           maxNodeLevel = nodeMaxLevel,
--           dirtyNodes = dirtyNodes,
--           worldTransforms = worldTransforms,
--           localTransforms = localTransforms,
--           gpuWorld = gpuWorld,
--           physicsSystems = physicsSystems
--         }

-- instance Component Node where
--   type Storage Node = WorldStore Node

-- type instance Elem (WorldStore Node) = Node

-- data NodeEntity = NodeEntity
--   { node :: Node,
--     entity :: Entity
--   }

newtype Node = Node
  { unNode3D :: Int
  }
  deriving stock (Show)

class Transform transform where
  zeroTransform :: transform
  multiplyTransform :: transform -> transform -> transform

instance Transform Mat4x4 where
  zeroTransform = identity
  multiplyTransform = multiply

syncWorldTransforms :: (MonadIO m, Storable transform, Transform transform) => World transform -> m ()
syncWorldTransforms world = do
  hierarchy <- readIORef world.hierarchy
  dirtyNodes <- readIORef world.dirtyNodes
  currentMaxLevel <- readIORef world.maxNodeLevel
  forM_ [1 .. currentMaxLevel] $ \level -> do
    (size, levelDirtyNodes) <- liftIO $ MV.unsafeRead dirtyNodes level
    unless (size == 0) $ do
      forM_ [0 .. size - 1] $ \offset -> do
        nodeIdx <- liftIO $ MV.unsafeRead levelDirtyNodes offset
        node <- liftIO $ MV.unsafeRead hierarchy nodeIdx
        unless node.hasBody $ do
          parentWorldTransform <- readIndex world.worldTransforms node.parent
          localTransform <- readIndex world.localTransforms nodeIdx
          let worldTransform = multiplyTransform parentWorldTransform localTransform
          writeIndex world.worldTransforms nodeIdx worldTransform
      liftIO $ MV.unsafeWrite dirtyNodes level (0, levelDirtyNodes)

class MonadWorld transform m where
  spawnNode :: Maybe Node -> transform -> m Node

spawnNodeImpl :: (MonadIO m, Storable transform, Transform transform) => World transform -> Maybe Node -> transform -> m Node
spawnNodeImpl world mParent localTransform = do
  pushBack world.localTransforms localTransform
  pushBack world.worldTransforms zeroTransform
  currentHierarchy <- readIORef world.hierarchy
  let nodeIdx = MV.length currentHierarchy
  newHierarchy <- liftIO $ MV.unsafeGrow currentHierarchy 1
  let nodeID = Node nodeIdx
  level <-
    case mParent of
      Nothing -> pure 0
      Just (Node parent) -> do
        parentNode <- liftIO $ MV.unsafeRead newHierarchy parent
        if parentNode.firstChild == -1
          then liftIO $ MV.unsafeModify newHierarchy (\n -> n {firstChild = nodeIdx}) parent
          else do
            let updateChild childIdx = do
                  childNode <- liftIO $ MV.unsafeRead newHierarchy childIdx
                  if childNode.nextSibling == -1
                    then liftIO $ MV.unsafeWrite newHierarchy childIdx $ childNode {nextSibling = nodeIdx}
                    else updateChild childNode.nextSibling
            updateChild parentNode.firstChild
        pure $ parentNode.level + 1
  liftIO $ MV.unsafeWrite newHierarchy nodeIdx $ HierarchyNode (maybe (-1) unNode3D mParent) (-1) (-1) level False
  writeIORef world.hierarchy newHierarchy
  currentMaxLevel <- readIORef world.maxNodeLevel
  if currentMaxLevel >= level
    then markDirty world nodeID
    else do
      previousDirtyNodes <- readIORef world.dirtyNodes
      dirtyNodes <- liftIO $ MV.unsafeGrow previousDirtyNodes 1
      newLevelNodes <- liftIO $ MV.replicateM 1 $ pure nodeIdx
      liftIO $ MV.unsafeWrite dirtyNodes level (1, newLevelNodes)
      writeIORef world.dirtyNodes dirtyNodes
      writeIORef world.maxNodeLevel $ currentMaxLevel + 1
  pure nodeID

markDirty :: (MonadIO m) => World transform -> Node -> m ()
markDirty world (Node nodeIdx) = do
  hierarchy <- readIORef world.hierarchy
  dirtyNodes <- readIORef world.dirtyNodes
  node <- liftIO $ MV.unsafeRead hierarchy nodeIdx
  (size, levelDirtyNodes) <- liftIO $ MV.unsafeRead dirtyNodes node.level
  levelDirtyNodes' <-
    if MV.length levelDirtyNodes == size
      then liftIO $ MV.unsafeGrow levelDirtyNodes 1
      else pure levelDirtyNodes
  liftIO $ MV.unsafeWrite levelDirtyNodes' size nodeIdx
  liftIO $ MV.unsafeWrite dirtyNodes node.level (size + 1, levelDirtyNodes')
  -- let markDirtyChild childIdx = do
  --       childNode <- MV.unsafeRead nodes childIdx
  --       markDirty world $ NodeID childIdx
  --       unless (childNode.nextSibling == -1) $ markDirtyChild childNode.nextSibling
  unless (node.firstChild == -1) $
    markDirty world (Node node.firstChild)
  -- markDirtyChild node.firstChild
  unless (node.nextSibling == -1) $
    markDirty world (Node node.nextSibling)
