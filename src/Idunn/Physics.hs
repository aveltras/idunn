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
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE TypeFamilyDependencies #-}
{-# LANGUAGE UndecidableInstances #-}

module Idunn.Physics
  ( Physics,
    PhysicsSystem,
    IsPhysicsSystem (..),
    HasPhysics (..),
    APhysicsSystem (..),
    PhysicsStore (..),
    initPhysics,
    withPhysicsSystem,
    update,
    BodyID,
    pattern Static,
    pattern Dynamic,
    pattern Kinematic,
    Shape (defaultSettings),
    ShapeSettings (..),
    createBody,
    onContactAdded,
  )
where

import Apecs hiding (Map, Set, asks)
import Apecs.Core hiding (Set)
import Control.Monad (forM_, when)
import Control.Monad.Reader
import Data.IntMap.Strict (IntMap)
import Data.IntMap.Strict qualified as IntMap
import Data.Kind (Type)
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Set
import Data.Unique (hashUnique, newUnique)
import Data.Vector.Generic.Mutable qualified as MV
import Data.Void (Void)
import Foreign
import Foreign.C
import GHC.Exts (RealWorld)
import HsBindgen.Runtime.Prelude hiding (Elem)
import Idunn.Linear.Vec
import Idunn.Physics.FFI
import Idunn.Vector
import Idunn.World
import UnliftIO
import UnliftIO.Resource

data Physics = Physics
  { ptr :: Ptr Void
  }

class HasPhysics env where
  getPhysics :: env -> Physics

initPhysics :: (MonadResource m) => m Physics
initPhysics = snd <$> allocate up down
  where
    up =
      alloca $ \pPhysics -> do
        idunn_physics_init pPhysics
        Physics <$> peek pPhysics
    down physics = idunn_physics_uninit physics.ptr

data PhysicsStore c = PhysicsStore
  { systems :: IORef (IntMap APhysicsSystem)
  }

instance (MonadIO m) => ExplInit m (PhysicsStore Physics) where
  explInit = do
    systemsRef <- newIORef mempty
    pure $
      PhysicsStore
        { systems = systemsRef
        }

instance Component Physics where
  type Storage Physics = PhysicsStore Physics

type instance Elem (PhysicsStore Physics) = Physics

data APhysicsSystem
  = forall broadPhaseLayer objectLayer s.
    (IsPhysicsSystem broadPhaseLayer objectLayer) =>
    APhysicsSystem (PhysicsSystem s broadPhaseLayer objectLayer)

class
  ( Eq objectLayer,
    Ord objectLayer,
    Bounded objectLayer,
    Enum objectLayer,
    Eq broadPhaseLayer,
    Ord broadPhaseLayer,
    Bounded broadPhaseLayer,
    Enum broadPhaseLayer,
    Show broadPhaseLayer
  ) =>
  IsPhysicsSystem broadPhaseLayer objectLayer
  where
  belongsTo :: objectLayer -> broadPhaseLayer
  shouldCollideBroad :: objectLayer -> Set broadPhaseLayer
  shouldCollideObject :: Proxy broadPhaseLayer -> objectLayer -> Set objectLayer

data PhysicsSystem s broadPhaseLayer objectLayer = PhysicsSystem
  { ptr :: Ptr Void,
    ptrContactRemovedCount :: Ptr Word32,
    ptrContactRemoved :: Ptr (Ptr Word64),
    ptrActiveBodyCount :: Ptr Word32,
    ptrActiveBodyIdsPtr :: Ptr (Ptr Word32),
    contactAddedListeners :: IORef (Map (BodyID s) (IO ())),
    onContactAddedFn :: FunPtr Idunn_physics_on_contact_added_Aux
  }

newtype BodyID s = BodyID
  { raw :: Word32
  }
  deriving stock (Show)
  deriving newtype (Eq, Ord)

withPhysicsSystem ::
  forall broadPhaseLayer objectLayer env w m a.
  ( IsPhysicsSystem broadPhaseLayer objectLayer,
    Has w m Physics,
    HasWorldInit env,
    HasPhysics env,
    MonadReader env m,
    MonadResource m
  ) =>
  Proxy broadPhaseLayer ->
  Proxy objectLayer ->
  (forall s. PhysicsSystem s broadPhaseLayer objectLayer -> SystemT w m a) ->
  SystemT w m a
withPhysicsSystem _ _ f = do
  worldInit <- lift $ asks getWorldInit
  worldTransforms <- readIORef worldInit.worldTransforms
  physics <- lift $ asks getPhysics
  physicsStore :: PhysicsStore Physics <- getStore
  uniq <- liftIO newUnique
  let systemId = hashUnique uniq -- TODO: handle collision
  let registerSystem = \system -> atomicModifyIORef' physicsStore.systems $ \systems -> (IntMap.insert systemId (APhysicsSystem system) systems, system)
  let unregisterSystem :: IO () = atomicModifyIORef' physicsStore.systems $ \systems -> (IntMap.delete systemId systems, ())
  (_, physicsSystem) <- allocate (up physics worldTransforms registerSystem) $ down unregisterSystem
  f physicsSystem
  where
    allBroadPhaseLayers :: [broadPhaseLayer] = [minBound .. maxBound]
    allObjectLayers :: [objectLayer] = [minBound .. maxBound]
    broadPhaseLayerCount = length allBroadPhaseLayers
    broadPhaseLayerNames = [show l | l <- allBroadPhaseLayers]
    objectLayerCount = length allObjectLayers
    objToBroadMapping = [fromIntegral $ fromEnum @broadPhaseLayer (belongsTo l) | l <- allObjectLayers]
    objectCollisions =
      [ if l2 `member` shouldCollideObject (Proxy @broadPhaseLayer) l1 then 1 else 0
      | l1 <- allObjectLayers,
        l2 <- allObjectLayers
      ]
    broadCollisions =
      [ if bl `member` shouldCollideBroad ol then 1 else 0
      | ol <- allObjectLayers,
        bl <- allBroadPhaseLayers
      ]

    down :: IO () -> PhysicsSystem s broadPhaseLayer objectLayer -> IO ()
    down unregisterSystem system = do
      putStrLn "drop physics"
      unregisterSystem
      freeHaskellFunPtr system.onContactAddedFn
      idunn_physics_system_uninit system.ptr
      free system.ptrActiveBodyCount
      free system.ptrActiveBodyIdsPtr

    up physics transforms registerSystem = alloca $ \ptrConfig -> do
      ptrContactRemovedCount <- malloc
      ptrContactRemoved <- malloc
      contactAddedListeners <- newIORef mempty
      ptrActiveBodyCount <- malloc
      ptrActiveBodyIdsPtr <- malloc
      onContactAddedFn <- toFunPtr $ Idunn_physics_on_contact_added_Aux $ \rawBodyID1 rawBodyID2 -> do
        listeners <- readIORef contactAddedListeners
        case Map.lookup (BodyID rawBodyID1) listeners of
          Nothing -> pure ()
          Just listener -> listener
        case Map.lookup (BodyID rawBodyID2) listeners of
          Nothing -> pure ()
          Just listener -> listener
      withMany withCString broadPhaseLayerNames $ \c'broadPhaseLayerNames ->
        withArray c'broadPhaseLayerNames $ \ptrBroadPhaseLayerNames ->
          withArray objToBroadMapping $ \ptrObjToBroad ->
            withArray objectCollisions $ \ptrObjectCollisions ->
              withArray broadCollisions $ \ptrBroadCollisions -> do
                poke ptrConfig $
                  Idunn_physics_system_config
                    { idunn_physics_system_config_bodyMutexes = 0,
                      idunn_physics_system_config_maxBodies = 1024,
                      idunn_physics_system_config_maxBodyPairs = 1024,
                      idunn_physics_system_config_maxContactConstraints = 1024,
                      idunn_physics_system_config_broadPhaseLayerCount = fromIntegral broadPhaseLayerCount,
                      idunn_physics_system_config_broadPhaseLayerNames = ptrBroadPhaseLayerNames,
                      idunn_physics_system_config_objectLayerCount = fromIntegral objectLayerCount,
                      idunn_physics_system_config_objectToBroadPhaseLayers = ptrObjToBroad,
                      idunn_physics_system_config_objectCollisions = ptrObjectCollisions,
                      idunn_physics_system_config_broadCollisions = ptrBroadCollisions,
                      idunn_physics_system_config_pContactRemovedCount = ptrContactRemovedCount,
                      idunn_physics_system_config_pContactRemoved = ptrContactRemoved,
                      idunn_physics_system_config_onContactAdded = Idunn_physics_on_contact_added onContactAddedFn,
                      idunn_physics_system_config_transformData = castPtr transforms.bufferPtr,
                      idunn_physics_system_config_pActiveBodyCount = ptrActiveBodyCount,
                      idunn_physics_system_config_ppActiveBodies = ptrActiveBodyIdsPtr
                    }
                alloca $ \ptrSystem -> do
                  idunn_physics_system_init physics.ptr ptrConfig ptrSystem
                  system <- peek ptrSystem
                  registerSystem
                    PhysicsSystem
                      { ptr = system,
                        ptrContactRemovedCount = ptrContactRemovedCount,
                        ptrContactRemoved = ptrContactRemoved,
                        ptrActiveBodyCount = ptrActiveBodyCount,
                        ptrActiveBodyIdsPtr = ptrActiveBodyIdsPtr,
                        contactAddedListeners = contactAddedListeners,
                        onContactAddedFn = onContactAddedFn
                      }

update :: (MonadIO m, Has w m Node3D) => PhysicsSystem s broadPhaseLayer objectLayer -> SystemT w m ()
update system = do
  liftIO $ idunn_physics_system_update_safe system.ptr
  contactRemovedCount <- liftIO $ peek system.ptrContactRemovedCount
  when (contactRemovedCount > 0) $ do
    ptrElements <- liftIO $ peek system.ptrContactRemoved
    forM_ [0 .. fromIntegral contactRemovedCount - 1] $ \i -> do
      raw :: Word64 <- liftIO $ peekElemOff ptrElements i
      let body1 = fromIntegral $ raw `shiftR` 32
          body2 = fromIntegral $ raw .&. 0xFFFFFFFF
      liftIO $ print (BodyID body1, BodyID body2)
  activeBodyCount <- liftIO $ peek system.ptrActiveBodyCount
  when (activeBodyCount > 0) $ do
    store :: Nodes Node3D <- getStore
    ptrActiveBodies <- liftIO $ peek system.ptrActiveBodyIdsPtr
    forM_ [0 .. fromIntegral activeBodyCount - 1] $ \i -> do
      node3D :: Word32 <- liftIO $ peekElemOff ptrActiveBodies i
      liftIO $ print (Node3D $ fromIntegral node3D)
      markDirty store (Node3D $ fromIntegral node3D)

data SphereShape

class (Storable (ForeignSettings shape)) => Shape shape where
  data ShapeSettings shape :: Type
  defaultSettings :: ShapeSettings shape
  type ForeignSettings shape = r | r -> shape
  foreignShapeType :: Proxy shape -> Idunn_physics_shape_type
  foreignSetter :: ForeignSettings shape -> Idunn_physics_body_settings_shapeSettings
  foreignSettings :: ShapeSettings shape -> ForeignSettings shape

instance Shape SphereShape where
  data ShapeSettings SphereShape
    = SphereShapeSettings
    { radius :: Float
    }

  defaultSettings =
    SphereShapeSettings
      { radius = 0
      }

  type ForeignSettings SphereShape = Idunn_physics_sphere_shape_settings
  foreignShapeType _ = Sphere

  foreignSetter = set_idunn_physics_body_settings_shapeSettings_sphere
  foreignSettings settings =
    Idunn_physics_sphere_shape_settings
      { idunn_physics_sphere_shape_settings_radius = CFloat settings.radius
      }

data BoxShape

instance Shape BoxShape where
  data ShapeSettings BoxShape
    = BoxShapeSettings
    { halfExtentX :: Float,
      halfExtentY :: Float,
      halfExtentZ :: Float,
      convexRadius :: Float
    }

  defaultSettings =
    BoxShapeSettings
      { halfExtentX = 0,
        halfExtentY = 0,
        halfExtentZ = 0,
        convexRadius = 0.05
      }

  type ForeignSettings BoxShape = Idunn_physics_box_shape_settings
  foreignShapeType _ = Box
  foreignSetter = set_idunn_physics_body_settings_shapeSettings_box
  foreignSettings settings =
    Idunn_physics_box_shape_settings
      { idunn_physics_box_shape_settings_halfExtentX = CFloat settings.halfExtentX,
        idunn_physics_box_shape_settings_halfExtentY = CFloat settings.halfExtentY,
        idunn_physics_box_shape_settings_halfExtentZ = CFloat settings.halfExtentZ,
        idunn_physics_box_shape_settings_convexRadius = CFloat settings.convexRadius
      }

type MotionType = Idunn_physics_motion_type

createBody ::
  forall shape broadPhaseLayer objectLayer m w s.
  (Shape shape, MonadIO m, IsPhysicsSystem broadPhaseLayer objectLayer) =>
  PhysicsSystem s broadPhaseLayer objectLayer ->
  Node3D ->
  Vec3 ->
  MotionType ->
  objectLayer ->
  ShapeSettings shape ->
  SystemT w m ()
createBody system (Node3D node) position motionType objectLayer settings = do
  liftIO $ do
    alloca $ \ptrSettings -> do
      poke ptrSettings $
        Idunn_physics_body_settings
          { idunn_physics_body_settings_shapeSettings = foreignSetter $ foreignSettings settings,
            idunn_physics_body_settings_shapeType = foreignShapeType (Proxy :: Proxy shape),
            idunn_physics_body_settings_objectLayer = fromIntegral $ fromEnum objectLayer,
            idunn_physics_body_settings_position = toPtr position,
            idunn_physics_body_settings_motionType = motionType,
            idunn_physics_body_settings_bodyID = fromIntegral node
          }
      idunn_physics_body_init system.ptr ptrSettings

onContactAdded :: (MonadIO m) => PhysicsSystem s broadPhaseLayer objectLayer -> BodyID s -> IO () -> m ()
onContactAdded system bodyID f = do
  atomicModifyIORef' system.contactAddedListeners $ \listeners -> (Map.insert bodyID f listeners, ())
  liftIO $ idunn_physics_body_contact_subscribe system.ptr bodyID.raw
