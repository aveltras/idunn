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
    -- Transform (..),
    -- pattern Static,
    -- pattern Dynamic,
    -- pattern Kinematic,
    -- Shape (defaultSettings),
    -- ShapeSettings (..),
    Mesh (..),
    MonadWorld (..),
    -- spawnNode,
    RequestExit (..),
    MonadAudio (..),
    -- MonadInput (..),
    -- Vertex,
    App,
    run,
    mkAppSettings,
    setAppName,
    setAppVersion,
    DeltaTime (..),
  )
where

import Apecs hiding (Map, ask, asks)
import Control.Monad (forM, forM_, unless, void, when)
import Control.Monad.Fix (MonadFix, fix)
import Control.Monad.Reader
import Control.Monad.Ref (MonadRef (..))
import Control.Monad.Trans.Resource (InternalState, MonadResource (..), getInternalState, runInternalState)
import Data.Dependent.Sum
import Data.Functor.Identity (Identity (..))
import Data.IntMap.Strict (IntMap)
import Data.IntMap.Strict qualified as IntMap
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
import System.Clock
import UnliftIO
import UnliftIO.Resource

newtype AppT world vertex env t m a = AppT
  { unAppT :: ReaderT (AppEnv world vertex env t) m a
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
      MonadReader (AppEnv world vertex env t),
      MonadSample t,
      MonadTrans,
      NotReady t,
      -- PerformEvent t,
      PostBuild t,
      TriggerEvent t
    )

-- instance MonadTrans (AppT world vertex env t) where
--   lift :: (Monad m) => m a -> AppT world vertex env t m a
--   lift = AppT . lift . lift

instance (Monad m, Monad (Performable m), PerformEvent t m, Reflex t) => PerformEvent t (AppT world vertex env t m) where
  type Performable (AppT world vertex env t m) = SystemT world (Performable m)
  {-# INLINEABLE performEvent_ #-}
  performEvent_ event = do
    world <- asks world
    lift $ performEvent_ $ fmapCheap (runWith world) event
  {-# INLINEABLE performEvent #-}
  performEvent event = do
    world <- asks world
    lift $ performEvent $ fmapCheap (runWith world) event

class RequestExit m where
  requestExit :: m ()

instance (MonadIO m) => RequestExit (ReaderT (AppEnv world vertex t env) m) where
  requestExit = do
    exitRequestedRef <- asks exitRequestedRef
    writeIORef exitRequestedRef True

instance (MonadIO m) => MonadAudio (ReaderT (AppEnv world vertex env t) m) where
  playAudio soundPath = do
    audioBackend <- asks audio
    liftIO $ playSound audioBackend soundPath

data AppEnv world vertex env t = AppEnv
  { platform :: Platform,
    gpu :: Gpu,
    graphics :: Graphics vertex,
    audio :: Audio,
    -- physics :: Physics,
    -- state :: InternalState,
    deltaTimeEvent :: Event t Float,
    scancodeSubscriptions :: Subscriptions t Scancode Bool,
    keySubscriptions :: Subscriptions t Key Bool,
    world :: world,
    exitRequestedRef :: IORef Bool,
    env :: env
  }

instance HasGraphics vertex (AppEnv world vertex env t) where
  getGraphics = (.graphics)

instance HasGpu (AppEnv world vertex env t) where
  getGpu = (.gpu)

type Subscriptions t subject value = IORef (Map subject (IntMap (EventTrigger t (InputValue subject))))

instance (Reflex t, ReflexHost t) => MonadInput t (AppM world vertex env t m) Scancode where
  subscribe = subscribeImpl scancodeSubscriptions subscribeToScancode unsubscribeFromScancode

instance (Reflex t, ReflexHost t) => MonadInput t (AppM world vertex env t m) Key where
  subscribe = subscribeImpl keySubscriptions subscribeToKey unsubscribeFromKey

subscribeImpl :: (ReflexHost t, Ord subject) => (AppEnv world vertex env t -> Subscriptions t subject value) -> (Platform -> subject -> IO ()) -> (Platform -> subject -> IO ()) -> subject -> AppM world vertex env t m (Event t (InputValue subject))
subscribeImpl getSubscriptions doSubscribe doUnsubscribe subject = do
  platform <- asks platform
  subscriptions <- asks getSubscriptions
  newEventWithTrigger $ \eventTrigger -> do
    uniq <- newUnique
    let subscription = hashUnique uniq
    shouldSubscribe <- atomicModifyIORef' subscriptions $ \currentSubscriptions ->
      case Map.lookup subject currentSubscriptions of
        Just triggerMap -> (Map.insert subject (IntMap.insert subscription eventTrigger triggerMap) currentSubscriptions, False)
        Nothing -> (Map.insert subject (IntMap.singleton subscription eventTrigger) currentSubscriptions, True)
    when shouldSubscribe $ doSubscribe platform subject
    pure $ do
      shouldUnsubscribe <- atomicModifyIORef' subscriptions $ \currentSubscriptions -> do
        let triggerMap = Map.findWithDefault IntMap.empty subject currentSubscriptions
            newTriggerMap = IntMap.delete subscription triggerMap
         in if IntMap.null newTriggerMap
              then (Map.delete subject currentSubscriptions, True)
              else (Map.insert subject newTriggerMap currentSubscriptions, False)
      when shouldUnsubscribe $ doUnsubscribe platform subject

class (Reflex t, Monad m) => DeltaTime t m | m -> t where
  getDeltaTime :: m (Event t Float)

instance (Reflex t, Monad m) => DeltaTime t (AppT world vertex env t m) where
  getDeltaTime = asks deltaTimeEvent

instance (Adjustable t m) => Adjustable t (AppT world vertex env t m) where
  runWithReplace (AppT a) ev = AppT $ runWithReplace a (fmap unAppT ev)
  traverseIntMapWithKeyWithAdjust f dm0 dm' = AppT $ traverseIntMapWithKeyWithAdjust (\k v -> unAppT (f k v)) dm0 dm'
  traverseDMapWithKeyWithAdjust f dm0 dm' = AppT $ traverseDMapWithKeyWithAdjust (\k v -> unAppT (f k v)) dm0 dm'
  traverseDMapWithKeyWithAdjustWithMove f dm0 dm' = AppT $ traverseDMapWithKeyWithAdjustWithMove (\k v -> unAppT (f k v)) dm0 dm'

-- instance (MonadIO m) => MonadResource (AppT world vertex env t m) where
--   liftResourceT m = do
--     env <- AppT ask
--     liftIO $ runInternalState m env.state

runAppT :: AppT world vertex env t m a -> AppEnv world vertex env t -> m a
runAppT (AppT app) env = runReaderT app env

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
    DeltaTime t m,
    PostBuild t m,
    TriggerEvent t m,
    MonadInput t m Key,
    MonadInput t m Scancode,
    -- MonadWorld Mat4x4 m,
    Performable m ~ SystemT world (Performable (PerformEventT t m)),
    -- MonadReader env (Performable m),
    -- HasGraphics vertex (Performable m),
    -- MonadAudio (Performable m),
    -- RequestExit (Performable m),
    MonadIO (Performable m)
  )

type AppM world vertex env t m = AppT world vertex env t (TriggerEventT t (PostBuildT t (PerformEventT t m)))

data InitEnv vertex = InitEnv
  { gpu :: Gpu,
    graphics :: Graphics vertex
  }

instance HasGraphics vertex (InitEnv vertex) where
  getGraphics = (.graphics)

instance HasGpu (InitEnv vertex) where
  getGpu = (.gpu)

run ::
  forall vertex world env t m.
  ( t ~ SpiderTimeline Reflex.Global,
    m ~ SpiderHost Reflex.Global,
    Has world (ReaderT (AppEnv world vertex env t) (ResourceT IO)) (Mesh vertex),
    Has world (ReaderT (AppEnv world vertex env t) (ResourceT IO)) WorldTransform
    -- Has world m (Mesh vertex)
  ) =>
  ReaderT (InitEnv vertex) IO world ->
  AppSettings ->
  env ->
  AppM world vertex env t m () ->
  IO ()
run mkWorld settings env game = runResourceT $ do
  platform <- initPlatform
  gpu <- initGpu settings.appName settings.appVersion
  graphics :: Graphics vertex <- initGraphics gpu
  (window, windowPtr) <- initWindow platform settings.appName 800 600
  (width, height) <- readIORef window.dimensions
  surface <- initSurface gpu windowPtr width height
  audio <- initAudio

  let initEnv =
        InitEnv
          { gpu = gpu,
            graphics = graphics
          }

  world <- liftIO $ flip runReaderT initEnv $ do
    world <- mkWorld
    pure world

  asyncEvents <- newChan

  exitRequestedRef <- newIORef False
  eventsRef <- newIORef mempty
  keySubscriptions <- newIORef mempty
  scancodeSubscriptions <- newIORef mempty

  (fire, appEnv, trPostBuild, trDeltaTime) <- liftIO $ runSpiderHost $ do
    (ePostBuild, trPostBuild) <- newEventWithTriggerRef
    (eDeltaTime, trDeltaTime) <- newEventWithTriggerRef

    let appEnv =
          AppEnv
            { platform = platform,
              gpu = gpu,
              graphics = graphics,
              audio = audio,
              world = world,
              deltaTimeEvent = eDeltaTime,
              keySubscriptions = keySubscriptions,
              scancodeSubscriptions = scancodeSubscriptions,
              exitRequestedRef = exitRequestedRef,
              env = env
            }

    (_, FireCommand fire) <-
      hostPerformEventT $
        flip runPostBuildT ePostBuild $
          flip runTriggerEventT asyncEvents $
            runAppT game appEnv

    pure (fire, appEnv, trPostBuild, trDeltaTime)

  asyncTrigger <- liftIO $ async $ fix $ \loop -> do
    triggerRefs <- readChan asyncEvents
    mes <- liftIO $ forM triggerRefs $ \(EventTriggerRef er :=> TriggerInvocation a _) -> do
      me <- readIORef er
      pure $ (\e -> e :=> Identity a) <$> me
    void $ runSpiderHost $ fire (catMaybes mes) $ pure ()
    forM_ triggerRefs $ \(_ :=> TriggerInvocation _ cb) -> cb
    loop

  startTime <- liftIO $ getTime Monotonic
  liftIO $ addEvent eventsRef trPostBuild ()

  flip runReaderT appEnv $ runWith world $ flip fix startTime $ \loop prevTime -> do
    liftIO $ pumpEvents platform $ \case
      PlatformEventKey key active -> do
        subscriptions <- readIORef keySubscriptions
        case Map.lookup key subscriptions of
          Just triggers -> modifyIORef' eventsRef $ \events -> foldr (\eventTrigger -> (:) (eventTrigger :=> Identity active)) events triggers
          Nothing -> pure ()
      PlatformEventScancode scancode active -> do
        subscriptions <- readIORef scancodeSubscriptions
        case Map.lookup scancode subscriptions of
          Just triggers -> modifyIORef' eventsRef $ \events -> foldr (\eventTrigger -> (:) (eventTrigger :=> Identity active)) events triggers
          Nothing -> pure ()
      PlatformEventQuit -> writeIORef exitRequestedRef True
    exitRequested <- readIORef exitRequestedRef
    unless exitRequested $ do
      currentTime <- liftIO $ getTime Monotonic
      let deltaTime :: Float = fromIntegral (toNanoSecs (diffTimeSpec currentTime prevTime)) / 1e9
      liftIO $ addEvent eventsRef trDeltaTime deltaTime
      pendingEvents <- readIORef eventsRef
      writeIORef eventsRef mempty
      liftIO $ runSpiderHost $ void $ fire pendingEvents $ pure () -- gameplay systems run
      prepareRender gpu graphics
      render surface graphics identity width height
      loop currentTime

    -- auto Window::render(Handle<Gpu::World> world) -> void {
    --   auto projection = glm::perspective(glm::radians(60.0F), static_cast<float>(width) / static_cast<float>(height), 0.1F, 10.0F);
    --   projection *= glm::lookAt(glm::vec3(0.0F, 0.0F, 5.0F), glm::vec3(0.0F, 0.0F, 0.0F), glm::vec3(0.0F, 1.0F, 0.0F));
    --   gpu->render(surface, world, projection, width, height, 0);
    -- }

    cancel asyncTrigger
  where
    -- addEvent :: (MonadRef m, MonadIO m) => IORef [DSum tag Identity] -> Ref m (Maybe (tag a)) -> a -> m ()
    addEvent eventsRef trRef val =
      readRef trRef >>= \case
        Nothing -> pure ()
        Just tr -> modifyIORef' eventsRef $ (:) (tr :=> Identity val)
