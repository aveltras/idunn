{-# LANGUAGE FunctionalDependencies #-}
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
{-# LANGUAGE PatternSynonyms #-}
{-# LANGUAGE RecursiveDo #-}
{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE UndecidableInstances #-}

module Idunn
  ( -- module Idunn.Audio,
    -- module Idunn.Gpu,
    -- module Idunn.Input,
    module Idunn.Logger,
    -- module Idunn.Platform,
    module Idunn.Linear.Mat,
    module Idunn.Input,
    module Idunn.Linear.Vec,
    module Idunn.World,
    -- module Data.Time,
    module Reflex,
    module Reflex.Network,
    -- module Reflex.Time,
    IsPhysicsSystem (..),
    MonadECS (..),
    -- Transform (..),
    -- pattern Static,
    -- pattern Dynamic,
    -- pattern Kinematic,
    -- Shape (defaultSettings),
    -- ShapeSettings (..),
    module Apecs,
    Mesh (..),
    -- MonadWorld (..),
    -- spawnNode,
    RequestExit (..),
    MonadAudio (..),
    -- MonadInput (..),
    -- Vertex,
    App,
    run,
    HasWorld (..),
    mkAppSettings,
    setAppName,
    setAppVersion,
    -- DeltaTime (..),
  )
where

import Apecs hiding (Map, ask, asks)
import Apecs.Experimental.Children
import Control.Concurrent.Async (cancelMany)
import Control.Monad (forM, forM_, unless, void, when)
import Control.Monad.Fix (MonadFix, fix)
import Control.Monad.Reader
import Control.Monad.Ref (MonadRef (..))
import Control.Monad.Trans.Resource (getInternalState, runInternalState)
import Data.Coerce (coerce)
import Data.Dependent.Map qualified as DMap
import Data.Dependent.Sum
import Data.Functor.Identity (Identity (..))
import Data.IntMap.Strict (IntMap)
import Data.IntMap.Strict qualified as IntMap
import Data.Kind (Type)
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Maybe (catMaybes)
import Data.Text (Text)
import Data.Unique
import Foreign hiding (void)
import Idunn.Audio
import Idunn.Gpu
import Idunn.Input
import Idunn.Linear.Mat
import Idunn.Linear.Vec
import Idunn.Logger
import Idunn.Physics hiding (System, update)
import Idunn.Platform
import Idunn.Window
import Idunn.World
import Reflex hiding (Global)
import Reflex qualified
import Reflex.Host.Class
import Reflex.Network
import Reflex.Spider.Internal (RootTrigger, SpiderHost (..), SpiderHostFrame)
import System.Clock
import UnliftIO
import UnliftIO.Resource

data GameEvents' f = GameEvents
  { postBuild :: f (),
    deltaTime :: f Float
  }

type GameEvents t = GameEvents' (Event t)

newtype Trigger t m a = Trigger {unTrigger :: Ref m (Maybe (EventTrigger t a))}

type GameTriggers t m = GameEvents' (Trigger t m)

type GameM world vertex t m = GameT world vertex t (TriggerEventT t (PostBuildT t (PerformEventT t m)))

data GameEnv world vertex t = GameEnv
  { platform :: Platform,
    gpu :: Gpu,
    graphics :: Graphics vertex,
    world :: world,
    events :: GameEvents t,
    input :: EventSelector t Input,
    exitRequested :: IORef Bool
  }

instance HasWorld (GameEnv world vertex t) world where
  getWorld = (.world)

instance (Monad m) => MonadGpu (GameT world vertex t m) where
  getGpuM = GameT $ asks (.gpu)

instance (Storable vertex, Typeable vertex, Monad m) => MonadGraphics vertex (GameT world vertex t m) where
  getGraphicsM = GameT $ asks (.graphics)

class MonadECS w m | m -> w where
  runECS :: SystemT w m a -> m a

newtype GameT world vertex (t :: Type) m a = GameT
  { unGameT :: ReaderT (GameEnv world vertex t) m a
  }
  deriving newtype
    ( Applicative,
      Functor,
      Monad,
      MonadFix,
      MonadIO,
      MonadHold t,
      MonadReflexCreateTrigger t,
      MonadReader (GameEnv world vertex t),
      MonadSample t,
      MonadTrans,
      NotReady t,
      PostBuild t,
      TriggerEvent t
    )

instance (Monad m, Reflex t, PerformEvent t m) => PerformEvent t (GameT world vertex t m) where
  type Performable (GameT world vertex t m) = GameT world vertex t (Performable m)

  {-# INLINE performEvent_ #-}
  performEvent_ event = GameT $ do
    env <- ask
    lift $ performEvent_ $ fmapCheap (\act -> runReaderT (coerce act) env) event

  {-# INLINE performEvent #-}
  performEvent event = GameT $ do
    env <- ask
    lift $ performEvent $ fmapCheap (\act -> runReaderT (coerce act) env) event

instance (Monad m) => MonadECS w (GameT w vertex t m) where
  runECS f = do
    world <- asks (.world)
    runSystem f world

instance (Adjustable t m) => Adjustable t (GameT world vertex t m) where
  runWithReplace (GameT a) ev = GameT $ runWithReplace a (fmap unGameT ev)
  traverseIntMapWithKeyWithAdjust f dm0 dm' = GameT $ traverseIntMapWithKeyWithAdjust (\k v -> unGameT (f k v)) dm0 dm'
  traverseDMapWithKeyWithAdjust f dm0 dm' = GameT $ traverseDMapWithKeyWithAdjust (\k v -> unGameT (f k v)) dm0 dm'
  traverseDMapWithKeyWithAdjustWithMove f dm0 dm' = GameT $ traverseDMapWithKeyWithAdjustWithMove (\k v -> unGameT (f k v)) dm0 dm'

runGameT :: GameT world vertex t m a -> GameEnv world vertex t -> m a
runGameT (GameT game) gameEnv = runReaderT game gameEnv

class RequestExit m where
  requestExit :: m ()

-- instance (MonadIO m) => MonadAudio (ReaderT (AppEnv world vertex env t) m) where
--   playAudio soundPath = do
--     audioBackend <- asks audio
--     liftIO $ playSound audioBackend soundPath

instance (MonadIO m) => RequestExit (GameT world vertex t m) where
  requestExit = do
    exitRequestedRef <- asks (.exitRequested)
    writeIORef exitRequestedRef True

instance (Monad m) => MonadInput t (GameT world vertex t m) where
  onScancode scancode = do
    input <- asks (.input)
    pure $ select input $ InputScancode scancode
  onKey scancode = do
    input <- asks (.input)
    pure $ select input $ InputKey scancode

setupInputSelector :: (MonadReflexCreateTrigger t m) => Platform -> IORef (DMap.DMap Input (EventTrigger t)) -> m (EventSelector t Input)
setupInputSelector platform triggerMapRef = do
  newFanEventWithTrigger $ \key trigger ->
    case key of
      InputScancode x -> do
        print $ show ("subscribe to scancode" :: Text, x)
        subscribeToScancode platform x
        atomicModifyIORef' triggerMapRef $ \m -> (DMap.insert (InputScancode x) trigger m, ())
        pure $ do
          print $ show ("unsubscribe from scancode" :: Text, x)
          unsubscribeFromScancode platform x
          atomicModifyIORef' triggerMapRef $ \m -> (DMap.delete (InputScancode x) m, ())
      InputKey x -> do
        subscribeToKey platform x
        atomicModifyIORef' triggerMapRef $ \m -> (DMap.insert (InputKey x) trigger m, ())
        pure $ do
          unsubscribeFromKey platform x
          atomicModifyIORef' triggerMapRef $ \m -> (DMap.delete (InputKey x) m, ())

-- class (Reflex t, Monad m) => DeltaTime t m | m -> t where
--   getDeltaTime :: m (Event t Float)

-- instance (Reflex t, Monad m) => DeltaTime t (AppT world vertex env t m) where
--   getDeltaTime = asks deltaTimeEvent

data AppSettings = AppSettings
  { appName :: Text,
    appVersion :: Word32
  }

mkAppSettings :: AppSettings
mkAppSettings =
  AppSettings
    { appName = "Idunn App",
      appVersion = 1
    }

setAppName :: Text -> AppSettings -> AppSettings
setAppName name settings = settings {appName = name}

setAppVersion :: Word32 -> AppSettings -> AppSettings
setAppVersion version settings = settings {appVersion = version}

type App world vertex env t m =
  ( MonadFix m,
    NotReady t m,
    PerformEvent t m,
    Adjustable t m,
    MonadHold t m,
    PostBuild t m,
    TriggerEvent t m,
    MonadInput t m,
    MonadECS world m,
    MonadECS world (Performable m),
    MonadGpu (Performable m),
    MonadGraphics vertex (Performable m),
    RequestExit m,
    RequestExit (Performable m),
    MonadIO (Performable m)
  )

class HasWorld env world where
  getWorld :: env -> world

newtype InitT vertex m a = InitT
  { unInitT :: ReaderT (InitEnv vertex) m a
  }
  deriving newtype
    ( Applicative,
      Functor,
      Monad,
      MonadReader (InitEnv vertex),
      MonadIO
    )

instance (Monad m) => MonadGpu (InitT vertex m) where
  getGpuM = InitT $ asks (.gpu)

runInitT :: InitT vertex m a -> InitEnv vertex -> m a
runInitT (InitT x) env = runReaderT x env

data InitEnv vertex = InitEnv
  { gpu :: Gpu,
    graphics :: Graphics vertex
  }

instance (Storable vertex, Monad m, Typeable vertex) => MonadGraphics vertex (InitT vertex m) where
  getGraphicsM = asks (.graphics)

instance MonadUnliftIO (SpiderHost Reflex.Global) where
  {-# INLINE withRunInIO #-}
  withRunInIO inner = SpiderHost $ inner runSpiderHost

run ::
  forall vertex world env t (m :: * -> *).
  ( t ~ SpiderTimeline Reflex.Global,
    m ~ SpiderHost Reflex.Global,
    Has world (SpiderHost Reflex.Global) (Mesh vertex),
    Has world (SpiderHost Reflex.Global) WorldTransform,
    Has world (SpiderHost Reflex.Global) WorldTransformUpdated,
    Has world (SpiderHost Reflex.Global) (Child RelativeTransform)
  ) =>
  InitT vertex m world ->
  AppSettings ->
  env ->
  GameM world vertex t m () ->
  IO ()
run mkWorld settings env game = runResourceT $ do
  platform <- initPlatform
  (window, windowPtr) <- initWindow platform settings.appName 800 600
  (width, height) <- readIORef window.dimensions

  gpu <- initGpu settings.appName settings.appVersion
  graphics :: Graphics vertex <- initGraphics gpu
  surface <- initSurface gpu windowPtr width height

  audio <- initAudio

  liftIO $ runSpiderHost $ do
    (ePostBuild, triggerPostBuild) <- newEventWithTriggerRef
    (eDeltaTime, triggerDeltaTime) <- newEventWithTriggerRef

    let initEnv =
          InitEnv
            { gpu = gpu,
              graphics = graphics
            }

    world <- flip runInitT initEnv $ do
      world <- mkWorld
      pure world

    asyncEvents <- newChan

    let gameTriggers :: GameTriggers t m =
          GameEvents
            { postBuild = Trigger triggerPostBuild,
              deltaTime = Trigger triggerDeltaTime
            }

    inputRef :: IORef (DMap.DMap Input (EventTrigger t)) <- newIORef mempty
    inputEvents <- setupInputSelector platform inputRef

    exitRequestedRef <- newIORef False
    eventsRef <- newIORef mempty

    let gameEnv =
          GameEnv
            { platform = platform,
              gpu = gpu,
              graphics = graphics,
              world = world,
              exitRequested = exitRequestedRef,
              input = inputEvents,
              events =
                GameEvents
                  { postBuild = ePostBuild,
                    deltaTime = eDeltaTime
                  }
            }

    physicsThread <- async $ runWith world $ fix $ \loop -> do
      loop

    renderingThread <- async $ runWith world $ fix $ \loop -> do
      propagateWorldTransformUpdates
      prepareRender gpu graphics
      render surface graphics identity width height
      loop

    (_, FireCommand fire) <- hostPerformEventT $ flip runPostBuildT ePostBuild $ flip runTriggerEventT asyncEvents $ runGameT game gameEnv

    asyncEventsThread <- liftIO $ async $ fix $ \loop -> do
      triggerRefs <- readChan asyncEvents
      mes <- liftIO $ forM triggerRefs $ \(EventTriggerRef er :=> TriggerInvocation a _) -> do
        me <- readIORef er
        pure $ (\e -> e :=> Identity a) <$> me
      void $ runSpiderHost $ fire (catMaybes mes) $ pure ()
      forM_ triggerRefs $ \(_ :=> TriggerInvocation _ cb) -> cb
      loop

    startTime <- liftIO $ getTime Monotonic
    -- fireEventRef gameTriggers.postBuild.unTrigger ()
    addEvent eventsRef gameTriggers.postBuild.unTrigger ()

    flip fix startTime $ \loop prevTime -> do
      input <- readIORef inputRef
      liftIO $ pumpEvents platform (Proxy @t) exitRequestedRef input eventsRef
      exitRequested <- readIORef exitRequestedRef
      unless exitRequested $ do
        currentTime <- liftIO $ getTime Monotonic
        --   --   let deltaTime :: Float = fromIntegral (toNanoSecs (diffTimeSpec currentTime prevTime)) / 1e9
        --   --   -- liftIO $ runSpiderHost $ addEvent eventsRef gameTriggers.deltaTime.unTrigger deltaTime
        pendingEvents <- readIORef eventsRef
        writeIORef eventsRef mempty
        void $ fire pendingEvents $ pure () -- gameplay systems run
        loop currentTime

    cancel physicsThread
    cancel renderingThread
    cancel asyncEventsThread
  where
    -- addEvent :: (MonadRef m, MonadIO m) => IORef [DSum tag Identity] -> Ref m (Maybe (tag a)) -> a -> m ()
    -- addEvent :: IORef [DSum tag Identity] -> IORef (Maybe (tag a)) -> a -> IO ()
    addEvent eventsRef trRef val =
      readRef trRef >>= \case
        Nothing -> pure ()
        Just tr -> modifyIORef' eventsRef $ (:) (tr :=> Identity val)
