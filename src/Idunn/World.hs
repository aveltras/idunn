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
{-# OPTIONS_GHC -ddump-splices #-}

module Idunn.World
  ( Node3D,
    Vertex (..),
    rootNode,
    WorldInit (..),
    HasWorldInit (..),
    Transform (..),
    LocalTransform (..),
    syncWorldTransforms,
  )
where

import Apecs hiding (asks)
import Apecs.Core
import Control.Monad (forM_, unless, void)
import Control.Monad.Reader
import Data.IntMap.Strict (IntMap)
import Data.IntMap.Strict qualified as IntMap
import Data.Vector.Generic.Mutable qualified as MV
import Data.Vector.Mutable (MVector)
import Foreign (Storable)
import GHC.Exts (RealWorld)
-- import Idunn.Gpu
-- import Idunn.Gpu.FFI
import Idunn.Linear.Mat
import Idunn.Linear.Vec
-- import Idunn.Platform (Window, render)
import Idunn.Vector
import UnliftIO

data WorldInit = WorldInit
  { worldTransforms :: IORef (PinnedVector Mat4x4)
  }

class HasWorldInit env where
  getWorldInit :: env -> WorldInit

data Node = Node
  { parent :: Int,
    firstChild :: Int,
    nextSibling :: Int,
    level :: Int
  }

data Transform = Transform (Maybe Node3D) Mat4x4

newtype LocalTransform = LocalTransform Mat4x4

type instance Elem (Nodes LocalTransform) = LocalTransform

instance Component LocalTransform where
  type Storage LocalTransform = Nodes LocalTransform

instance (MonadIO m) => ExplGet m (Nodes LocalTransform) where
  explExists store entity = do
    mapping <- readIORef store.mapping
    pure $ IntMap.member entity mapping
  explGet store entity = liftIO $ do
    mapping <- readIORef store.mapping
    let nodeIdx = mapping IntMap.! entity
    currentLocalTransform <- readIndex store.localTransforms nodeIdx
    pure $ LocalTransform currentLocalTransform

instance (MonadIO m) => ExplSet m (Nodes LocalTransform) where
  explSet store entity (LocalTransform transform) = liftIO $ do
    mapping <- readIORef store.mapping
    let nodeIdx = mapping IntMap.! entity
    writeIndex store.localTransforms nodeIdx transform
    markDirty store $ Node3D nodeIdx

instance (MonadIO m, Has w m Node3D) => Has w m LocalTransform where
  getStore = (cast :: Nodes Node3D -> Nodes LocalTransform) <$> getStore

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
      then markDirty nodes nodeID
      else do
        previousDirtyNodes <- readIORef nodes.dirtyNodes
        dirtyNodes <- MV.unsafeGrow previousDirtyNodes 1
        newLevelNodes <- MV.replicateM 1 $ pure nodeIdx
        MV.unsafeWrite dirtyNodes level (1, newLevelNodes)
        writeIORef nodes.dirtyNodes dirtyNodes
        writeIORef nodes.currentMaxLevel $ currentMaxLevel + 1

markDirty :: (MonadIO m, MV.PrimState m ~ RealWorld, MV.PrimMonad m) => Nodes c -> Node3D -> m ()
markDirty store (Node3D nodeIdx) = do
  hierarchy <- readIORef store.hierarchy
  dirtyNodes <- readIORef store.dirtyNodes
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
    markDirty store (Node3D node.firstChild)
  -- markDirtyChild node.firstChild
  unless (node.nextSibling == -1) $
    markDirty store (Node3D node.nextSibling)

newtype WorldTransform = WorldTransform Mat4x4

instance Component WorldTransform where
  type Storage WorldTransform = Global WorldTransform

-- instance (MonadIO m, Has w m Node3D) => Has w m WorldTransform where
--   getStore = (cast :: Nodes Node3D -> Nodes WorldTransform) <$> getStore

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

instance (MonadIO m, HasWorldInit env, MonadReader env m) => ExplInit m (Nodes Node3D) where
  explInit = do
    localTransforms <- newVector 0
    worldInit <- asks getWorldInit
    worldTransforms <- readIORef worldInit.worldTransforms
    liftIO $ do
      hierarchy <- newIORef =<< MV.new 0
      dirtyNodes <- liftIO $ newIORef =<< MV.new 0
      mapping <- newIORef mempty
      currentMaxLevel <- newIORef (-1)
      pure $
        Nodes
          { hierarchy = hierarchy,
            dirtyNodes = dirtyNodes,
            mapping = mapping,
            currentMaxLevel = currentMaxLevel,
            localTransforms = localTransforms,
            worldTransforms = worldTransforms
          }

newtype Vertex = Vertex Vec3
  deriving newtype (Storable)

newtype NodeID = NodeID Int
  deriving newtype (Eq, Ord)

rootNode :: NodeID
rootNode = NodeID (-1)

syncWorldTransforms :: (MonadIO m, Has w m Node3D) => SystemT w m ()
syncWorldTransforms = do
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
