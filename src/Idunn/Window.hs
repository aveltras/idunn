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

module Idunn.Window where

import Control.Monad.IO.Class
import Control.Monad.Trans.Resource
import Data.Text
import Data.Text.Foreign (withCString)
import Data.Void
import Foreign
import Foreign.C.ConstPtr
import Idunn.Gpu
import Idunn.Platform
import Idunn.Platform.FFI

data Window = Window
  { ptr :: Ptr Void
  }

initWindow :: (MonadResource m) => Platform -> Gpu -> Text -> Word32 -> Word32 -> m Window
initWindow platform gpu title width height = snd <$> allocate up down
  where
    up = withCString title $ \c'title ->
      alloca $ \pWindow ->
        alloca $ \pConfig -> do
          let config = Idunn_window_config platform.ptr gpu.ptr (ConstPtr c'title) width height
          poke pConfig config
          idunn_platform_window_init pConfig pWindow
          Window <$> peek pWindow
    down window = idunn_platform_window_uninit window.ptr

render :: (MonadIO m) => Window -> Graphics vertex -> m ()
render window graphics = error "todo" -- liftIO $ idunn_platform_window_render window.ptr graphics.handle
