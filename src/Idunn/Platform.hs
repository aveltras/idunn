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
    pumpEvents,
    subscribeToScancode,
    unsubscribeFromScancode,
    subscribeToKey,
    unsubscribeFromKey,
  )
where

import Control.Monad (unless)
import Data.Dependent.Map (DMap)
import Data.Dependent.Map qualified as DMap
import Data.Dependent.Sum (DSum (..))
import Data.Foldable (forM_)
import Data.Functor.Identity (Identity (..))
import Data.Proxy
import Data.Void
import Foreign
import Foreign.C hiding (withCString)
import Idunn.Input
import Idunn.Platform.FFI
import Reflex.Host.Class
import UnliftIO
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

pumpEvents :: Platform -> Proxy t -> IORef Bool -> DMap Input (EventTrigger t) -> IORef [DSum (EventTrigger t) Identity] -> IO ()
pumpEvents platform _ exitRequestedRef subscribers eventsRef = do
  idunn_platform_tick platform.ptr
  eventCount <- peek platform.ptrEventCount
  unless (eventCount == 0) $ do
    ptrEvents <- peek platform.ptrEventsPtr
    events <- peekArray (fromIntegral eventCount) ptrEvents
    forM_ events $ \event -> do
      case idunn_platform_event_type event of
        KeyEvent -> do
          let keyEvent = get_idunn_platform_event_payload_key $ idunn_platform_event_payload event
          case DMap.lookup (InputKey $ idunn_platform_key_event_key keyEvent) subscribers of
            Just trigger -> modifyIORef' eventsRef $ \pendingEvents -> (trigger :=> Identity (toBool $ idunn_platform_key_event_value keyEvent)) : pendingEvents
            Nothing -> pure ()
        ScancodeEvent -> do
          let scancodeEvent = get_idunn_platform_event_payload_scancode $ idunn_platform_event_payload event
          case DMap.lookup (InputScancode $ idunn_platform_scancode_event_scancode scancodeEvent) subscribers of
            Just trigger -> modifyIORef' eventsRef $ \pendingEvents -> (trigger :=> Identity (toBool $ idunn_platform_scancode_event_value scancodeEvent)) : pendingEvents
            Nothing -> pure ()
        QuitEvent -> writeIORef exitRequestedRef True
        _ -> pure ()

subscribeToScancode :: Platform -> Scancode -> IO ()
subscribeToScancode platform scancode = idunn_platform_scancode_subscribe platform.ptr scancode

unsubscribeFromScancode :: Platform -> Scancode -> IO ()
unsubscribeFromScancode platform scancode = idunn_platform_scancode_unsubscribe platform.ptr scancode

subscribeToKey :: Platform -> Key -> IO ()
subscribeToKey platform key = idunn_platform_key_subscribe platform.ptr key

unsubscribeFromKey :: Platform -> Key -> IO ()
unsubscribeFromKey platform key = idunn_platform_key_unsubscribe platform.ptr key
