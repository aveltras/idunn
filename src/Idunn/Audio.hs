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

module Idunn.Audio
  ( Audio,
    HasAudio (..),
    initAudio,
    playSound,
  )
where

import Control.Monad.Reader
import Data.Void (Void)
import Foreign
import Foreign.C
import Foreign.C.ConstPtr
import Idunn.Audio.FFI
import UnliftIO.Resource

data Audio = Audio
  { ptr :: Ptr Void
  }

class HasAudio env where
  getAudio :: env -> Audio

initAudio :: (MonadResource m) => m Audio
initAudio = snd <$> allocate up down
  where
    up =
      alloca $ \pAudio -> do
        idunn_audio_init pAudio
        Audio <$> peek pAudio
    down audio = idunn_audio_uninit audio.ptr

playSound :: (HasAudio env, MonadReader env m, MonadIO m) => FilePath -> m ()
playSound soundPath = do
  audio <- asks getAudio
  liftIO $ withCString soundPath $ \c'soundPath ->
    idunn_audio_sound_play audio.ptr $ ConstPtr c'soundPath
