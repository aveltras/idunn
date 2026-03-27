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

#include <SDL3/SDL.h>
#include <cassert>

extern "C" {
void idunn_platform_init(void **pPlatform) { *pPlatform = new Platform(); }

void idunn_platform_uninit(void *platform) {
  delete static_cast<Platform *>(platform);
}

void idunn_platform_window_init(idunn_window_config *config, void **pWindow) {
  *pWindow = new Window(config);
}

void idunn_platform_window_uninit(void *window) {
  delete static_cast<Window *>(window);
}

void idunn_platform_window_render(void *window) {
  static_cast<Window *>(window)->render();
}
}

Platform::Platform() {
  LOG_DEBUG("Platform");
  SDL_Init(SDL_INIT_VIDEO | SDL_INIT_GAMEPAD);
}

Platform::~Platform() {
  SDL_Quit();
  LOG_DEBUG("~Platform");
}

Window::Window(idunn_window_config *config)
    : width(config->width),
      height(config->height),
      window(SDL_CreateWindow(config->title, (int)width, (int)height, SDL_WINDOW_VULKAN), SDL_DestroyWindow),
      surface(std::make_unique<Surface>(static_cast<Gpu *>(config->gpu), window.get(), config->width, config->height)) {
  LOG_DEBUG("Window");
}

Window::~Window() {
  LOG_DEBUG("~Window");
}

auto Window::render() -> void {
  surface->draw(width, height, 1);
}
