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

module Main where

import Control.Monad.IO.Class (liftIO)
import Idunn
import Paths_idunn qualified as Cabal

main :: IO ()
main = run app

app :: (App t m) => m ()
app = do
  ePostBuild <- getPostBuild
  performEvent_ $ ffor ePostBuild $ \_ -> logInfo "postBuild"
  eKey <- subscribe KeyE
  let eKeyPressed = ffilter ((==) True) eKey
  performEvent_ $ ffor eKeyPressed $ \_ -> do
    logInfo "Key 'E' Pressed "
    soundPath <- liftIO $ Cabal.getDataFileName "demo/assets/freesound_community-wind-6352.mp3"
    playSound soundPath
  eScancode <- subscribe ScancodeW
  let eScancodePressed = ffilter ((==) True) eScancode
  performEvent_ $ ffor eScancodePressed $ \_ -> logInfo "Scancode 'W' Pressed "
