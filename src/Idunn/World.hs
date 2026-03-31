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

module Idunn.World
  ( World (..),
    HasWorld (..),
    Vertex,
    newWorld,
    spawnNode,
    syncWorldTransforms,
  )
where

import Control.Monad (foldM, forM_, unless, void)
import Data.Vector.Generic.Mutable qualified as MV
import Data.Vector.Mutable (MVector)
import Foreign (Storable)
import GHC.Exts (RealWorld)
import Idunn.Gpu
import Idunn.Gpu.FFI
import Idunn.Linear.Mat
import Idunn.Linear.Vec
import Idunn.Vector
import UnliftIO
import UnliftIO.Resource

class HasWorld env where
  getWorld :: env -> World Vertex

data World vertex = World
  { gpu :: GpuWorld vertex,
    nodes :: IORef (MVector RealWorld Node),
    currentMaxLevel :: IORef Int,
    dirtyNodes :: IORef (MVector RealWorld (Int, MVector RealWorld Int)),
    worldTransforms :: PinnedVector Mat4x4,
    localTransforms :: PinnedVector Mat4x4
  }

newtype Vertex = Vertex Vec3
  deriving newtype (Storable)

newWorld :: (MonadResource m) => Gpu -> m (World Vertex)
newWorld gpu = do
  vertices <- liftIO $ do
    v0 <- newVector 0
    foldM
      pushBack
      v0
      [ Vertex $ mkVec3 (-1) (-1) 1,
        Vertex $ mkVec3 1 (-1) 1,
        Vertex $ mkVec3 1 1 1,
        Vertex $ mkVec3 (-1) 1 1
      ]

  indices <- liftIO $ do
    i0 <- newVector 0
    foldM pushBack i0 [0, 1, 2, 0, 2, 3]

  meshes <- liftIO $ do
    m0 <- newVector 1
    pushBack m0 $ Idunn_gpu_mesh 0 6 0 4

  nodes <- liftIO $ newIORef =<< MV.new 0
  dirtyNodes <- liftIO $ newIORef =<< MV.new 0
  currentMaxLevel <- newIORef 0
  worldTransforms <- liftIO $ newVector 10
  localTransforms <- liftIO $ newVector 10
  gpuWorld <- initGpuWorld gpu vertices indices meshes worldTransforms

  pure $
    World
      { gpu = gpuWorld,
        nodes = nodes,
        currentMaxLevel = currentMaxLevel,
        dirtyNodes = dirtyNodes,
        worldTransforms = worldTransforms,
        localTransforms = localTransforms
      }

newtype NodeID = NodeID Int

data Node = Node
  { parent :: Int,
    firstChild :: Int,
    nextSibling :: Int,
    lastSibling :: Int,
    level :: Int
  }

spawnNode :: NodeID -> Mat4x4 -> World Vertex -> IO NodeID
spawnNode (NodeID parent) localTransform world = do
  void $ pushBack world.localTransforms localTransform
  void $ pushBack world.worldTransforms identity
  previousNodes <- readIORef world.nodes
  let nodeIdx = MV.length previousNodes
  nodes <- MV.unsafeGrow previousNodes 1
  parentNode <- MV.unsafeRead nodes parent
  if parentNode.firstChild == -1
    then MV.unsafeModify nodes (\n -> n {firstChild = nodeIdx}) parent
    else do
      let updateChild childIdx = do
            childNode <- MV.unsafeRead nodes childIdx
            if childNode.nextSibling == -1
              then MV.unsafeWrite nodes childIdx $ childNode {lastSibling = nodeIdx, nextSibling = nodeIdx}
              else do
                MV.unsafeWrite nodes childIdx $ childNode {lastSibling = nodeIdx}
                updateChild childNode.nextSibling
      updateChild parentNode.firstChild
  let level = parentNode.level + 1
  MV.unsafeWrite nodes nodeIdx $
    Node
      { parent = parent,
        firstChild = -1,
        nextSibling = -1,
        lastSibling = -1,
        level = level
      }
  writeIORef world.nodes nodes
  let nodeID = NodeID nodeIdx

  currentMaxLevel <- readIORef world.currentMaxLevel
  if currentMaxLevel > level
    then markDirty world nodeID
    else do
      previousDirtyNodes <- readIORef world.dirtyNodes
      dirtyNodes <- MV.unsafeGrow previousDirtyNodes 1
      newLevelNodes <- MV.replicateM 1 $ pure nodeIdx
      MV.unsafeWrite dirtyNodes level (1, newLevelNodes)
      writeIORef world.dirtyNodes dirtyNodes

  pure nodeID

markDirty :: World Vertex -> NodeID -> IO ()
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
  let markDirtyChild childIdx = do
        childNode <- MV.unsafeRead nodes childIdx
        markDirty world $ NodeID childIdx
        unless (childNode.nextSibling == -1) $ markDirtyChild childNode.nextSibling
  markDirtyChild node.firstChild

syncWorldTransforms :: World Vertex -> IO ()
syncWorldTransforms world = do
  nodes <- readIORef world.nodes
  dirtyNodes <- readIORef world.dirtyNodes
  currentMaxLevel <- readIORef world.currentMaxLevel
  forM_ [0 .. currentMaxLevel] $ \level -> do
    (size, levelDirtyNodes) <- MV.unsafeRead dirtyNodes level
    unless (size == 0) $ do
      forM_ [0 .. size] $ \offset -> do
        nodeIdx <- MV.unsafeRead levelDirtyNodes offset
        node <- MV.unsafeRead nodes nodeIdx
        parentWorldTransform <- readIndex world.worldTransforms node.parent
        localTransform <- readIndex world.localTransforms nodeIdx
        let worldTransform = multiply parentWorldTransform localTransform
        writeIndex world.worldTransforms nodeIdx worldTransform
      MV.unsafeWrite dirtyNodes level (0, levelDirtyNodes)
