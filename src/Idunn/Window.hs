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

module Idunn.Window
  ( Window (dimensions),
    initWindow,
  )
where

import Control.Monad.Trans.Resource
import Data.Text
import Data.Text.Foreign (withCString)
import Data.Void
import Foreign
import Foreign.C.ConstPtr
import Idunn.Platform
import Idunn.Platform.FFI
import UnliftIO

data Window = Window
  { ptr :: Ptr Void,
    dimensions :: IORef (Word32, Word32)
  }

initWindow :: (MonadResource m) => Platform -> Text -> Word32 -> Word32 -> m (Window, Ptr Void)
initWindow platform title width height = snd <$> allocate up down
  where
    up = withCString title $ \c'title ->
      alloca $ \pWindow ->
        alloca $ \pPlatformWindow ->
          alloca $ \pConfig -> do
            let config = Idunn_window_config platform.ptr (ConstPtr c'title) width height pPlatformWindow
            poke pConfig config
            idunn_platform_window_init pConfig pWindow
            dimensions <- newIORef (width, height)
            window <- Window <$> peek pWindow <*> pure dimensions
            (,) <$> pure window <*> peek pPlatformWindow
    down (window, _) = idunn_platform_window_uninit window.ptr
