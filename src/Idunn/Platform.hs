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

module Idunn.Platform
  ( initPlatform,
  )
where

import Data.Void
import Foreign
import Idunn.Platform.FFI
import UnliftIO.Resource

data Platform = Platform
  { ptr :: Ptr Void
  }

initPlatform :: (MonadResource m) => m Platform
initPlatform = snd <$> allocate up down
  where
    up = alloca $ \pPlatform -> do
      idunn_platform_init pPlatform
      Platform <$> peek pPlatform
    down platform = idunn_platform_uninit platform.ptr
