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
  ( WorldTransform (..),
    RelativeTransform (..),
    WorldTransformUpdated,
    propagateWorldTransformUpdates,
  )
where

import Apecs
import Apecs.Core
import Apecs.Experimental.Children
import Apecs.Experimental.Reactive
import Control.Monad (forM_, when)
import Control.Monad.Reader
import Foreign (Storable)
import Idunn.Linear.Mat
import Idunn.Vector
import UnliftIO

class Transform transform where
  zeroTransform :: transform
  multiplyTransform :: transform -> transform -> transform

instance Transform Mat4x4 where
  zeroTransform = identity
  multiplyTransform = multiply

newtype WorldTransform = WorldTransform Mat4x4
  deriving newtype (Storable)

instance Component WorldTransform where
  type Storage WorldTransform = SparseVector WorldTransform

data WorldTransformUpdated = WorldTransformUpdated
  deriving stock (Show)

instance Component WorldTransformUpdated where
  type Storage WorldTransformUpdated = Map WorldTransformUpdated

newtype RelativeTransform = RelativeTransform Mat4x4
  deriving newtype (Storable)

data TransformUpdater = TransformUpdater

instance Component RelativeTransform where
  type Storage RelativeTransform = Reactive TransformUpdater (SparseVector RelativeTransform)

type instance Elem TransformUpdater = RelativeTransform

instance (MonadIO m) => Reacts m TransformUpdater where
  {-# INLINE rempty #-}
  rempty = pure TransformUpdater
  {-# INLINE react #-}
  react _ Nothing Nothing _ = pure ()
  react (Entity entity) oldLocalTransformM newLocalTransformM _ = do
    pure ()

propagateWorldTransformUpdates ::
  ( MonadIO m,
    Has w m WorldTransformUpdated,
    Has w m WorldTransform,
    Has w m (ChildList RelativeTransform),
    Has w m (Child RelativeTransform)
  ) =>
  SystemT w m ()
propagateWorldTransformUpdates = do
  hasUpdatedChildrenRef <- newIORef False
  cmapM $ \(WorldTransformUpdated, WorldTransform worldTransform, ChildList children :: ChildList RelativeTransform) -> do
    writeIORef hasUpdatedChildrenRef True
    forM_ children $ \child -> do
      ChildValue (RelativeTransform childTransform) <- get child
      child $= (WorldTransformUpdated, WorldTransform (multiplyTransform worldTransform childTransform))
    pure $ Not @WorldTransformUpdated
  hasUpdatedChildren <- readIORef hasUpdatedChildrenRef
  when hasUpdatedChildren propagateWorldTransformUpdates
