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

module Idunn
  ( module Idunn,
    module Idunn.Audio,
    module Idunn.Logger,
    module Idunn.Platform,
    module Reflex,
  )
where

import Control.Monad (unless)
import Control.Monad.Fix (fix)
import Control.Monad.Reader
import Control.Monad.Ref (MonadRef (..), Ref)
import Data.Dependent.Sum
import Data.Functor.Identity (Identity (..))
import Idunn.Audio
import Idunn.Gpu
import Idunn.Logger
import Idunn.Platform
import Reflex
import Reflex.Host.Class
import UnliftIO
import UnliftIO.Resource

type App t m =
  ( Reflex t,
    ReflexHost t,
    MonadRef m,
    Ref m ~ Ref IO,
    PerformEvent t m,
    MonadIO (Performable m),
    MonadReader (AppEnv t) (Performable m),
    MonadIO (HostFrame t),
    PostBuild t m,
    MonadReader (AppEnv t) m,
    MonadReflexCreateTrigger t m
  )

data AppEnv t = AppEnv
  { platform :: Platform t,
    gpu :: Gpu,
    audio :: Audio
  }

instance HasAudio (AppEnv t) where
  getAudio = audio

instance HasPlatform t (AppEnv t) where
  getPlatform = platform

type AppM =
  ReaderT
    (AppEnv (SpiderTimeline Global))
    ( PostBuildT
        (SpiderTimeline Global)
        ( PerformEventT
            (SpiderTimeline Global)
            (SpiderHost Global)
        )
    )

run :: AppM () -> IO ()
run app = runResourceT $ do
  platform <- initPlatform
  gpu <- initGpu "Idunn" 1
  audio <- initAudio
  window <- initWindow platform gpu "Idunn" 800 600
  liftIO $ runSpiderHost $ do
    (ePostBuild, trPostBuild) <- newEventWithTriggerRef
    let appEnv :: AppEnv (SpiderTimeline Global) = AppEnv platform gpu audio
    (_, FireCommand fire) <- hostPerformEventT $ flip runPostBuildT ePostBuild $ runReaderT app appEnv
    addEvent platform.eventsRef trPostBuild ()
    fix $ \f -> do
      shouldExit <- tick platform
      unless shouldExit $ do
        events <- readIORef platform.eventsRef
        _ <- fire events $ pure ()
        render window
        writeIORef platform.eventsRef mempty
        f
  where
    addEvent :: (MonadRef m, MonadIO m) => IORef [DSum tag Identity] -> Ref m (Maybe (tag a)) -> a -> m ()
    addEvent eventsRef trRef val =
      readRef trRef >>= \case
        Nothing -> pure ()
        Just tr -> modifyIORef' eventsRef $ (:) (tr :=> Identity val)
