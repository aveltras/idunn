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
{-# LANGUAGE OverloadedLists #-}
{-# LANGUAGE RecursiveDo #-}
{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE TypeFamilies #-}

-- {-# OPTIONS_GHC -ddump-splices #-}

module Main where

import Apecs hiding (asks)
import Apecs.Experimental.Children
import Control.Monad.IO.Class
import Data.Data (Typeable)
import Data.Function ((&))
import Data.Functor ((<&>))
import Data.Proxy
import Data.Set qualified as Set
import Foreign
import Idunn hiding (Set)
import Paths_idunn qualified as Cabal

newtype Vertex = Vertex Vec3
  deriving newtype (Storable)
  deriving stock (Typeable)

type MyMesh = Mesh Vertex

type ChildTransform = Child RelativeTransform

makeWorld
  "MyWorld"
  [ ''RelativeTransform,
    ''WorldTransform,
    ''ChildTransform,
    ''WorldTransformUpdated,
    ''MyMesh
  ]

data MyGame = MyGame

data MyGameState
  = ScreenA
  | ScreenB

main :: IO ()
main = do
  run initMyWorld settings MyGame game
  where
    settings = mkAppSettings & setAppName "Demo"

game :: (App MyWorld Vertex MyGame t m) => m ()
game = do
  -- withPhysics (Proxy @BroadPhaseLayer) (Proxy @ObjectLayer) $ \physicsSystem -> do
  ePostBuild <- getPostBuild
  -- eDeltaTime <- getDeltaTime

  eEscape <- onScancode ScancodeEscape
  performEvent_ $ ffor eEscape $ const requestExit

  let indices = [0, 1, 2, 0, 2, 3]
  let vertices =
        [ Vertex $ mkVec3 (-1) (-1) 1,
          Vertex $ mkVec3 1 (-1) 1,
          Vertex $ mkVec3 1 1 1,
          Vertex $ mkVec3 (-1) 1 1
        ]

  performEvent_ $ ffor ePostBuild $ const $ runECS $ do
    -- entity' <- newEntity (WorldTransform $ translate identity $ mkVec3 0 1 0, Mesh 5 vertices indices)
    parent <- newEntity (RelativeTransform $ translate identity $ mkVec3 0 1 0, Mesh 5 vertices indices)
    -- parent' <- newEntity (WorldTransformUpdated, WorldTransform $ translate identity $ mkVec3 0 1 0, Mesh 5 vertices indices)
    newEntity_ (RelativeTransform identity, Child parent $ RelativeTransform $ translate identity $ mkVec3 1 0 0, Mesh 5 vertices indices)
    pure ()

  -- where
  --

  rec dynGameState <- holdDyn ScreenA eNextLevel
      eNextLevel <- switchHold never eeNextLevel
      eeNextLevel <- networkView $ ffor dynGameState $ \case
        ScreenA -> screenA
        ScreenB -> screenB

  -- currentTime <- liftIO getCurrentTime
  -- liftIO $ putStrLn "screenA"

  -- setMesh root vertices indices

  -- parent <- spawnChildOf root $ translate identity $ mkVec3 0 1 0
  -- setMesh parent vertices indices
  -- setRigidBody parent physicsSystem (mkVec3 0 1 0) Dynamic Moving $ defaultSettings {halfExtentX = 100, halfExtentY = 1, halfExtentZ = 100}

  -- child <- spawnChildOf parent $ translate identity $ mkVec3 1 0 0
  -- setMesh child vertices indices

  -- floorID <- createBody physicsSystem (mkVec3 0 (-1) 0) Static NonMoving $ defaultSettings {halfExtentX = 100, halfExtentY = 1, halfExtentZ = 100}
  -- onContactAdded physicsSystem floorID $ logDebug "FLOOR CONTACT!"

  -- createBody physicsSystem rootNode3D (mkVec3 0 1 0) Dynamic Moving $ defaultSettings {halfExtentX = 100, halfExtentY = 1, halfExtentZ = 100}

  -- child <-
  --   newEntity
  --     ( Transform (Just parentNode3D) $ translate identity $ mkVec3 1 0 0,
  --       GpuMesh vertices indices
  --     )

  -- root $= GpuMesh vertices indices
  -- setNodeMesh root
  -- childNodeID <- liftIO $ spawnNode nodeID (translate identity $ mkVec3 0 1 0) world
  -- setNodeMesh world childNodeID
  -- grandChildNodeID <- liftIO $ spawnNode childNodeID (translate identity $ mkVec3 1 0 0) world
  -- setNodeMesh world grandChildNodeID
  -- sphereID <- createBody physicsSystem (mkVec3 0 100 0) Dynamic Moving $ defaultSettings {radius = 0.5}
  -- onContactAdded physicsSystem sphereID $ logDebug "SPHERE CONTACT!"

  -- eScancodeW <- subscribe ScancodeW
  -- eScancodeA <- subscribe ScancodeA
  -- eScancodeS <- subscribe ScancodeS
  -- eScancodeD <- subscribe ScancodeD

  -- dynMove <-
  --   foldDyn ($) mempty $
  --     mergeWith
  --       (.)
  --       [ eScancodeW <&> \pressed -> if pressed then Set.insert MoveUp else Set.delete MoveUp,
  --         eScancodeA <&> \pressed -> if pressed then Set.insert MoveLeft else Set.delete MoveLeft,
  --         eScancodeS <&> \pressed -> if pressed then Set.insert MoveDown else Set.delete MoveDown,
  --         eScancodeD <&> \pressed -> if pressed then Set.insert MoveRight else Set.delete MoveRight
  --       ]

  -- eTick <- tickLossyFrom (1 / 144) currentTime ePostBuild
  -- performEvent_ $ ffor (tagPromptlyDyn dynMove eTick) $ \moves -> do
  --   let moveX = if Set.member MoveLeft moves then (-1) else 0
  --   let moveX' = moveX + if Set.member MoveRight moves then 1 else 0
  --   let moveY = if Set.member MoveUp moves then 1 else 0
  --   let moveY' = moveY + if Set.member MoveDown moves then (-1) else 0
  --   when (moveX' /= 0 || moveY' /= 0) $
  --     modify root $
  --       \(LocalTransform transform) -> (LocalTransform $ translate transform $ mkVec3 (moveX' * 0.2) (moveY' * 0.2) 0)

  -- performEvent_ $ ffor ePostBuild $ const $ logInfo "PART A"
  -- eKeyX <- subscribe KeyX
  -- pure $ ScreenB <$ ffilter id eKeyX
  pure ()

screenA :: (App MyWorld Vertex MyGame t m) => m (Event t MyGameState)
screenA = do
  ePostBuild <- getPostBuild
  performEvent_ $ ffor ePostBuild $ const $ logInfo "PART A"

  eScancodeW <- onScancode ScancodeW
  performEvent_ $ ffor (ffilter id eScancodeW) $ \_ -> logInfo "Scancode 'W' Pressed in screenA"

  -- eKeyE <- subscribe KeyE
  -- performEvent_ $ ffor (ffilter id eKeyE) $ \_ -> do
  --   logInfo "Key 'E' Pressed "
  --   soundPath <- liftIO $ Cabal.getDataFileName "demo/assets/freesound_community-wind-6352.mp3"
  --   playAudio soundPath

  eKeyX <- onKey KeyX
  pure $ ScreenB <$ ffilter id eKeyX

screenB :: (App MyWorld Vertex MyGame t m) => m (Event t MyGameState)
screenB = do
  ePostBuild <- getPostBuild
  performEvent_ $ ffor ePostBuild $ const $ logInfo "PART B"

  eScancodeW <- onScancode ScancodeW
  performEvent_ $ ffor (ffilter id eScancodeW) $ \_ -> logInfo "Scancode 'W' Pressed in screenB"

  eKeyX <- onKey KeyX
  pure $ ScreenA <$ ffilter id eKeyX

data Move
  = MoveLeft
  | MoveRight
  | MoveUp
  | MoveDown
  deriving stock (Eq, Ord)

data ObjectLayer
  = NonMoving
  | Moving
  | Debris
  | Bullet
  | Weapon
  deriving stock (Bounded, Eq, Ord, Enum)

data BroadPhaseLayer
  = BroadPhaseLayerNonMoving
  | BroadPhaseLayerMoving
  | BroadPhaseLayerDebris
  deriving stock (Bounded, Eq, Ord, Enum, Show)

instance IsPhysicsSystem BroadPhaseLayer ObjectLayer where
  belongsTo = \case
    NonMoving -> BroadPhaseLayerNonMoving
    Moving -> BroadPhaseLayerMoving
    Debris -> BroadPhaseLayerDebris
    Bullet -> BroadPhaseLayerMoving
    Weapon -> BroadPhaseLayerNonMoving

  shouldCollideBroad = \case
    NonMoving -> [BroadPhaseLayerMoving, BroadPhaseLayerDebris]
    Moving -> [BroadPhaseLayerNonMoving, BroadPhaseLayerMoving]
    Debris -> [BroadPhaseLayerNonMoving]
    Weapon -> [BroadPhaseLayerNonMoving, BroadPhaseLayerMoving]
    _ -> []

  shouldCollideObject _ = \case
    Moving -> [NonMoving, Moving]
    Debris -> [NonMoving]
    Weapon -> [NonMoving, Bullet]
    _ -> []
