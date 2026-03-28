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

#pragma once

#include <idunn/platform.h>
#include "gpu.hpp"

#include <SDL3/SDL.h>
#include <array>
#include <map>
#include <memory>

static constexpr uint32_t kMaxIndexBase = SDLK_PLUSMINUS;
static constexpr uint32_t kMinIndexScancode = SDLK_CAPSLOCK & ~SDLK_SCANCODE_MASK;
static constexpr uint32_t kMinIndexExtended = SDLK_LEFT_TAB & ~SDLK_EXTENDED_MASK;
static constexpr uint32_t kSizeBase = kMaxIndexBase + 1;
static constexpr uint32_t kSizeScancode = (SDLK_ENDCALL & ~SDLK_SCANCODE_MASK) - kMinIndexScancode + 1;
static constexpr uint32_t kSizeExtended = (SDLK_RHYPER & ~SDLK_EXTENDED_MASK) - kMinIndexExtended + 1;
static constexpr uint32_t kKeyNumEntries = kSizeBase + kSizeScancode + kSizeExtended;

struct Platform {
  explicit Platform(uint32_t *pEventCount, idunn_platform_event **ppEvent);
  ~Platform();
  auto tick() -> void;
  auto subscribe(Key key) -> void;
  auto subscribe(Scancode scancode) -> void;
  auto unsubscribe(Key key) -> void;
  auto unsubscribe(Scancode scancode) -> void;

private:
  uint32_t *pEventCount;
  idunn_platform_event **ppEvent;
  std::vector<idunn_platform_event> tickEvents;
  std::map<SDL_Keycode, Key> keys;
  std::map<SDL_Scancode, Scancode> scancodes;

  static constexpr auto getScancodeMapping() -> std::array<SDL_Scancode, SDL_SCANCODE_COUNT>;
  [[nodiscard]] static auto mapScancode(Scancode scancode) noexcept -> SDL_Scancode;
  static constexpr auto getKeyMapping() -> std::array<SDL_Keycode, kKeyNumEntries>;
  [[nodiscard]] static constexpr auto getKeyMappingIndex(SDL_Keycode keycode) noexcept -> uint32_t;
  [[nodiscard]] static auto mapKey(Key key) noexcept -> SDL_Keycode;
};

struct Window {
  explicit Window(idunn_window_config *config);
  ~Window();
  auto render() -> void;

private:
  Platform *platform;
  Gpu *gpu;
  uint32_t width;
  uint32_t height;
  std::unique_ptr<SDL_Window, void (*)(SDL_Window *)> window;
  std::unique_ptr<Gpu::Surface> surface;
};
