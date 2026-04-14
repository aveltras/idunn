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
    MonadAudio (..),
    initAudio,
    playSound,
  )
where

import Data.Void (Void)
import Foreign
import Foreign.C
import Foreign.C.ConstPtr
import Idunn.Audio.FFI
import UnliftIO.Resource

class MonadAudio m where
  playAudio :: FilePath -> m ()

data Audio = Audio
  { ptr :: Ptr Void
  }

initAudio :: (MonadResource m) => m Audio
initAudio = snd <$> allocate up down
  where
    up =
      alloca $ \pAudio -> do
        idunn_audio_init pAudio
        Audio <$> peek pAudio
    down audio = idunn_audio_uninit audio.ptr

playSound :: Audio -> FilePath -> IO ()
playSound audio soundPath = do
  withCString soundPath $ \c'soundPath ->
    idunn_audio_sound_play audio.ptr $ ConstPtr c'soundPath
