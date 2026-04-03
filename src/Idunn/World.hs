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
{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE UndecidableInstances #-}

module Idunn.World
  ( World (..),
    HasWorld (..),
    Vertex,
    debug,
    newWorld,
    rootNode,
    spawnNode,
    setNodeMesh,
    syncWorldTransforms,
  )
where

import Apecs
import Apecs.Core
import Control.Monad (forM_, unless, void)
import Data.IntMap.Strict (IntMap)
import Data.IntMap.Strict qualified as IntMap
import Data.Maybe (fromMaybe)
import Data.Vector.Generic.Mutable qualified as MV
import Data.Vector.Mutable (MVector)
import Foreign (Storable)
import GHC.Exts (RealWorld)
import Idunn.Gpu
import Idunn.Linear.Mat
import Idunn.Linear.Vec
import Idunn.Logger
import Idunn.Vector
import UnliftIO
import UnliftIO.Resource

data Node = Node
  { parent :: Int,
    firstChild :: Int,
    nextSibling :: Int,
    level :: Int
  }

data Transform = Transform (Maybe Node3D) Mat4x4

instance Component Transform where
  type Storage Transform = Nodes Transform

instance (MonadIO m, Has w m Node3D) => Has w m Transform where
  getStore = (cast :: Nodes Node3D -> Nodes Transform) <$> getStore

type instance Elem (Nodes Transform) = Transform

instance (MonadIO m) => ExplGet m (Nodes Node3D) where
  explGet nodes entity = liftIO $ do
    mapping <- readIORef nodes.mapping
    pure $ Node3D $ mapping IntMap.! entity
  explExists nodes entity = liftIO $ do
    mapping <- readIORef nodes.mapping
    pure $ IntMap.member entity mapping

instance (MonadIO m) => ExplSet m (Nodes Transform) where
  explSet nodes entity (Transform mParent localTransform) = liftIO $ do
    pushBack nodes.localTransforms localTransform
    pushBack nodes.worldTransforms identity
    currentHierarchy <- readIORef nodes.hierarchy
    let nodeIdx = MV.length currentHierarchy
    newHierarchy <- MV.unsafeGrow currentHierarchy 1
    atomicModifyIORef' nodes.mapping $ \mapping -> (IntMap.insert entity nodeIdx mapping, ())
    let nodeID = Node3D nodeIdx
    level <-
      case mParent of
        Nothing -> pure 0
        Just (Node3D parent) -> do
          parentNode <- MV.unsafeRead newHierarchy parent
          if parentNode.firstChild == -1
            then MV.unsafeModify newHierarchy (\n -> n {firstChild = nodeIdx}) parent
            else do
              let updateChild childIdx = do
                    childNode <- MV.unsafeRead newHierarchy childIdx
                    if childNode.nextSibling == -1
                      then MV.unsafeWrite newHierarchy childIdx $ childNode {nextSibling = nodeIdx}
                      else updateChild childNode.nextSibling
              updateChild parentNode.firstChild
          pure $ parentNode.level + 1
    MV.unsafeWrite newHierarchy nodeIdx $ Node (maybe (-1) unNode3D mParent) (-1) (-1) level
    writeIORef nodes.hierarchy newHierarchy
    currentMaxLevel <- readIORef nodes.currentMaxLevel
    if currentMaxLevel >= level
      then markDirty nodeID
      else do
        previousDirtyNodes <- readIORef nodes.dirtyNodes
        dirtyNodes <- MV.unsafeGrow previousDirtyNodes 1
        newLevelNodes <- MV.replicateM 1 $ pure nodeIdx
        MV.unsafeWrite dirtyNodes level (1, newLevelNodes)
        writeIORef nodes.dirtyNodes dirtyNodes
        writeIORef nodes.currentMaxLevel $ currentMaxLevel + 1
    where
      markDirty (Node3D nodeIdx) = do
        hierarchy <- readIORef nodes.hierarchy
        dirtyNodes <- readIORef nodes.dirtyNodes
        node <- MV.unsafeRead hierarchy nodeIdx
        (size, levelDirtyNodes) <- MV.unsafeRead dirtyNodes node.level
        levelDirtyNodes' <-
          if MV.length levelDirtyNodes == size
            then MV.unsafeGrow levelDirtyNodes 1
            else pure levelDirtyNodes
        MV.unsafeWrite levelDirtyNodes' size nodeIdx
        MV.unsafeWrite dirtyNodes node.level (size + 1, levelDirtyNodes')
        -- let markDirtyChild childIdx = do
        --       childNode <- MV.unsafeRead nodes childIdx
        --       markDirty world $ NodeID childIdx
        --       unless (childNode.nextSibling == -1) $ markDirtyChild childNode.nextSibling
        unless (node.firstChild == -1) $
          markDirty (Node3D node.firstChild)
        -- markDirtyChild node.firstChild
        unless (node.nextSibling == -1) $
          markDirty (Node3D node.nextSibling)

newtype WorldTransform = WorldTransform Mat4x4

instance Component WorldTransform where
  type Storage WorldTransform = Nodes WorldTransform

instance (MonadIO m, Has w m Node3D) => Has w m WorldTransform where
  getStore = (cast :: Nodes Node3D -> Nodes WorldTransform) <$> getStore

type instance Elem (Nodes WorldTransform) = WorldTransform

data Nodes c = Nodes
  { hierarchy :: IORef (MVector RealWorld Node),
    dirtyNodes :: IORef (MVector RealWorld (Int, MVector RealWorld Int)),
    mapping :: IORef (IntMap Int),
    currentMaxLevel :: IORef Int,
    localTransforms :: PinnedVector Mat4x4,
    worldTransforms :: PinnedVector Mat4x4
  }

cast :: Nodes a -> Nodes b
cast (Nodes a b c d e f) = Nodes a b c d e f

newtype Node3D = Node3D
  { unNode3D :: Int
  }

instance Component Node3D where
  type Storage Node3D = Nodes Node3D

type instance Elem (Nodes Node3D) = Node3D

instance (MonadIO m) => ExplInit m (Nodes Node3D) where
  explInit = liftIO $ do
    hierarchy <- newIORef =<< MV.new 0
    dirtyNodes <- liftIO $ newIORef =<< MV.new 0
    mapping <- newIORef mempty
    currentMaxLevel <- newIORef (-1)
    localTransforms <- newVector 0
    worldTransforms <- newVector 0
    pure $ Nodes hierarchy dirtyNodes mapping currentMaxLevel localTransforms worldTransforms

class HasWorld env where
  getWorld :: env -> World Vertex

data World vertex = World
  { gpu :: GpuWorld vertex,
    nodes :: IORef (MVector RealWorld Node),
    currentMaxLevel :: IORef Int,
    dirtyNodes :: IORef (MVector RealWorld (Int, MVector RealWorld Int)),
    nodeMeshes :: IORef (IntMap Mesh),
    worldTransforms :: PinnedVector Mat4x4,
    localTransforms :: PinnedVector Mat4x4
  }

newtype Vertex = Vertex Vec3
  deriving newtype (Storable)

newWorld :: (MonadResource m) => Gpu -> m (World Vertex)
newWorld gpu = do
  nodes <- liftIO $ newIORef =<< MV.new 0
  dirtyNodes <- liftIO $ newIORef =<< MV.new 0
  currentMaxLevel <- newIORef (-1)
  worldTransforms <- liftIO $ newVector 0
  localTransforms <- liftIO $ newVector 0
  meshes <- liftIO $ newVector 0
  vertices <- liftIO $ newVector 0
  indices <- liftIO $ newVector 0
  gpuWorld <- initGpuWorld gpu vertices indices meshes worldTransforms
  nodeMeshes <- newIORef mempty
  pure $
    World
      { gpu = gpuWorld,
        nodes = nodes,
        currentMaxLevel = currentMaxLevel,
        dirtyNodes = dirtyNodes,
        nodeMeshes = nodeMeshes,
        worldTransforms = worldTransforms,
        localTransforms = localTransforms
      }

newtype NodeID = NodeID Int
  deriving newtype (Eq, Ord)

rootNode :: NodeID
rootNode = NodeID (-1)

setNodeMesh :: (MonadIO m) => World Vertex -> NodeID -> m ()
setNodeMesh world (NodeID nodeIdx) = do
  mesh <- spawnMesh world.gpu vertices indices
  atomicModifyIORef' world.nodeMeshes $ \mapping -> (IntMap.insert nodeIdx mesh mapping, ())
  where
    indices = [0, 1, 2, 0, 2, 3]
    vertices =
      [ Vertex $ mkVec3 (-1) (-1) 1,
        Vertex $ mkVec3 1 (-1) 1,
        Vertex $ mkVec3 1 1 1,
        Vertex $ mkVec3 (-1) 1 1
      ]

spawnNode :: (MonadIO m, MV.PrimState m ~ RealWorld, MV.PrimMonad m) => NodeID -> Mat4x4 -> World Vertex -> m NodeID
spawnNode (NodeID parent) localTransform world = do
  liftIO $ pushBack world.localTransforms localTransform
  liftIO $ pushBack world.worldTransforms identity
  previousNodes <- readIORef world.nodes
  let nodeIdx = MV.length previousNodes
  nodes <- MV.unsafeGrow previousNodes 1
  level <-
    if parent == -1
      then pure 0
      else do
        parentNode <- MV.unsafeRead nodes parent
        if parentNode.firstChild == -1
          then MV.unsafeModify nodes (\n -> n {firstChild = nodeIdx}) parent
          else do
            let updateChild childIdx = do
                  childNode <- MV.unsafeRead nodes childIdx
                  if childNode.nextSibling == -1
                    then MV.unsafeWrite nodes childIdx $ childNode {nextSibling = nodeIdx}
                    else updateChild childNode.nextSibling
            updateChild parentNode.firstChild
        pure $ parentNode.level + 1
  MV.unsafeWrite nodes nodeIdx $
    Node
      { parent = parent,
        firstChild = -1,
        nextSibling = -1,
        level = level
      }
  writeIORef world.nodes nodes
  let nodeID = NodeID nodeIdx
  currentMaxLevel <- readIORef world.currentMaxLevel
  if currentMaxLevel >= level
    then markDirty world nodeID
    else do
      previousDirtyNodes <- readIORef world.dirtyNodes
      dirtyNodes <- MV.unsafeGrow previousDirtyNodes 1
      newLevelNodes <- MV.replicateM 1 $ pure nodeIdx
      MV.unsafeWrite dirtyNodes level (1, newLevelNodes)
      writeIORef world.dirtyNodes dirtyNodes
      writeIORef world.currentMaxLevel $ currentMaxLevel + 1

  pure nodeID

markDirty :: (MonadIO m, MV.PrimState m ~ RealWorld, MV.PrimMonad m) => World Vertex -> NodeID -> m ()
markDirty world (NodeID nodeIdx) = do
  nodes <- readIORef world.nodes
  dirtyNodes <- readIORef world.dirtyNodes
  node <- MV.unsafeRead nodes nodeIdx
  (size, levelDirtyNodes) <- MV.unsafeRead dirtyNodes node.level
  levelDirtyNodes' <-
    if MV.length levelDirtyNodes == size
      then MV.unsafeGrow levelDirtyNodes 1
      else pure levelDirtyNodes
  MV.unsafeWrite levelDirtyNodes' size nodeIdx
  MV.unsafeWrite dirtyNodes node.level (size + 1, levelDirtyNodes')
  -- let markDirtyChild childIdx = do
  --       childNode <- MV.unsafeRead nodes childIdx
  --       markDirty world $ NodeID childIdx
  --       unless (childNode.nextSibling == -1) $ markDirtyChild childNode.nextSibling
  unless (node.firstChild == -1) $
    markDirty world (NodeID node.firstChild)
  -- markDirtyChild node.firstChild
  unless (node.nextSibling == -1) $
    markDirty world (NodeID node.nextSibling)

syncWorldTransforms :: (MonadIO m) => World Vertex -> m ()
syncWorldTransforms world = liftIO $ do
  nodes <- readIORef world.nodes
  dirtyNodes <- readIORef world.dirtyNodes
  currentMaxLevel <- readIORef world.currentMaxLevel
  forM_ [1 .. currentMaxLevel] $ \level -> do
    (size, levelDirtyNodes) <- MV.unsafeRead dirtyNodes level
    unless (size == 0) $ do
      forM_ [0 .. size - 1] $ \offset -> do
        nodeIdx <- MV.unsafeRead levelDirtyNodes offset
        node <- MV.unsafeRead nodes nodeIdx
        parentWorldTransform <- readIndex world.worldTransforms node.parent
        localTransform <- readIndex world.localTransforms nodeIdx
        let worldTransform = multiply parentWorldTransform localTransform
        writeIndex world.worldTransforms nodeIdx worldTransform
      MV.unsafeWrite dirtyNodes level (0, levelDirtyNodes)

makeWorld "Toc" [''Node3D]

debug :: IO ()
debug = do
  world <- initToc
  runSystem game world

game :: System Toc ()
game = do
  root <- newEntity (Transform Nothing identity)
  rootNode3D :: Node3D <- get root
  parent <- newEntity (Transform (Just rootNode3D) identity)
  parentNode3D :: Node3D <- get parent
  child <- newEntity (Transform (Just parentNode3D) identity)
  childNode3D :: Node3D <- get child
  liftIO $ print @String "debugOK"

syncWorldTransforms' :: System Toc ()
syncWorldTransforms' = do
  nodes :: Nodes Transform <- getStore
  hierarchy <- readIORef nodes.hierarchy
  dirtyNodes <- readIORef nodes.dirtyNodes
  currentMaxLevel <- readIORef nodes.currentMaxLevel
  forM_ [1 .. currentMaxLevel] $ \level -> liftIO $ do
    (size, levelDirtyNodes) <- MV.unsafeRead dirtyNodes level
    unless (size == 0) $ do
      forM_ [0 .. size - 1] $ \offset -> do
        nodeIdx <- MV.unsafeRead levelDirtyNodes offset
        node <- MV.unsafeRead hierarchy nodeIdx
        parentWorldTransform <- readIndex nodes.worldTransforms node.parent
        localTransform <- readIndex nodes.localTransforms nodeIdx
        let worldTransform = multiply parentWorldTransform localTransform
        writeIndex nodes.worldTransforms nodeIdx worldTransform
      MV.unsafeWrite dirtyNodes level (0, levelDirtyNodes)
