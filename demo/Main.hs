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

module Main where

import Control.Monad.IO.Class (liftIO)
import Data.Proxy
import Idunn
import Paths_idunn qualified as Cabal

main :: IO ()
main = run ScreenA $ \case
  ScreenA -> screenA
  ScreenB -> screenB

screenA :: (App t m) => World Vertex -> m (Event t Screen)
screenA world = do
  withPhysicsSystem (Proxy @BroadPhaseLayer) (Proxy @ObjectLayer) $ \physicsSystem -> do
    ePostBuild <- getPostBuild
    currentTime <- liftIO getCurrentTime
    ePhysicsTick <- tickLossyFrom (1 / 60) currentTime ePostBuild
    performEvent_ $ ffor ePhysicsTick $ const $ update physicsSystem
    floorID <- createBody physicsSystem (mkVec3 0 (-1) 0) Static NonMoving $ defaultSettings {halfExtentX = 100, halfExtentY = 1, halfExtentZ = 100}
    -- onContactAdded physicsSystem floorID $ logDebug "FLOOR CONTACT!"
    nodeID <- liftIO $ spawnNode rootNode identity world
    setNodeMesh world nodeID
    childNodeID <- liftIO $ spawnNode nodeID (translate identity $ mkVec3 0 1 0) world
    setNodeMesh world childNodeID
    grandChildNodeID <- liftIO $ spawnNode childNodeID (translate identity $ mkVec3 1 0 0) world
    setNodeMesh world grandChildNodeID
    syncWorldTransforms world
    sphereID <- createBody physicsSystem (mkVec3 0 100 0) Dynamic Moving $ defaultSettings {radius = 0.5}
    onContactAdded physicsSystem sphereID $ logDebug "SPHERE CONTACT!"
    eKeyE <- subscribe KeyE
    performEvent_ $ ffor (ffilter id eKeyE) $ \_ -> do
      logInfo "Key 'E' Pressed "
      soundPath <- liftIO $ Cabal.getDataFileName "demo/assets/freesound_community-wind-6352.mp3"
      playSound soundPath
    performEvent_ $ ffor ePostBuild $ const $ logInfo "PART A"
    eKeyX <- subscribe KeyX
    pure $ ScreenB <$ ffilter id eKeyX

screenB :: (App t m) => World Vertex -> m (Event t Screen)
screenB world = do
  ePostBuild <- getPostBuild
  performEvent_ $ ffor ePostBuild $ const $ logInfo "PART B"
  eScancodeW <- subscribe ScancodeW
  performEvent_ $ ffor (ffilter id eScancodeW) $ \_ -> logInfo "Scancode 'W' Pressed "
  eKeyX <- subscribe KeyX
  pure $ ScreenA <$ ffilter id eKeyX

data Screen
  = ScreenA
  | ScreenB
  deriving stock (Show, Eq)

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
