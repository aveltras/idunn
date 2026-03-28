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

module Idunn.Physics
  ( Physics,
    HasPhysics (..),
    initPhysics,
  )
where

import Data.Void (Void)
import Foreign
import Idunn.Physics.FFI
import UnliftIO.Resource

data Physics = Physics
  { ptr :: Ptr Void
  }

class HasPhysics env where
  getPhysics :: env -> Physics

initPhysics :: (MonadResource m) => m Physics
initPhysics = snd <$> allocate up down
  where
    up =
      alloca $ \pPhysics -> do
        idunn_physics_init pPhysics
        Physics <$> peek pPhysics
    down physics = idunn_physics_uninit physics.ptr
