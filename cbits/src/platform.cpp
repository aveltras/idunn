/*
 * Copyright (C) 2026 Romain Viallard
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Affero General Public License as
 * published by the Free Software Foundation, either version 3 of the
 * License, or (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU Affero General Public License for more details.
 *
 * You should have received a copy of the GNU Affero General Public License
 * along with this program. If not, see <http://www.gnu.org/licenses/>.
 */

#include "platform.hpp"
#include "logger.hpp"
#include "pool.hpp"

#include <SDL3/SDL.h>
#include <cassert>
#include <glm/glm.hpp>
#include <glm/matrix.hpp>
#include <glm/ext.hpp>

extern "C" {
void idunn_platform_init(idunn_platform_config *config, void **pPlatform) {
  *pPlatform = new Platform(config->pDeltaTime, config->pEventCount, config->ppEvent);
}

void idunn_platform_uninit(void *platform) {
  delete static_cast<Platform *>(platform);
}

void idunn_platform_window_init(idunn_window_config *config, void **pWindow) {
  *pWindow = new Window(config);
}

void idunn_platform_tick(void *platform) {
  static_cast<Platform *>(platform)->tick();
}

void idunn_platform_key_subscribe(void *platform, Key key) {
  static_cast<Platform *>(platform)->subscribe(key);
}

void idunn_platform_key_unsubscribe(void *platform, Key key) {
  static_cast<Platform *>(platform)->unsubscribe(key);
}

void idunn_platform_scancode_subscribe(void *platform, Scancode scancode) {
  static_cast<Platform *>(platform)->subscribe(scancode);
}

void idunn_platform_scancode_unsubscribe(void *platform, Scancode scancode) {
  static_cast<Platform *>(platform)->unsubscribe(scancode);
}

void idunn_platform_window_uninit(void *window) {
  delete static_cast<Window *>(window);
}

void idunn_platform_window_render(void *window, uint64_t gpuWorld) {
  static_cast<Window *>(window)->render(Handle<Gpu::World>(gpuWorld));
}
}

Platform::Platform(float *pDeltaTime, uint32_t *pEventCount, idunn_platform_event **ppEvent)
    : pDeltaTime(pDeltaTime),
      pEventCount(pEventCount),
      ppEvent(ppEvent) {
  LOG_DEBUG("Platform");
  SDL_Init(SDL_INIT_VIDEO | SDL_INIT_GAMEPAD);
  ticks = SDL_GetPerformanceCounter();
  frequency = SDL_GetPerformanceFrequency();
}

Platform::~Platform() {
  SDL_Quit();
  LOG_DEBUG("~Platform");
}

auto Platform::tick() -> void {
  tickEvents.clear();

  uint64_t currentTicks = SDL_GetPerformanceCounter();
  *pDeltaTime = (float)(currentTicks - ticks) / (float)frequency;

  ticks = currentTicks;

  SDL_Event sdlEvent;
  while (SDL_PollEvent(&sdlEvent)) {
    switch (sdlEvent.type) {
    case SDL_EVENT_QUIT: {
      idunn_platform_event event = {};
      event.type = QuitEvent;
      tickEvents.emplace_back(event);
    } break;
    case SDL_EVENT_KEY_DOWN:
    case SDL_EVENT_KEY_UP: {
      if (!sdlEvent.key.repeat) {
        if (auto subscription = keys.find(sdlEvent.key.key); subscription != keys.end()) {
          idunn_platform_event event = {};
          event.type = KeyEvent;
          event.payload.key.key = subscription->second;
          event.payload.key.value = sdlEvent.key.down;
          tickEvents.emplace_back(event);
        }

        if (auto subscription = scancodes.find(sdlEvent.key.scancode); subscription != scancodes.end()) {
          idunn_platform_event event = {};
          event.type = ScancodeEvent;
          event.payload.scancode.scancode = subscription->second;
          event.payload.scancode.value = sdlEvent.key.down;
          tickEvents.emplace_back(event);
        }
      }
    } break;
    default:
      break;
    }
  }

  *pEventCount = tickEvents.size();
  *ppEvent = tickEvents.data();
}

auto Platform::subscribe(Key key) -> void {
  // LOG_DEBUG("Subscribing to key: %i", key);
  keys[mapKey(key)] = key;
}

auto Platform::subscribe(Scancode scancode) -> void {
  // LOG_DEBUG("Subscribing to scancode: %i", scancode);
  scancodes[mapScancode(scancode)] = scancode;
}

auto Platform::unsubscribe(Key key) -> void {
  // LOG_DEBUG("Unsubscribing from key: %i", key);
  keys.erase(mapKey(key));
}

auto Platform::unsubscribe(Scancode scancode) -> void {
  // LOG_DEBUG("Unsubscribing from scancode: %i", scancode);
  scancodes.erase(mapScancode(scancode));
}

constexpr auto Platform::getScancodeMapping() -> std::array<SDL_Scancode, SDL_SCANCODE_COUNT> {
  std::array<SDL_Scancode, SDL_SCANCODE_COUNT> mapping{};

  mapping[ScancodeA] = SDL_SCANCODE_A;
  mapping[ScancodeB] = SDL_SCANCODE_B;
  mapping[ScancodeC] = SDL_SCANCODE_C;
  mapping[ScancodeD] = SDL_SCANCODE_D;
  mapping[ScancodeE] = SDL_SCANCODE_E;
  mapping[ScancodeF] = SDL_SCANCODE_F;
  mapping[ScancodeG] = SDL_SCANCODE_G;
  mapping[ScancodeH] = SDL_SCANCODE_H;
  mapping[ScancodeI] = SDL_SCANCODE_I;
  mapping[ScancodeJ] = SDL_SCANCODE_J;
  mapping[ScancodeK] = SDL_SCANCODE_K;
  mapping[ScancodeL] = SDL_SCANCODE_L;
  mapping[ScancodeM] = SDL_SCANCODE_M;
  mapping[ScancodeN] = SDL_SCANCODE_N;
  mapping[ScancodeO] = SDL_SCANCODE_O;
  mapping[ScancodeP] = SDL_SCANCODE_P;
  mapping[ScancodeQ] = SDL_SCANCODE_Q;
  mapping[ScancodeR] = SDL_SCANCODE_R;
  mapping[ScancodeS] = SDL_SCANCODE_S;
  mapping[ScancodeT] = SDL_SCANCODE_T;
  mapping[ScancodeU] = SDL_SCANCODE_U;
  mapping[ScancodeV] = SDL_SCANCODE_V;
  mapping[ScancodeW] = SDL_SCANCODE_W;
  mapping[ScancodeX] = SDL_SCANCODE_X;
  mapping[ScancodeY] = SDL_SCANCODE_Y;
  mapping[ScancodeZ] = SDL_SCANCODE_Z;
  mapping[ScancodeDigit1] = SDL_SCANCODE_1;
  mapping[ScancodeDigit2] = SDL_SCANCODE_2;
  mapping[ScancodeDigit3] = SDL_SCANCODE_3;
  mapping[ScancodeDigit4] = SDL_SCANCODE_4;
  mapping[ScancodeDigit5] = SDL_SCANCODE_5;
  mapping[ScancodeDigit6] = SDL_SCANCODE_6;
  mapping[ScancodeDigit7] = SDL_SCANCODE_7;
  mapping[ScancodeDigit8] = SDL_SCANCODE_8;
  mapping[ScancodeDigit9] = SDL_SCANCODE_9;
  mapping[ScancodeDigit0] = SDL_SCANCODE_0;
  mapping[ScancodeReturn] = SDL_SCANCODE_RETURN;
  mapping[ScancodeEscape] = SDL_SCANCODE_ESCAPE;
  mapping[ScancodeBackspace] = SDL_SCANCODE_BACKSPACE;
  mapping[ScancodeTab] = SDL_SCANCODE_TAB;
  mapping[ScancodeSpace] = SDL_SCANCODE_SPACE;
  mapping[ScancodeMinus] = SDL_SCANCODE_MINUS;
  mapping[ScancodeEquals] = SDL_SCANCODE_EQUALS;
  mapping[ScancodeLeftBracket] = SDL_SCANCODE_LEFTBRACKET;
  mapping[ScancodeRightBracket] = SDL_SCANCODE_RIGHTBRACKET;
  mapping[ScancodeBackslash] = SDL_SCANCODE_BACKSLASH;
  mapping[ScancodeNonUsHash] = SDL_SCANCODE_NONUSHASH;
  mapping[ScancodeSemicolon] = SDL_SCANCODE_SEMICOLON;
  mapping[ScancodeApostrophe] = SDL_SCANCODE_APOSTROPHE;
  mapping[ScancodeGrave] = SDL_SCANCODE_GRAVE;
  mapping[ScancodeComma] = SDL_SCANCODE_COMMA;
  mapping[ScancodePeriod] = SDL_SCANCODE_PERIOD;
  mapping[ScancodeSlash] = SDL_SCANCODE_SLASH;
  mapping[ScancodeCapsLock] = SDL_SCANCODE_CAPSLOCK;
  mapping[ScancodeF1] = SDL_SCANCODE_F1;
  mapping[ScancodeF2] = SDL_SCANCODE_F2;
  mapping[ScancodeF3] = SDL_SCANCODE_F3;
  mapping[ScancodeF4] = SDL_SCANCODE_F4;
  mapping[ScancodeF5] = SDL_SCANCODE_F5;
  mapping[ScancodeF6] = SDL_SCANCODE_F6;
  mapping[ScancodeF7] = SDL_SCANCODE_F7;
  mapping[ScancodeF8] = SDL_SCANCODE_F8;
  mapping[ScancodeF9] = SDL_SCANCODE_F9;
  mapping[ScancodeF10] = SDL_SCANCODE_F10;
  mapping[ScancodeF11] = SDL_SCANCODE_F11;
  mapping[ScancodeF12] = SDL_SCANCODE_F12;
  mapping[ScancodeF13] = SDL_SCANCODE_F13;
  mapping[ScancodeF14] = SDL_SCANCODE_F14;
  mapping[ScancodeF15] = SDL_SCANCODE_F15;
  mapping[ScancodeF16] = SDL_SCANCODE_F16;
  mapping[ScancodeF17] = SDL_SCANCODE_F17;
  mapping[ScancodeF18] = SDL_SCANCODE_F18;
  mapping[ScancodeF19] = SDL_SCANCODE_F19;
  mapping[ScancodeF20] = SDL_SCANCODE_F20;
  mapping[ScancodeF21] = SDL_SCANCODE_F21;
  mapping[ScancodeF22] = SDL_SCANCODE_F22;
  mapping[ScancodeF23] = SDL_SCANCODE_F23;
  mapping[ScancodeF24] = SDL_SCANCODE_F24;
  mapping[ScancodePrintScreen] = SDL_SCANCODE_PRINTSCREEN;
  mapping[ScancodeScrollLock] = SDL_SCANCODE_SCROLLLOCK;
  mapping[ScancodePause] = SDL_SCANCODE_PAUSE;
  mapping[ScancodeInsert] = SDL_SCANCODE_INSERT;
  mapping[ScancodeHome] = SDL_SCANCODE_HOME;
  mapping[ScancodePageUp] = SDL_SCANCODE_PAGEUP;
  mapping[ScancodeDelete] = SDL_SCANCODE_DELETE;
  mapping[ScancodeEnd] = SDL_SCANCODE_END;
  mapping[ScancodePageDown] = SDL_SCANCODE_PAGEDOWN;
  mapping[ScancodeRight] = SDL_SCANCODE_RIGHT;
  mapping[ScancodeLeft] = SDL_SCANCODE_LEFT;
  mapping[ScancodeDown] = SDL_SCANCODE_DOWN;
  mapping[ScancodeUp] = SDL_SCANCODE_UP;
  mapping[ScancodeNumLockClear] = SDL_SCANCODE_NUMLOCKCLEAR;
  mapping[ScancodeKpDivide] = SDL_SCANCODE_KP_DIVIDE;
  mapping[ScancodeKpMultiply] = SDL_SCANCODE_KP_MULTIPLY;
  mapping[ScancodeKpMinus] = SDL_SCANCODE_KP_MINUS;
  mapping[ScancodeKpPlus] = SDL_SCANCODE_KP_PLUS;
  mapping[ScancodeKpEnter] = SDL_SCANCODE_KP_ENTER;
  mapping[ScancodeKp1] = SDL_SCANCODE_KP_1;
  mapping[ScancodeKp2] = SDL_SCANCODE_KP_2;
  mapping[ScancodeKp3] = SDL_SCANCODE_KP_3;
  mapping[ScancodeKp4] = SDL_SCANCODE_KP_4;
  mapping[ScancodeKp5] = SDL_SCANCODE_KP_5;
  mapping[ScancodeKp6] = SDL_SCANCODE_KP_6;
  mapping[ScancodeKp7] = SDL_SCANCODE_KP_7;
  mapping[ScancodeKp8] = SDL_SCANCODE_KP_8;
  mapping[ScancodeKp9] = SDL_SCANCODE_KP_9;
  mapping[ScancodeKp0] = SDL_SCANCODE_KP_0;
  mapping[ScancodeKpPeriod] = SDL_SCANCODE_KP_PERIOD;
  mapping[ScancodeKpEquals] = SDL_SCANCODE_KP_EQUALS;
  mapping[ScancodeKpComma] = SDL_SCANCODE_KP_COMMA;
  mapping[ScancodeKpEqualsAs400] = SDL_SCANCODE_KP_EQUALSAS400;
  mapping[ScancodeKp00] = SDL_SCANCODE_KP_00;
  mapping[ScancodeKp000] = SDL_SCANCODE_KP_000;
  mapping[ScancodeKpLeftParen] = SDL_SCANCODE_KP_LEFTPAREN;
  mapping[ScancodeKpRightParen] = SDL_SCANCODE_KP_RIGHTPAREN;
  mapping[ScancodeKpLeftBrace] = SDL_SCANCODE_KP_LEFTBRACE;
  mapping[ScancodeKpRightBrace] = SDL_SCANCODE_KP_RIGHTBRACE;
  mapping[ScancodeKpTab] = SDL_SCANCODE_KP_TAB;
  mapping[ScancodeKpBackspace] = SDL_SCANCODE_KP_BACKSPACE;
  mapping[ScancodeKpA] = SDL_SCANCODE_KP_A;
  mapping[ScancodeKpB] = SDL_SCANCODE_KP_B;
  mapping[ScancodeKpC] = SDL_SCANCODE_KP_C;
  mapping[ScancodeKpD] = SDL_SCANCODE_KP_D;
  mapping[ScancodeKpE] = SDL_SCANCODE_KP_E;
  mapping[ScancodeKpF] = SDL_SCANCODE_KP_F;
  mapping[ScancodeKpXor] = SDL_SCANCODE_KP_XOR;
  mapping[ScancodeKpPower] = SDL_SCANCODE_KP_POWER;
  mapping[ScancodeKpPercent] = SDL_SCANCODE_KP_PERCENT;
  mapping[ScancodeKpLess] = SDL_SCANCODE_KP_LESS;
  mapping[ScancodeKpGreater] = SDL_SCANCODE_KP_GREATER;
  mapping[ScancodeKpAmpersand] = SDL_SCANCODE_KP_AMPERSAND;
  mapping[ScancodeKpDblAmpersand] = SDL_SCANCODE_KP_DBLAMPERSAND;
  mapping[ScancodeKpVerticalBar] = SDL_SCANCODE_KP_VERTICALBAR;
  mapping[ScancodeKpDblVerticalBar] = SDL_SCANCODE_KP_DBLVERTICALBAR;
  mapping[ScancodeKpColon] = SDL_SCANCODE_KP_COLON;
  mapping[ScancodeKpHash] = SDL_SCANCODE_KP_HASH;
  mapping[ScancodeKpSpace] = SDL_SCANCODE_KP_SPACE;
  mapping[ScancodeKpAt] = SDL_SCANCODE_KP_AT;
  mapping[ScancodeKpExclam] = SDL_SCANCODE_KP_EXCLAM;
  mapping[ScancodeKpMemStore] = SDL_SCANCODE_KP_MEMSTORE;
  mapping[ScancodeKpMemRecall] = SDL_SCANCODE_KP_MEMRECALL;
  mapping[ScancodeKpMemClear] = SDL_SCANCODE_KP_MEMCLEAR;
  mapping[ScancodeKpMemAdd] = SDL_SCANCODE_KP_MEMADD;
  mapping[ScancodeKpMemSubtract] = SDL_SCANCODE_KP_MEMSUBTRACT;
  mapping[ScancodeKpMemMultiply] = SDL_SCANCODE_KP_MEMMULTIPLY;
  mapping[ScancodeKpMemDivide] = SDL_SCANCODE_KP_MEMDIVIDE;
  mapping[ScancodeKpPlusMinus] = SDL_SCANCODE_KP_PLUSMINUS;
  mapping[ScancodeKpClear] = SDL_SCANCODE_KP_CLEAR;
  mapping[ScancodeKpClearEntry] = SDL_SCANCODE_KP_CLEARENTRY;
  mapping[ScancodeKpBinary] = SDL_SCANCODE_KP_BINARY;
  mapping[ScancodeKpOctal] = SDL_SCANCODE_KP_OCTAL;
  mapping[ScancodeKpDecimal] = SDL_SCANCODE_KP_DECIMAL;
  mapping[ScancodeKpHexadecimal] = SDL_SCANCODE_KP_HEXADECIMAL;
  mapping[ScancodeNonUsBackslash] = SDL_SCANCODE_NONUSBACKSLASH;
  mapping[ScancodeInternational1] = SDL_SCANCODE_INTERNATIONAL1;
  mapping[ScancodeInternational2] = SDL_SCANCODE_INTERNATIONAL2;
  mapping[ScancodeInternational3] = SDL_SCANCODE_INTERNATIONAL3;
  mapping[ScancodeInternational4] = SDL_SCANCODE_INTERNATIONAL4;
  mapping[ScancodeInternational5] = SDL_SCANCODE_INTERNATIONAL5;
  mapping[ScancodeInternational6] = SDL_SCANCODE_INTERNATIONAL6;
  mapping[ScancodeInternational7] = SDL_SCANCODE_INTERNATIONAL7;
  mapping[ScancodeInternational8] = SDL_SCANCODE_INTERNATIONAL8;
  mapping[ScancodeInternational9] = SDL_SCANCODE_INTERNATIONAL9;
  mapping[ScancodeLang1] = SDL_SCANCODE_LANG1;
  mapping[ScancodeLang2] = SDL_SCANCODE_LANG2;
  mapping[ScancodeLang3] = SDL_SCANCODE_LANG3;
  mapping[ScancodeLang4] = SDL_SCANCODE_LANG4;
  mapping[ScancodeLang5] = SDL_SCANCODE_LANG5;
  mapping[ScancodeLang6] = SDL_SCANCODE_LANG6;
  mapping[ScancodeLang7] = SDL_SCANCODE_LANG7;
  mapping[ScancodeLang8] = SDL_SCANCODE_LANG8;
  mapping[ScancodeLang9] = SDL_SCANCODE_LANG9;
  mapping[ScancodeApplication] = SDL_SCANCODE_APPLICATION;
  mapping[ScancodePower] = SDL_SCANCODE_POWER;
  mapping[ScancodeExecute] = SDL_SCANCODE_EXECUTE;
  mapping[ScancodeHelp] = SDL_SCANCODE_HELP;
  mapping[ScancodeMenu] = SDL_SCANCODE_MENU;
  mapping[ScancodeSelect] = SDL_SCANCODE_SELECT;
  mapping[ScancodeStop] = SDL_SCANCODE_STOP;
  mapping[ScancodeAgain] = SDL_SCANCODE_AGAIN;
  mapping[ScancodeUndo] = SDL_SCANCODE_UNDO;
  mapping[ScancodeCut] = SDL_SCANCODE_CUT;
  mapping[ScancodeCopy] = SDL_SCANCODE_COPY;
  mapping[ScancodePaste] = SDL_SCANCODE_PASTE;
  mapping[ScancodeFind] = SDL_SCANCODE_FIND;
  mapping[ScancodeMute] = SDL_SCANCODE_MUTE;
  mapping[ScancodeVolumeUp] = SDL_SCANCODE_VOLUMEUP;
  mapping[ScancodeVolumeDown] = SDL_SCANCODE_VOLUMEDOWN;
  mapping[ScancodeAltErase] = SDL_SCANCODE_ALTERASE;
  mapping[ScancodeSysReq] = SDL_SCANCODE_SYSREQ;
  mapping[ScancodeCancel] = SDL_SCANCODE_CANCEL;
  mapping[ScancodeClear] = SDL_SCANCODE_CLEAR;
  mapping[ScancodePrior] = SDL_SCANCODE_PRIOR;
  mapping[ScancodeReturn2] = SDL_SCANCODE_RETURN2;
  mapping[ScancodeSeparator] = SDL_SCANCODE_SEPARATOR;
  mapping[ScancodeOut] = SDL_SCANCODE_OUT;
  mapping[ScancodeOper] = SDL_SCANCODE_OPER;
  mapping[ScancodeClearAgain] = SDL_SCANCODE_CLEARAGAIN;
  mapping[ScancodeCrSel] = SDL_SCANCODE_CRSEL;
  mapping[ScancodeExSel] = SDL_SCANCODE_EXSEL;
  mapping[ScancodeThousandsSeparator] = SDL_SCANCODE_THOUSANDSSEPARATOR;
  mapping[ScancodeDecimalSeparator] = SDL_SCANCODE_DECIMALSEPARATOR;
  mapping[ScancodeCurrencyUnit] = SDL_SCANCODE_CURRENCYUNIT;
  mapping[ScancodeCurrencySubunit] = SDL_SCANCODE_CURRENCYSUBUNIT;
  mapping[ScancodeLeftCtrl] = SDL_SCANCODE_LCTRL;
  mapping[ScancodeLeftShift] = SDL_SCANCODE_LSHIFT;
  mapping[ScancodeLeftAlt] = SDL_SCANCODE_LALT;
  mapping[ScancodeLeftGui] = SDL_SCANCODE_LGUI;
  mapping[ScancodeRightCtrl] = SDL_SCANCODE_RCTRL;
  mapping[ScancodeRightShift] = SDL_SCANCODE_RSHIFT;
  mapping[ScancodeRightAlt] = SDL_SCANCODE_RALT;
  mapping[ScancodeRightGui] = SDL_SCANCODE_RGUI;
  mapping[ScancodeMode] = SDL_SCANCODE_MODE;
  mapping[ScancodeSleep] = SDL_SCANCODE_SLEEP;
  mapping[ScancodeWake] = SDL_SCANCODE_WAKE;
  mapping[ScancodeChannelIncrement] = SDL_SCANCODE_CHANNEL_INCREMENT;
  mapping[ScancodeChannelDecrement] = SDL_SCANCODE_CHANNEL_DECREMENT;
  mapping[ScancodeMediaPlay] = SDL_SCANCODE_MEDIA_PLAY;
  mapping[ScancodeMediaPause] = SDL_SCANCODE_MEDIA_PAUSE;
  mapping[ScancodeMediaRecord] = SDL_SCANCODE_MEDIA_RECORD;
  mapping[ScancodeMediaFastForward] = SDL_SCANCODE_MEDIA_FAST_FORWARD;
  mapping[ScancodeMediaRewind] = SDL_SCANCODE_MEDIA_REWIND;
  mapping[ScancodeMediaNextTrack] = SDL_SCANCODE_MEDIA_NEXT_TRACK;
  mapping[ScancodeMediaPreviousTrack] = SDL_SCANCODE_MEDIA_PREVIOUS_TRACK;
  mapping[ScancodeMediaStop] = SDL_SCANCODE_MEDIA_STOP;
  mapping[ScancodeMediaEject] = SDL_SCANCODE_MEDIA_EJECT;
  mapping[ScancodeMediaPlayPause] = SDL_SCANCODE_MEDIA_PLAY_PAUSE;
  mapping[ScancodeMediaSelect] = SDL_SCANCODE_MEDIA_SELECT;
  mapping[ScancodeAcNew] = SDL_SCANCODE_AC_NEW;
  mapping[ScancodeAcOpen] = SDL_SCANCODE_AC_OPEN;
  mapping[ScancodeAcClose] = SDL_SCANCODE_AC_CLOSE;
  mapping[ScancodeAcExit] = SDL_SCANCODE_AC_EXIT;
  mapping[ScancodeAcSave] = SDL_SCANCODE_AC_SAVE;
  mapping[ScancodeAcPrint] = SDL_SCANCODE_AC_PRINT;
  mapping[ScancodeAcProperties] = SDL_SCANCODE_AC_PROPERTIES;
  mapping[ScancodeAcSearch] = SDL_SCANCODE_AC_SEARCH;
  mapping[ScancodeAcHome] = SDL_SCANCODE_AC_HOME;
  mapping[ScancodeAcBack] = SDL_SCANCODE_AC_BACK;
  mapping[ScancodeAcForward] = SDL_SCANCODE_AC_FORWARD;
  mapping[ScancodeAcStop] = SDL_SCANCODE_AC_STOP;
  mapping[ScancodeAcRefresh] = SDL_SCANCODE_AC_REFRESH;
  mapping[ScancodeAcBookmarks] = SDL_SCANCODE_AC_BOOKMARKS;
  mapping[ScancodeSoftLeft] = SDL_SCANCODE_SOFTLEFT;
  mapping[ScancodeSoftRight] = SDL_SCANCODE_SOFTRIGHT;
  mapping[ScancodeCall] = SDL_SCANCODE_CALL;
  mapping[ScancodeEndCall] = SDL_SCANCODE_ENDCALL;

  return mapping;
}

auto Platform::mapScancode(Scancode scancode) noexcept -> SDL_Scancode {
  static constexpr auto mapping = getScancodeMapping();

  if (static_cast<uint32_t>(scancode) >= SDL_SCANCODE_COUNT) [[unlikely]] {
    return SDL_SCANCODE_UNKNOWN;
  }

  return mapping[static_cast<size_t>(scancode)];
}

constexpr auto Platform::getKeyMapping() -> std::array<SDL_Keycode, kKeyNumEntries> {
  std::array<SDL_Keycode, kKeyNumEntries> mapping{};

  auto set = [&](SDL_Keycode sdlKey, Key key) -> void {
    mapping[key] = getKeyMappingIndex(sdlKey);
  };

  set(SDLK_RETURN, KeyReturn);
  set(SDLK_ESCAPE, KeyEscape);
  set(SDLK_BACKSPACE, KeyBackspace);
  set(SDLK_TAB, KeyTab);
  set(SDLK_DELETE, KeyDelete);
  set(SDLK_SPACE, KeySpace);
  set(SDLK_EXCLAIM, KeyExclaim);
  set(SDLK_DBLAPOSTROPHE, KeyDblApostrophe);
  set(SDLK_HASH, KeyHash);
  set(SDLK_DOLLAR, KeyDollar);
  set(SDLK_PERCENT, KeyPercent);
  set(SDLK_AMPERSAND, KeyAmpersand);
  set(SDLK_APOSTROPHE, KeyApostrophe);
  set(SDLK_LEFTPAREN, KeyLeftParen);
  set(SDLK_RIGHTPAREN, KeyRightParen);
  set(SDLK_ASTERISK, KeyAsterisk);
  set(SDLK_PLUS, KeyPlus);
  set(SDLK_COMMA, KeyComma);
  set(SDLK_MINUS, KeyMinus);
  set(SDLK_PERIOD, KeyPeriod);
  set(SDLK_SLASH, KeySlash);
  set(SDLK_0, KeyDigit0);
  set(SDLK_1, KeyDigit1);
  set(SDLK_2, KeyDigit2);
  set(SDLK_3, KeyDigit3);
  set(SDLK_4, KeyDigit4);
  set(SDLK_5, KeyDigit5);
  set(SDLK_6, KeyDigit6);
  set(SDLK_7, KeyDigit7);
  set(SDLK_8, KeyDigit8);
  set(SDLK_9, KeyDigit9);
  set(SDLK_COLON, KeyColon);
  set(SDLK_SEMICOLON, KeySemicolon);
  set(SDLK_LESS, KeyLess);
  set(SDLK_EQUALS, KeyEquals);
  set(SDLK_GREATER, KeyGreater);
  set(SDLK_QUESTION, KeyQuestion);
  set(SDLK_AT, KeyAt);
  set(SDLK_LEFTBRACKET, KeyLeftBracket);
  set(SDLK_BACKSLASH, KeyBackslash);
  set(SDLK_RIGHTBRACKET, KeyRightBracket);
  set(SDLK_CARET, KeyCaret);
  set(SDLK_UNDERSCORE, KeyUnderscore);
  set(SDLK_GRAVE, KeyGrave);
  set(SDLK_A, KeyA);
  set(SDLK_B, KeyB);
  set(SDLK_C, KeyC);
  set(SDLK_D, KeyD);
  set(SDLK_E, KeyE);
  set(SDLK_F, KeyF);
  set(SDLK_G, KeyG);
  set(SDLK_H, KeyH);
  set(SDLK_I, KeyI);
  set(SDLK_J, KeyJ);
  set(SDLK_K, KeyK);
  set(SDLK_L, KeyL);
  set(SDLK_M, KeyM);
  set(SDLK_N, KeyN);
  set(SDLK_O, KeyO);
  set(SDLK_P, KeyP);
  set(SDLK_Q, KeyQ);
  set(SDLK_R, KeyR);
  set(SDLK_S, KeyS);
  set(SDLK_T, KeyT);
  set(SDLK_U, KeyU);
  set(SDLK_V, KeyV);
  set(SDLK_W, KeyW);
  set(SDLK_X, KeyX);
  set(SDLK_Y, KeyY);
  set(SDLK_Z, KeyZ);
  set(SDLK_LEFTBRACE, KeyLeftBrace);
  set(SDLK_PIPE, KeyPipe);
  set(SDLK_RIGHTBRACE, KeyRightBrace);
  set(SDLK_TILDE, KeyTilde);
  set(SDLK_PLUSMINUS, KeyPlusMinus);
  set(SDLK_CAPSLOCK, KeyCapsLock);
  set(SDLK_F1, KeyF1);
  set(SDLK_F2, KeyF2);
  set(SDLK_F3, KeyF3);
  set(SDLK_F4, KeyF4);
  set(SDLK_F5, KeyF5);
  set(SDLK_F6, KeyF6);
  set(SDLK_F7, KeyF7);
  set(SDLK_F8, KeyF8);
  set(SDLK_F9, KeyF9);
  set(SDLK_F10, KeyF10);
  set(SDLK_F11, KeyF11);
  set(SDLK_F12, KeyF12);
  set(SDLK_PRINTSCREEN, KeyPrintScreen);
  set(SDLK_SCROLLLOCK, KeyScrollLock);
  set(SDLK_PAUSE, KeyPause);
  set(SDLK_INSERT, KeyInsert);
  set(SDLK_HOME, KeyHome);
  set(SDLK_PAGEUP, KeyPageUp);
  set(SDLK_END, KeyEnd);
  set(SDLK_PAGEDOWN, KeyPageDown);
  set(SDLK_RIGHT, KeyRight);
  set(SDLK_LEFT, KeyLeft);
  set(SDLK_DOWN, KeyDown);
  set(SDLK_UP, KeyUp);
  set(SDLK_NUMLOCKCLEAR, KeyNumLockClear);
  set(SDLK_KP_DIVIDE, KeyKpDivide);
  set(SDLK_KP_MULTIPLY, KeyKpMultiply);
  set(SDLK_KP_MINUS, KeyKpMinus);
  set(SDLK_KP_PLUS, KeyKpPlus);
  set(SDLK_KP_ENTER, KeyKpEnter);
  set(SDLK_KP_1, KeyKp1);
  set(SDLK_KP_2, KeyKp2);
  set(SDLK_KP_3, KeyKp3);
  set(SDLK_KP_4, KeyKp4);
  set(SDLK_KP_5, KeyKp5);
  set(SDLK_KP_6, KeyKp6);
  set(SDLK_KP_7, KeyKp7);
  set(SDLK_KP_8, KeyKp8);
  set(SDLK_KP_9, KeyKp9);
  set(SDLK_KP_0, KeyKp0);
  set(SDLK_KP_PERIOD, KeyKpPeriod);
  set(SDLK_APPLICATION, KeyApplication);
  set(SDLK_POWER, KeyPower);
  set(SDLK_KP_EQUALS, KeyKpEquals);
  set(SDLK_F13, KeyF13);
  set(SDLK_F14, KeyF14);
  set(SDLK_F15, KeyF15);
  set(SDLK_F16, KeyF16);
  set(SDLK_F17, KeyF17);
  set(SDLK_F18, KeyF18);
  set(SDLK_F19, KeyF19);
  set(SDLK_F20, KeyF20);
  set(SDLK_F21, KeyF21);
  set(SDLK_F22, KeyF22);
  set(SDLK_F23, KeyF23);
  set(SDLK_F24, KeyF24);
  set(SDLK_EXECUTE, KeyExecute);
  set(SDLK_HELP, KeyHelp);
  set(SDLK_MENU, KeyMenu);
  set(SDLK_SELECT, KeySelect);
  set(SDLK_STOP, KeyStop);
  set(SDLK_AGAIN, KeyAgain);
  set(SDLK_UNDO, KeyUndo);
  set(SDLK_CUT, KeyCut);
  set(SDLK_COPY, KeyCopy);
  set(SDLK_PASTE, KeyPaste);
  set(SDLK_FIND, KeyFind);
  set(SDLK_MUTE, KeyMute);
  set(SDLK_VOLUMEUP, KeyVolumeUp);
  set(SDLK_VOLUMEDOWN, KeyVolumeDown);
  set(SDLK_KP_COMMA, KeyComma);
  set(SDLK_KP_EQUALSAS400, KeyKpEqualsAs400);
  set(SDLK_ALTERASE, KeyAltErase);
  set(SDLK_SYSREQ, KeySysReq);
  set(SDLK_CANCEL, KeyCancel);
  set(SDLK_CLEAR, KeyClear);
  set(SDLK_PRIOR, KeyPrior);
  set(SDLK_RETURN2, KeyReturn);
  set(SDLK_SEPARATOR, KeySeparator);
  set(SDLK_OUT, KeyOut);
  set(SDLK_OPER, KeyOper);
  set(SDLK_CLEARAGAIN, KeyClearAgain);
  set(SDLK_CRSEL, KeyCrSel);
  set(SDLK_EXSEL, KeyExSel);
  set(SDLK_KP_00, KeyKp00);
  set(SDLK_KP_000, KeyKp000);
  set(SDLK_THOUSANDSSEPARATOR, KeyThousandsSeparator);
  set(SDLK_DECIMALSEPARATOR, KeyDecimalSeparator);
  set(SDLK_CURRENCYUNIT, KeyCurrencyUnit);
  set(SDLK_CURRENCYSUBUNIT, KeyCurrencySubunit);
  set(SDLK_KP_LEFTPAREN, KeyKpLeftParen);
  set(SDLK_KP_RIGHTPAREN, KeyKpRightParen);
  set(SDLK_KP_LEFTBRACE, KeyKpLeftBrace);
  set(SDLK_KP_RIGHTBRACE, KeyKpRightBrace);
  set(SDLK_KP_TAB, KeyKpTab);
  set(SDLK_KP_BACKSPACE, KeyKpBackspace);
  set(SDLK_KP_A, KeyKpA);
  set(SDLK_KP_B, KeyKpB);
  set(SDLK_KP_C, KeyKpC);
  set(SDLK_KP_D, KeyKpD);
  set(SDLK_KP_E, KeyKpE);
  set(SDLK_KP_F, KeyKpF);
  set(SDLK_KP_XOR, KeyKpXor);
  set(SDLK_KP_POWER, KeyKpPower);
  set(SDLK_KP_PERCENT, KeyKpPercent);
  set(SDLK_KP_LESS, KeyKpLess);
  set(SDLK_KP_GREATER, KeyKpGreater);
  set(SDLK_KP_AMPERSAND, KeyKpAmpersand);
  set(SDLK_KP_DBLAMPERSAND, KeyKpAmpersand);
  set(SDLK_KP_VERTICALBAR, KeyKpVerticalBar);
  set(SDLK_KP_DBLVERTICALBAR, KeyKpDblVerticalBar);
  set(SDLK_KP_COLON, KeyKpColon);
  set(SDLK_KP_HASH, KeyKpHash);
  set(SDLK_KP_SPACE, KeyKpSpace);
  set(SDLK_KP_AT, KeyKpAt);
  set(SDLK_KP_EXCLAM, KeyKpExclam);
  set(SDLK_KP_MEMSTORE, KeyKpMemStore);
  set(SDLK_KP_MEMRECALL, KeyKpMemRecall);
  set(SDLK_KP_MEMCLEAR, KeyKpMemClear);
  set(SDLK_KP_MEMADD, KeyKpMemAdd);
  set(SDLK_KP_MEMSUBTRACT, KeyKpMemSubtract);
  set(SDLK_KP_MEMMULTIPLY, KeyKpMemMultiply);
  set(SDLK_KP_MEMDIVIDE, KeyKpMemDivide);
  set(SDLK_KP_PLUSMINUS, KeyKpPlusMinus);
  set(SDLK_KP_CLEAR, KeyKpClear);
  set(SDLK_KP_CLEARENTRY, KeyKpClearEntry);
  set(SDLK_KP_BINARY, KeyKpBinary);
  set(SDLK_KP_OCTAL, KeyKpOctal);
  set(SDLK_KP_DECIMAL, KeyKpDecimal);
  set(SDLK_KP_HEXADECIMAL, KeyKpHexadecimal);
  set(SDLK_LCTRL, KeyLeftCtrl);
  set(SDLK_LSHIFT, KeyLeftShift);
  set(SDLK_LALT, KeyLeftAlt);
  set(SDLK_LGUI, KeyLeftGui);
  set(SDLK_RCTRL, KeyRightCtrl);
  set(SDLK_RSHIFT, KeyRightShift);
  set(SDLK_RALT, KeyRightAlt);
  set(SDLK_RGUI, KeyRightGui);
  set(SDLK_MODE, KeyMode);
  set(SDLK_SLEEP, KeySleep);
  set(SDLK_WAKE, KeyWake);
  set(SDLK_CHANNEL_INCREMENT, KeyChannelIncrement);
  set(SDLK_CHANNEL_DECREMENT, KeyChannelDecrement);
  set(SDLK_MEDIA_PLAY, KeyMediaPlay);
  set(SDLK_MEDIA_PAUSE, KeyMediaPause);
  set(SDLK_MEDIA_RECORD, KeyMediaRecord);
  set(SDLK_MEDIA_FAST_FORWARD, KeyMediaFastForward);
  set(SDLK_MEDIA_REWIND, KeyMediaRewind);
  set(SDLK_MEDIA_NEXT_TRACK, KeyMediaNextTrack);
  set(SDLK_MEDIA_PREVIOUS_TRACK, KeyMediaPreviousTrack);
  set(SDLK_MEDIA_STOP, KeyMediaStop);
  set(SDLK_MEDIA_EJECT, KeyMediaEject);
  set(SDLK_MEDIA_PLAY_PAUSE, KeyMediaPlayPause);
  set(SDLK_MEDIA_SELECT, KeyMediaSelect);
  set(SDLK_AC_NEW, KeyAcNew);
  set(SDLK_AC_OPEN, KeyAcOpen);
  set(SDLK_AC_CLOSE, KeyAcClose);
  set(SDLK_AC_EXIT, KeyAcExit);
  set(SDLK_AC_SAVE, KeyAcSave);
  set(SDLK_AC_PRINT, KeyAcPrint);
  set(SDLK_AC_PROPERTIES, KeyAcProperties);
  set(SDLK_AC_SEARCH, KeyAcSearch);
  set(SDLK_AC_HOME, KeyAcHome);
  set(SDLK_AC_BACK, KeyAcBack);
  set(SDLK_AC_FORWARD, KeyAcForward);
  set(SDLK_AC_STOP, KeyAcStop);
  set(SDLK_AC_REFRESH, KeyAcRefresh);
  set(SDLK_AC_BOOKMARKS, KeyAcBookmarks);
  set(SDLK_SOFTLEFT, KeySoftLeft);
  set(SDLK_SOFTRIGHT, KeySoftRight);
  set(SDLK_CALL, KeyCall);
  set(SDLK_ENDCALL, KeyEndCall);
  set(SDLK_LEFT_TAB, KeyLeftTab);
  set(SDLK_LEVEL5_SHIFT, KeyLevel5Shift);
  set(SDLK_MULTI_KEY_COMPOSE, KeyMultiKeyCompose);
  set(SDLK_LMETA, KeyLeftMeta);
  set(SDLK_RMETA, KeyRightMeta);
  set(SDLK_LHYPER, KeyLeftHyper);
  set(SDLK_RHYPER, KeyRightHyper);

  return mapping;
}

constexpr auto Platform::getKeyMappingIndex(SDL_Keycode keycode) noexcept -> uint32_t {
  if ((keycode & SDLK_EXTENDED_MASK) != 0U) {
    return kSizeBase + kSizeScancode - kMinIndexExtended + (keycode & ~SDLK_EXTENDED_MASK);
  }

  if ((keycode & SDLK_SCANCODE_MASK) != 0U) {
    return kSizeBase - kMinIndexScancode + (keycode & ~SDLK_SCANCODE_MASK);
  }

  return static_cast<uint32_t>(keycode);
}

auto Platform::mapKey(Key keycode) noexcept -> SDL_Keycode {
  static constexpr auto mapping = getKeyMapping();
  const uint32_t index = getKeyMappingIndex(keycode);

  if (index >= kKeyNumEntries) [[unlikely]] {
    return SDLK_UNKNOWN;
  }

  return mapping[static_cast<size_t>(index)];
}

Window::Window(idunn_window_config *config)
    : platform(static_cast<Platform *>(config->platform)),
      gpu(static_cast<Gpu *>(config->gpu)),
      width(config->width),
      height(config->height),
      window(SDL_CreateWindow(config->title, (int)width, (int)height, SDL_WINDOW_VULKAN), SDL_DestroyWindow) {
  LOG_DEBUG("Window");
  Gpu::Surface::Desc surfaceDesc{};
  surfaceDesc.window = window.get();
  surfaceDesc.width = config->width;
  surfaceDesc.height = config->height;
  surface = gpu->create(surfaceDesc);
}

Window::~Window() {
  LOG_DEBUG("~Window");
}

auto Window::render(Handle<Gpu::World> world) -> void {
  auto projection = glm::perspective(glm::radians(60.0F), static_cast<float>(width) / static_cast<float>(height), 0.1F, 10.0F);
  projection *= glm::lookAt(glm::vec3(0.0F, 0.0F, 5.0F), glm::vec3(0.0F, 0.0F, 0.0F), glm::vec3(0.0F, 1.0F, 0.0F));
  gpu->render(surface, world, projection, width, height, 0);
}
