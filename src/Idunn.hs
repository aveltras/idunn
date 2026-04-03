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
{-# LANGUAGE RecursiveDo #-}
{-# LANGUAGE UndecidableInstances #-}

module Idunn
  ( module Idunn,
    module Idunn.Audio,
    module Idunn.Logger,
    module Idunn.Platform,
    module Idunn.Physics,
    module Idunn.Linear.Mat,
    module Idunn.Linear.Vec,
    module Idunn.World,
    module Data.Time,
    module Reflex,
    module Reflex.Network,
    module Reflex.Time,
  )
where

import Control.Monad (forM, forM_, unless, void)
import Control.Monad.Fix (MonadFix, fix)
import Control.Monad.Reader
import Control.Monad.Ref (MonadRef (..), Ref)
import Control.Monad.Trans.Resource (InternalState, MonadResource (..), getInternalState, runInternalState)
import Data.Dependent.Sum
import Data.Functor.Identity (Identity (..))
import Data.Maybe (catMaybes)
import Data.Time
import Idunn.Audio
import Idunn.Gpu
import Idunn.Linear.Mat
import Idunn.Linear.Vec
import Idunn.Logger
import Idunn.Physics
import Idunn.Platform
import Idunn.Resource
import Idunn.World
import Reflex
import Reflex.Host.Class
import Reflex.Network
import Reflex.Time
import UnliftIO
import UnliftIO.Resource

type App t m =
  ( Reflex t,
    ReflexHost t,
    MonadFix m,
    Ref m ~ Ref IO,
    NotReady t m,
    PerformEvent t m,
    Adjustable t m,
    MonadHold t m,
    MonadResource m,
    TriggerEvent t m,
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
    audio :: Audio,
    physics :: Physics,
    state :: InternalState,
    resources :: Resources,
    world :: World Vertex
  }

instance HasAudio (AppEnv t) where
  getAudio = audio

instance HasPhysics (AppEnv t) where
  getPhysics = physics

instance HasPlatform t (AppEnv t) where
  getPlatform = platform

instance HasResources (AppEnv t) where
  getResources = resources

instance HasWorld (AppEnv t) where
  getWorld = world

newtype AppT t m a = AppT
  { unAppT :: ReaderT (AppEnv t) m a
  }
  deriving newtype
    ( Applicative,
      Functor,
      Monad,
      MonadFix,
      MonadIO,
      MonadHold t,
      MonadRef,
      MonadReflexCreateTrigger t,
      MonadReader (AppEnv t),
      MonadSample t,
      NotReady t,
      PerformEvent t,
      PostBuild t,
      TriggerEvent t
    )

instance (Adjustable t m) => Adjustable t (AppT t m) where
  runWithReplace (AppT a) ev = AppT $ runWithReplace a (fmap unAppT ev)
  traverseIntMapWithKeyWithAdjust f dm0 dm' = AppT $ traverseIntMapWithKeyWithAdjust (\k v -> unAppT (f k v)) dm0 dm'
  traverseDMapWithKeyWithAdjust f dm0 dm' = AppT $ traverseDMapWithKeyWithAdjust (\k v -> unAppT (f k v)) dm0 dm'
  traverseDMapWithKeyWithAdjustWithMove f dm0 dm' = AppT $ traverseDMapWithKeyWithAdjustWithMove (\k v -> unAppT (f k v)) dm0 dm'

instance (MonadIO m) => MonadResource (AppT t m) where
  liftResourceT m = do
    env <- AppT ask
    liftIO $ runInternalState m env.state

runAppT :: AppEnv t -> AppT t m a -> m a
runAppT env (AppT app) = runReaderT app env

type AppM =
  AppT
    (SpiderTimeline Global)
    ( TriggerEventT
        (SpiderTimeline Global)
        ( PostBuildT
            (SpiderTimeline Global)
            ( PerformEventT
                (SpiderTimeline Global)
                (SpiderHost Global)
            )
        )
    )

run :: screen -> (screen -> (World Vertex -> AppM (Event (SpiderTimeline Global) screen))) -> IO ()
run startingScreen screenMapping = runResourceT $ do
  platform <- initPlatform
  gpu <- initGpu "Idunn" 1
  audio <- initAudio
  physics <- initPhysics
  window <- initWindow platform gpu "Idunn" 800 600

  asyncEvents <- newChan
  internalState <- getInternalState
  resources <- initResources

  world <- newWorld gpu
  worldRef <- newIORef world

  let appEnv =
        AppEnv
          { platform = platform,
            gpu = gpu,
            audio = audio,
            physics = physics,
            state = internalState,
            resources = resources,
            world = world
          }

  liftIO $ runSpiderHost $ do
    (ePostBuild, trPostBuild) <- newEventWithTriggerRef
    (_, FireCommand fire) <- hostPerformEventT $ flip runPostBuildT ePostBuild $ flip runTriggerEventT asyncEvents $ runAppT appEnv $ do
      rec let eSwitch = switchPromptlyDyn dNextLevel
          dNextLevel <- networkHold (screenMapping startingScreen world) $ ffor eSwitch $ \nextLevel -> do
            flip runInternalState internalState $ cleanupResources resources
            levelWorld <- newWorld gpu
            oldWorld <- atomicModifyIORef' worldRef $ \currentWorld -> (levelWorld, currentWorld)
            screenMapping nextLevel world
      pure ()

    addEvent platform.eventsRef trPostBuild ()

    asyncTrigger <- liftIO $ async $ fix $ \loop -> do
      triggerRefs <- readChan asyncEvents
      mes <- liftIO $ forM triggerRefs $ \(EventTriggerRef er :=> TriggerInvocation a _) -> do
        me <- readIORef er
        pure $ (\e -> e :=> Identity a) <$> me
      void $ runSpiderHost $ fire (catMaybes mes) $ pure ()
      forM_ triggerRefs $ \(_ :=> TriggerInvocation _ cb) -> cb
      loop

    fix $ \f -> do
      shouldExit <- tick platform
      unless shouldExit $ do
        events <- readIORef platform.eventsRef
        _ <- fire events $ pure ()
        currentWorld <- readIORef worldRef
        render window currentWorld.gpu
        writeIORef platform.eventsRef mempty
        f

    cancel asyncTrigger
  where
    addEvent :: (MonadRef m, MonadIO m) => IORef [DSum tag Identity] -> Ref m (Maybe (tag a)) -> a -> m ()
    addEvent eventsRef trRef val =
      readRef trRef >>= \case
        Nothing -> pure ()
        Just tr -> modifyIORef' eventsRef $ (:) (tr :=> Identity val)
