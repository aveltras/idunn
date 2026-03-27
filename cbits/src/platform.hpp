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
#include <SDL3/SDL_video.h>
#include <memory>
#include "gpu.hpp"

struct Platform {
  explicit Platform();
  ~Platform();
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
  std::unique_ptr<Surface> surface;
};
