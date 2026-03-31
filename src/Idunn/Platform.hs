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
    HasPlatform (..),
    initPlatform,
    initWindow,
    render,
    subscribe,
    tick,
    pattern KeyReturn,
    pattern KeyEscape,
    pattern KeyBackspace,
    pattern KeyTab,
    pattern KeySpace,
    pattern KeyExclaim,
    pattern KeyDblApostrophe,
    pattern KeyHash,
    pattern KeyDollar,
    pattern KeyPercent,
    pattern KeyAmpersand,
    pattern KeyApostrophe,
    pattern KeyLeftParen,
    pattern KeyRightParen,
    pattern KeyAsterisk,
    pattern KeyPlus,
    pattern KeyComma,
    pattern KeyMinus,
    pattern KeyPeriod,
    pattern KeySlash,
    pattern KeyDigit0,
    pattern KeyDigit1,
    pattern KeyDigit2,
    pattern KeyDigit3,
    pattern KeyDigit4,
    pattern KeyDigit5,
    pattern KeyDigit6,
    pattern KeyDigit7,
    pattern KeyDigit8,
    pattern KeyDigit9,
    pattern KeyColon,
    pattern KeySemicolon,
    pattern KeyLess,
    pattern KeyEquals,
    pattern KeyGreater,
    pattern KeyQuestion,
    pattern KeyAt,
    pattern KeyLeftBracket,
    pattern KeyBackslash,
    pattern KeyRightBracket,
    pattern KeyCaret,
    pattern KeyUnderscore,
    pattern KeyGrave,
    pattern KeyA,
    pattern KeyB,
    pattern KeyC,
    pattern KeyD,
    pattern KeyE,
    pattern KeyF,
    pattern KeyG,
    pattern KeyH,
    pattern KeyI,
    pattern KeyJ,
    pattern KeyK,
    pattern KeyL,
    pattern KeyM,
    pattern KeyN,
    pattern KeyO,
    pattern KeyP,
    pattern KeyQ,
    pattern KeyR,
    pattern KeyS,
    pattern KeyT,
    pattern KeyU,
    pattern KeyV,
    pattern KeyW,
    pattern KeyX,
    pattern KeyY,
    pattern KeyZ,
    pattern KeyLeftBrace,
    pattern KeyPipe,
    pattern KeyRightBrace,
    pattern KeyTilde,
    pattern KeyDelete,
    pattern KeyPlusMinus,
    pattern KeyF1,
    pattern KeyF2,
    pattern KeyF3,
    pattern KeyF4,
    pattern KeyF5,
    pattern KeyF6,
    pattern KeyF7,
    pattern KeyF8,
    pattern KeyF9,
    pattern KeyF10,
    pattern KeyF11,
    pattern KeyF12,
    pattern KeyF13,
    pattern KeyF14,
    pattern KeyF15,
    pattern KeyF16,
    pattern KeyF17,
    pattern KeyF18,
    pattern KeyF19,
    pattern KeyF20,
    pattern KeyF21,
    pattern KeyF22,
    pattern KeyF23,
    pattern KeyF24,
    pattern KeyCapsLock,
    pattern KeyPrintScreen,
    pattern KeyScrollLock,
    pattern KeyPause,
    pattern KeyInsert,
    pattern KeyHome,
    pattern KeyPageUp,
    pattern KeyEnd,
    pattern KeyPageDown,
    pattern KeyRight,
    pattern KeyLeft,
    pattern KeyDown,
    pattern KeyUp,
    pattern KeyNumLockClear,
    pattern KeyApplication,
    pattern KeyPower,
    pattern KeyExecute,
    pattern KeyHelp,
    pattern KeyMenu,
    pattern KeySelect,
    pattern KeyStop,
    pattern KeyAgain,
    pattern KeyUndo,
    pattern KeyCut,
    pattern KeyCopy,
    pattern KeyPaste,
    pattern KeyFind,
    pattern KeyAltErase,
    pattern KeySysReq,
    pattern KeyCancel,
    pattern KeyClear,
    pattern KeyPrior,
    pattern KeyReturn2,
    pattern KeySeparator,
    pattern KeyOut,
    pattern KeyOper,
    pattern KeyClearAgain,
    pattern KeyCrSel,
    pattern KeyExSel,
    pattern KeyKp0,
    pattern KeyKp1,
    pattern KeyKp2,
    pattern KeyKp3,
    pattern KeyKp4,
    pattern KeyKp5,
    pattern KeyKp6,
    pattern KeyKp7,
    pattern KeyKp8,
    pattern KeyKp9,
    pattern KeyKpDivide,
    pattern KeyKpMultiply,
    pattern KeyKpMinus,
    pattern KeyKpPlus,
    pattern KeyKpEnter,
    pattern KeyKpPeriod,
    pattern KeyKpEquals,
    pattern KeyKpComma,
    pattern KeyKp00,
    pattern KeyKp000,
    pattern KeyKpEqualsAs400,
    pattern KeyThousandsSeparator,
    pattern KeyDecimalSeparator,
    pattern KeyCurrencyUnit,
    pattern KeyCurrencySubunit,
    pattern KeyKpLeftParen,
    pattern KeyKpRightParen,
    pattern KeyKpLeftBrace,
    pattern KeyKpRightBrace,
    pattern KeyKpTab,
    pattern KeyKpBackspace,
    pattern KeyKpA,
    pattern KeyKpB,
    pattern KeyKpC,
    pattern KeyKpD,
    pattern KeyKpE,
    pattern KeyKpF,
    pattern KeyKpXor,
    pattern KeyKpPower,
    pattern KeyKpPercent,
    pattern KeyKpLess,
    pattern KeyKpGreater,
    pattern KeyKpAmpersand,
    pattern KeyKpDblAmpersand,
    pattern KeyKpVerticalBar,
    pattern KeyKpDblVerticalBar,
    pattern KeyKpColon,
    pattern KeyKpHash,
    pattern KeyKpSpace,
    pattern KeyKpAt,
    pattern KeyKpExclam,
    pattern KeyKpMemStore,
    pattern KeyKpMemRecall,
    pattern KeyKpMemClear,
    pattern KeyKpMemAdd,
    pattern KeyKpMemSubtract,
    pattern KeyKpMemMultiply,
    pattern KeyKpMemDivide,
    pattern KeyKpPlusMinus,
    pattern KeyKpClear,
    pattern KeyKpClearEntry,
    pattern KeyKpBinary,
    pattern KeyKpOctal,
    pattern KeyKpDecimal,
    pattern KeyKpHexadecimal,
    pattern KeyLeftCtrl,
    pattern KeyLeftShift,
    pattern KeyLeftAlt,
    pattern KeyLeftGui,
    pattern KeyRightCtrl,
    pattern KeyRightShift,
    pattern KeyRightAlt,
    pattern KeyRightGui,
    pattern KeyMode,
    pattern KeySleep,
    pattern KeyWake,
    pattern KeyChannelIncrement,
    pattern KeyChannelDecrement,
    pattern KeyMediaPlay,
    pattern KeyMediaPause,
    pattern KeyMediaRecord,
    pattern KeyMediaFastForward,
    pattern KeyMediaRewind,
    pattern KeyMediaNextTrack,
    pattern KeyMediaPreviousTrack,
    pattern KeyMediaStop,
    pattern KeyMediaEject,
    pattern KeyMediaPlayPause,
    pattern KeyMediaSelect,
    pattern KeyMute,
    pattern KeyVolumeUp,
    pattern KeyVolumeDown,
    pattern KeyAcNew,
    pattern KeyAcOpen,
    pattern KeyAcClose,
    pattern KeyAcExit,
    pattern KeyAcSave,
    pattern KeyAcPrint,
    pattern KeyAcProperties,
    pattern KeyAcSearch,
    pattern KeyAcHome,
    pattern KeyAcBack,
    pattern KeyAcForward,
    pattern KeyAcStop,
    pattern KeyAcRefresh,
    pattern KeyAcBookmarks,
    pattern KeySoftLeft,
    pattern KeySoftRight,
    pattern KeyCall,
    pattern KeyEndCall,
    pattern KeyLeftTab,
    pattern KeyLevel5Shift,
    pattern KeyMultiKeyCompose,
    pattern KeyLeftMeta,
    pattern KeyRightMeta,
    pattern KeyLeftHyper,
    pattern KeyRightHyper,
    pattern ScancodeA,
    pattern ScancodeB,
    pattern ScancodeC,
    pattern ScancodeD,
    pattern ScancodeE,
    pattern ScancodeF,
    pattern ScancodeG,
    pattern ScancodeH,
    pattern ScancodeI,
    pattern ScancodeJ,
    pattern ScancodeK,
    pattern ScancodeL,
    pattern ScancodeM,
    pattern ScancodeN,
    pattern ScancodeO,
    pattern ScancodeP,
    pattern ScancodeQ,
    pattern ScancodeR,
    pattern ScancodeS,
    pattern ScancodeT,
    pattern ScancodeU,
    pattern ScancodeV,
    pattern ScancodeW,
    pattern ScancodeX,
    pattern ScancodeY,
    pattern ScancodeZ,
    pattern ScancodeDigit1,
    pattern ScancodeDigit2,
    pattern ScancodeDigit3,
    pattern ScancodeDigit4,
    pattern ScancodeDigit5,
    pattern ScancodeDigit6,
    pattern ScancodeDigit7,
    pattern ScancodeDigit8,
    pattern ScancodeDigit9,
    pattern ScancodeDigit0,
    pattern ScancodeReturn,
    pattern ScancodeEscape,
    pattern ScancodeBackspace,
    pattern ScancodeTab,
    pattern ScancodeSpace,
    pattern ScancodeMinus,
    pattern ScancodeEquals,
    pattern ScancodeLeftBracket,
    pattern ScancodeRightBracket,
    pattern ScancodeBackslash,
    pattern ScancodeNonUsHash,
    pattern ScancodeSemicolon,
    pattern ScancodeApostrophe,
    pattern ScancodeGrave,
    pattern ScancodeComma,
    pattern ScancodePeriod,
    pattern ScancodeSlash,
    pattern ScancodeCapsLock,
    pattern ScancodeF1,
    pattern ScancodeF2,
    pattern ScancodeF3,
    pattern ScancodeF4,
    pattern ScancodeF5,
    pattern ScancodeF6,
    pattern ScancodeF7,
    pattern ScancodeF8,
    pattern ScancodeF9,
    pattern ScancodeF10,
    pattern ScancodeF11,
    pattern ScancodeF12,
    pattern ScancodeF13,
    pattern ScancodeF14,
    pattern ScancodeF15,
    pattern ScancodeF16,
    pattern ScancodeF17,
    pattern ScancodeF18,
    pattern ScancodeF19,
    pattern ScancodeF20,
    pattern ScancodeF21,
    pattern ScancodeF22,
    pattern ScancodeF23,
    pattern ScancodeF24,
    pattern ScancodePrintScreen,
    pattern ScancodeScrollLock,
    pattern ScancodePause,
    pattern ScancodeInsert,
    pattern ScancodeHome,
    pattern ScancodePageUp,
    pattern ScancodeDelete,
    pattern ScancodeEnd,
    pattern ScancodePageDown,
    pattern ScancodeRight,
    pattern ScancodeLeft,
    pattern ScancodeDown,
    pattern ScancodeUp,
    pattern ScancodeNumLockClear,
    pattern ScancodeKpDivide,
    pattern ScancodeKpMultiply,
    pattern ScancodeKpMinus,
    pattern ScancodeKpPlus,
    pattern ScancodeKpEnter,
    pattern ScancodeKp1,
    pattern ScancodeKp2,
    pattern ScancodeKp3,
    pattern ScancodeKp4,
    pattern ScancodeKp5,
    pattern ScancodeKp6,
    pattern ScancodeKp7,
    pattern ScancodeKp8,
    pattern ScancodeKp9,
    pattern ScancodeKp0,
    pattern ScancodeKpPeriod,
    pattern ScancodeKpEquals,
    pattern ScancodeKpComma,
    pattern ScancodeKpEqualsAs400,
    pattern ScancodeKp00,
    pattern ScancodeKp000,
    pattern ScancodeKpLeftParen,
    pattern ScancodeKpRightParen,
    pattern ScancodeKpLeftBrace,
    pattern ScancodeKpRightBrace,
    pattern ScancodeKpTab,
    pattern ScancodeKpBackspace,
    pattern ScancodeKpA,
    pattern ScancodeKpB,
    pattern ScancodeKpC,
    pattern ScancodeKpD,
    pattern ScancodeKpE,
    pattern ScancodeKpF,
    pattern ScancodeKpXor,
    pattern ScancodeKpPower,
    pattern ScancodeKpPercent,
    pattern ScancodeKpLess,
    pattern ScancodeKpGreater,
    pattern ScancodeKpAmpersand,
    pattern ScancodeKpDblAmpersand,
    pattern ScancodeKpVerticalBar,
    pattern ScancodeKpDblVerticalBar,
    pattern ScancodeKpColon,
    pattern ScancodeKpHash,
    pattern ScancodeKpSpace,
    pattern ScancodeKpAt,
    pattern ScancodeKpExclam,
    pattern ScancodeKpMemStore,
    pattern ScancodeKpMemRecall,
    pattern ScancodeKpMemClear,
    pattern ScancodeKpMemAdd,
    pattern ScancodeKpMemSubtract,
    pattern ScancodeKpMemMultiply,
    pattern ScancodeKpMemDivide,
    pattern ScancodeKpPlusMinus,
    pattern ScancodeKpClear,
    pattern ScancodeKpClearEntry,
    pattern ScancodeKpBinary,
    pattern ScancodeKpOctal,
    pattern ScancodeKpDecimal,
    pattern ScancodeKpHexadecimal,
    pattern ScancodeNonUsBackslash,
    pattern ScancodeInternational1,
    pattern ScancodeInternational2,
    pattern ScancodeInternational3,
    pattern ScancodeInternational4,
    pattern ScancodeInternational5,
    pattern ScancodeInternational6,
    pattern ScancodeInternational7,
    pattern ScancodeInternational8,
    pattern ScancodeInternational9,
    pattern ScancodeLang1,
    pattern ScancodeLang2,
    pattern ScancodeLang3,
    pattern ScancodeLang4,
    pattern ScancodeLang5,
    pattern ScancodeLang6,
    pattern ScancodeLang7,
    pattern ScancodeLang8,
    pattern ScancodeLang9,
    pattern ScancodeApplication,
    pattern ScancodePower,
    pattern ScancodeExecute,
    pattern ScancodeHelp,
    pattern ScancodeMenu,
    pattern ScancodeSelect,
    pattern ScancodeStop,
    pattern ScancodeAgain,
    pattern ScancodeUndo,
    pattern ScancodeCut,
    pattern ScancodeCopy,
    pattern ScancodePaste,
    pattern ScancodeFind,
    pattern ScancodeMute,
    pattern ScancodeVolumeUp,
    pattern ScancodeVolumeDown,
    pattern ScancodeAltErase,
    pattern ScancodeSysReq,
    pattern ScancodeCancel,
    pattern ScancodeClear,
    pattern ScancodePrior,
    pattern ScancodeReturn2,
    pattern ScancodeSeparator,
    pattern ScancodeOut,
    pattern ScancodeOper,
    pattern ScancodeClearAgain,
    pattern ScancodeCrSel,
    pattern ScancodeExSel,
    pattern ScancodeThousandsSeparator,
    pattern ScancodeDecimalSeparator,
    pattern ScancodeCurrencyUnit,
    pattern ScancodeCurrencySubunit,
    pattern ScancodeLeftCtrl,
    pattern ScancodeLeftShift,
    pattern ScancodeLeftAlt,
    pattern ScancodeLeftGui,
    pattern ScancodeRightCtrl,
    pattern ScancodeRightShift,
    pattern ScancodeRightAlt,
    pattern ScancodeRightGui,
    pattern ScancodeMode,
    pattern ScancodeSleep,
    pattern ScancodeWake,
    pattern ScancodeChannelIncrement,
    pattern ScancodeChannelDecrement,
    pattern ScancodeMediaPlay,
    pattern ScancodeMediaPause,
    pattern ScancodeMediaRecord,
    pattern ScancodeMediaFastForward,
    pattern ScancodeMediaRewind,
    pattern ScancodeMediaNextTrack,
    pattern ScancodeMediaPreviousTrack,
    pattern ScancodeMediaStop,
    pattern ScancodeMediaEject,
    pattern ScancodeMediaPlayPause,
    pattern ScancodeMediaSelect,
    pattern ScancodeAcNew,
    pattern ScancodeAcOpen,
    pattern ScancodeAcClose,
    pattern ScancodeAcExit,
    pattern ScancodeAcSave,
    pattern ScancodeAcPrint,
    pattern ScancodeAcProperties,
    pattern ScancodeAcSearch,
    pattern ScancodeAcHome,
    pattern ScancodeAcBack,
    pattern ScancodeAcForward,
    pattern ScancodeAcStop,
    pattern ScancodeAcRefresh,
    pattern ScancodeAcBookmarks,
    pattern ScancodeSoftLeft,
    pattern ScancodeSoftRight,
    pattern ScancodeCall,
    pattern ScancodeEndCall,
  )
where

import Control.Monad (unless, when)
import Control.Monad.Reader
import Data.Dependent.Sum
import Data.Foldable (forM_)
import Data.Functor.Identity (Identity (..))
import Data.IntMap.Strict (IntMap)
import Data.IntMap.Strict qualified as IntMap
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Proxy
import Data.Text hiding (foldr)
import Data.Text.Foreign (withCString)
import Data.Unique (hashUnique, newUnique)
import Data.Void
import Foreign
import Foreign.C.ConstPtr
import Idunn.Gpu
import Idunn.Platform.FFI
import Reflex
import Reflex.Host.Class
import UnliftIO
import UnliftIO.Resource

data Platform t = Platform
  { ptr :: Ptr Void,
    ptrEventCount :: Ptr Word32,
    ptrEventsPtr :: Ptr (Ptr Idunn_platform_event),
    eventsRef :: IORef [DSum (EventTrigger t) Identity],
    keySubscribers :: Subscriptions t Key,
    scancodeSubscribers :: Subscriptions t Scancode
  }

class HasPlatform t env where
  getPlatform :: env -> (Platform t)

initPlatform :: (MonadResource m) => m (Platform t)
initPlatform = snd <$> allocate up down
  where
    up = alloca $ \ptrPlatformPtr ->
      alloca $ \ptrConfig -> do
        ptrEventCount <- malloc
        ptrEventsPtr <- malloc
        poke ptrConfig $ Idunn_platform_config ptrEventCount ptrEventsPtr
        idunn_platform_init ptrConfig ptrPlatformPtr
        ptrPlatform <- peek ptrPlatformPtr
        eventsRef <- newIORef mempty
        keySubscribers <- newIORef mempty
        scancodeSubscribers <- newIORef mempty
        pure $
          Platform
            { ptr = ptrPlatform,
              ptrEventCount = ptrEventCount,
              ptrEventsPtr = ptrEventsPtr,
              eventsRef = eventsRef,
              keySubscribers = keySubscribers,
              scancodeSubscribers = scancodeSubscribers
            }
    down platform = do
      writeIORef platform.keySubscribers mempty
      writeIORef platform.scancodeSubscribers mempty
      idunn_platform_uninit platform.ptr
      free platform.ptrEventCount
      free platform.ptrEventsPtr

tick :: forall t m. (MonadIO m) => (Platform t) -> m Bool
tick platform = do
  shouldQuitRef <- newIORef False
  liftIO $ idunn_platform_tick platform.ptr
  eventCount <- liftIO $ peek platform.ptrEventCount
  unless (eventCount == 0) $ do
    ptrEvents <- liftIO $ peek platform.ptrEventsPtr
    events <- liftIO $ peekArray (fromIntegral eventCount) ptrEvents
    forM_ events $ \event -> do
      case idunn_platform_event_type event of
        KeyEvent -> extractEventValue event $ Proxy @Key
        ScancodeEvent -> extractEventValue event $ Proxy @Scancode
        QuitEvent -> writeIORef shouldQuitRef True
        _ -> pure ()
  readIORef shouldQuitRef
  where
    extractEventValue :: forall item. (Subscribe item) => Idunn_platform_event -> Proxy item -> m ()
    extractEventValue event _ = do
      subscribers <- readIORef $ subscribersRef @item platform
      let (item, value) = extractValue event
      case Map.lookup item subscribers of
        Nothing -> pure ()
        Just eventSubscribers -> modifyIORef' platform.eventsRef $ \xs -> foldr (\eventTrigger -> (:) (eventTrigger :=> Identity value)) xs eventSubscribers

data Window = Window
  { ptr :: Ptr Void
  }

initWindow :: (MonadResource m) => (Platform t) -> Gpu -> Text -> Word32 -> Word32 -> m Window
initWindow platform gpu title width height = snd <$> allocate up down
  where
    up = withCString title $ \c'title ->
      alloca $ \pWindow ->
        alloca $ \pConfig -> do
          let config = Idunn_window_config platform.ptr gpu.ptr (ConstPtr c'title) width height
          poke pConfig config
          idunn_platform_window_init pConfig pWindow
          Window <$> peek pWindow
    down window = idunn_platform_window_uninit window.ptr

render :: (MonadIO m) => Window -> GpuWorld vertex -> m ()
render window world = liftIO $ idunn_platform_window_render window.ptr world.handle

type Subscriptions t a = IORef (Map a (IntMap (EventTrigger t (Value a))))

class (Ord a) => Subscribe a where
  type Value a
  subscribersRef :: Platform t -> Subscriptions t a
  c'subscribe :: Ptr Void -> a -> IO ()
  c'unsubscribe :: Ptr Void -> a -> IO ()
  extractValue :: Idunn_platform_event -> (a, Value a)

instance Subscribe Key where
  type Value Key = Bool
  subscribersRef = keySubscribers
  c'subscribe = idunn_platform_key_subscribe
  c'unsubscribe = idunn_platform_key_unsubscribe
  extractValue event = do
    let keyEvent = get_idunn_platform_event_payload_key $ idunn_platform_event_payload event
    let key = idunn_platform_key_event_key keyEvent
    (key, toBool $ idunn_platform_key_event_value keyEvent)

instance Subscribe Scancode where
  type Value Scancode = Bool
  subscribersRef = scancodeSubscribers
  c'subscribe = idunn_platform_scancode_subscribe
  c'unsubscribe = idunn_platform_scancode_unsubscribe
  extractValue event = do
    let scancodeEvent = get_idunn_platform_event_payload_scancode $ idunn_platform_event_payload event
    let scancode = idunn_platform_scancode_event_scancode scancodeEvent
    (scancode, toBool $ idunn_platform_scancode_event_value scancodeEvent)

subscribe :: forall t env item m. (Subscribe item, MonadReflexCreateTrigger t m, HasPlatform t env, MonadReader env m) => item -> m (Event t (Value item))
subscribe item = do
  platform :: Platform t <- asks getPlatform
  newEventWithTrigger $ \eventTrigger -> do
    uniq <- liftIO newUnique
    let subscription = hashUnique uniq -- TODO: handle collision
    shouldSubscribe <- atomicModifyIORef' (subscribersRef platform) $ \currentSubscribers ->
      case Map.lookup item currentSubscribers of
        Just triggerMap -> (Map.insert item (IntMap.insert subscription eventTrigger triggerMap) currentSubscribers, False)
        Nothing -> (Map.insert item (IntMap.singleton subscription eventTrigger) currentSubscribers, True)
    when shouldSubscribe $ c'subscribe platform.ptr item
    pure $ do
      shouldUnsubscribe <- atomicModifyIORef' (subscribersRef platform) $ \currentSubscribers -> do
        let triggerMap = Map.findWithDefault IntMap.empty item currentSubscribers
            newTriggerMap = IntMap.delete subscription triggerMap
         in if IntMap.null newTriggerMap
              then (Map.delete item currentSubscribers, True)
              else (Map.insert item newTriggerMap currentSubscribers, False)
      when shouldUnsubscribe $ c'unsubscribe platform.ptr item
