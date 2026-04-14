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

module Idunn.Platform
  ( Platform (..),
    initPlatform,
    PlatformEvent (..),
    pumpEvents,
    subscribeToScancode,
    unsubscribeFromScancode,
    subscribeToKey,
    unsubscribeFromKey,
  )
where

import Control.Monad (unless)
import Data.Foldable (forM_)
import Data.Void
import Foreign
import Foreign.C hiding (withCString)
import Idunn.Platform.FFI
import UnliftIO.Resource

data Platform = Platform
  { ptr :: Ptr Void,
    ptrDeltaTime :: Ptr CFloat,
    ptrEventCount :: Ptr Word32,
    ptrEventsPtr :: Ptr (Ptr Idunn_platform_event)
  }

initPlatform :: (MonadResource m) => m Platform
initPlatform = snd <$> allocate up down
  where
    up = alloca $ \ptrPlatformPtr ->
      alloca $ \ptrConfig -> do
        ptrDeltaTime <- malloc
        ptrEventCount <- malloc
        ptrEventsPtr <- malloc
        poke ptrConfig $ Idunn_platform_config ptrDeltaTime ptrEventCount ptrEventsPtr
        idunn_platform_init ptrConfig ptrPlatformPtr
        ptrPlatform <- peek ptrPlatformPtr
        pure $
          Platform
            { ptr = ptrPlatform,
              ptrDeltaTime = ptrDeltaTime,
              ptrEventCount = ptrEventCount,
              ptrEventsPtr = ptrEventsPtr
            }
    down platform = do
      idunn_platform_uninit platform.ptr
      free platform.ptrEventCount
      free platform.ptrEventsPtr
      free platform.ptrDeltaTime

data PlatformEvent
  = PlatformEventKey Key Bool
  | PlatformEventScancode Scancode Bool
  | PlatformEventQuit

pumpEvents :: Platform -> (PlatformEvent -> IO ()) -> IO ()
pumpEvents platform f = do
  idunn_platform_tick platform.ptr
  eventCount <- peek platform.ptrEventCount
  unless (eventCount == 0) $ do
    ptrEvents <- peek platform.ptrEventsPtr
    events <- peekArray (fromIntegral eventCount) ptrEvents
    forM_ events $ \event -> do
      case idunn_platform_event_type event of
        KeyEvent -> do
          let keyEvent = get_idunn_platform_event_payload_key $ idunn_platform_event_payload event
          f $ PlatformEventKey (idunn_platform_key_event_key keyEvent) $ toBool $ idunn_platform_key_event_value keyEvent
        ScancodeEvent -> do
          let scancodeEvent = get_idunn_platform_event_payload_scancode $ idunn_platform_event_payload event
          f $ PlatformEventScancode (idunn_platform_scancode_event_scancode scancodeEvent) $ toBool $ idunn_platform_scancode_event_value scancodeEvent
        QuitEvent -> f PlatformEventQuit
        _ -> pure ()

subscribeToScancode :: Platform -> Scancode -> IO ()
subscribeToScancode platform scancode = idunn_platform_scancode_subscribe platform.ptr scancode

unsubscribeFromScancode :: Platform -> Scancode -> IO ()
unsubscribeFromScancode platform scancode = idunn_platform_scancode_unsubscribe platform.ptr scancode

subscribeToKey :: Platform -> Key -> IO ()
subscribeToKey platform key = idunn_platform_key_subscribe platform.ptr key

unsubscribeFromKey :: Platform -> Key -> IO ()
unsubscribeFromKey platform key = idunn_platform_key_unsubscribe platform.ptr key
