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

module Idunn.Physics
  ( Physics,
    PhysicsSystem,
    IsPhysicsSystem (..),
    HasPhysics (..),
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

import Control.Monad (forM_, when)
import Control.Monad.Reader
import Data.Kind (Type)
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Proxy
import Data.Set
import Data.Void (Void)
import Foreign
import Foreign.C
import HsBindgen.Runtime.Prelude
import Idunn.Linear.Vec
import Idunn.Physics.FFI
import Idunn.Resource
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
    contactAddedListeners :: IORef (Map (BodyID s) (IO ())),
    onContactAddedFn :: FunPtr Idunn_physics_on_contact_added_Aux
  }

newtype BodyID s = BodyID
  { raw :: Word32
  }
  deriving stock (Show)
  deriving newtype (Eq, Ord)

withPhysicsSystem ::
  forall broadPhaseLayer objectLayer env m a.
  ( IsPhysicsSystem broadPhaseLayer objectLayer,
    HasPhysics env,
    HasResources env,
    MonadReader env m,
    MonadResource m
  ) =>
  Proxy broadPhaseLayer ->
  Proxy objectLayer ->
  (forall s. PhysicsSystem s broadPhaseLayer objectLayer -> m a) ->
  m a
withPhysicsSystem _ _ f = do
  physics <- asks getPhysics
  resources <- asks getResources
  physicsSystem <- allocateAndStore resources (up physics) down
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
    down system = do
      freeHaskellFunPtr system.onContactAddedFn
      idunn_physics_system_uninit system.ptr
    up physics = alloca $ \ptrConfig -> do
      ptrContactRemovedCount <- malloc
      ptrContactRemoved <- malloc
      contactAddedListeners <- newIORef mempty
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
                      idunn_physics_system_config_onContactAdded = Idunn_physics_on_contact_added onContactAddedFn
                    }
                alloca $ \ptrSystem -> do
                  idunn_physics_system_init physics.ptr ptrConfig ptrSystem
                  system <- peek ptrSystem
                  pure $
                    PhysicsSystem
                      { ptr = system,
                        ptrContactRemovedCount = ptrContactRemovedCount,
                        ptrContactRemoved = ptrContactRemoved,
                        contactAddedListeners = contactAddedListeners,
                        onContactAddedFn = onContactAddedFn
                      }

update :: (MonadIO m) => PhysicsSystem s broadPhaseLayer objectLayer -> m ()
update system = liftIO $ do
  idunn_physics_system_update_safe system.ptr
  contactRemovedCount <- peek system.ptrContactRemovedCount
  when (contactRemovedCount > 0) $ do
    ptrElements <- peek system.ptrContactRemoved
    forM_ [0 .. fromIntegral contactRemovedCount - 1] $ \i -> do
      raw :: Word64 <- peekElemOff ptrElements i
      let body1 = fromIntegral $ raw `shiftR` 32
          body2 = fromIntegral $ raw .&. 0xFFFFFFFF
      print (BodyID body1, BodyID body2)

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
  forall shape broadPhaseLayer objectLayer m s.
  (Shape shape, MonadIO m, IsPhysicsSystem broadPhaseLayer objectLayer) =>
  PhysicsSystem s broadPhaseLayer objectLayer ->
  Vec3 ->
  MotionType ->
  objectLayer ->
  ShapeSettings shape ->
  m (BodyID s)
createBody system position motionType objectLayer settings = liftIO $ do
  alloca $ \ptrBodyID -> do
    alloca $ \ptrSettings -> do
      poke ptrSettings $
        Idunn_physics_body_settings
          { idunn_physics_body_settings_shapeSettings = foreignSetter $ foreignSettings settings,
            idunn_physics_body_settings_shapeType = foreignShapeType (Proxy :: Proxy shape),
            idunn_physics_body_settings_objectLayer = fromIntegral $ fromEnum objectLayer,
            idunn_physics_body_settings_position = toPtr position,
            idunn_physics_body_settings_motionType = motionType
          }
      idunn_physics_body_init system.ptr ptrSettings ptrBodyID
      BodyID <$> peek ptrBodyID

onContactAdded :: (MonadIO m) => PhysicsSystem s broadPhaseLayer objectLayer -> BodyID s -> IO () -> m ()
onContactAdded system bodyID f = do
  atomicModifyIORef' system.contactAddedListeners $ \listeners -> (Map.insert bodyID f listeners, ())
  liftIO $ idunn_physics_body_contact_subscribe system.ptr bodyID.raw
