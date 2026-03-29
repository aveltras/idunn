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
    newWorld,
  )
where

import Control.Monad (foldM)
import Foreign
import Idunn.Gpu
import Idunn.Gpu.FFI
import Idunn.Linear.Mat
import Idunn.Linear.Vec
import Idunn.Vector
import UnliftIO
import UnliftIO.Resource

data World vertex = World
  { gpu :: GpuWorld vertex
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

  transforms <- liftIO $ do
    t0 <- newVector 1
    pushBack t0 identity

  gpuWorld <- initGpuWorld gpu vertices indices meshes transforms

  pure $
    World
      { gpu = gpuWorld
      }
