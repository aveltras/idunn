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

#include <idunn/platform.h>

#include "logger.hpp"
#include "platform.hpp"

#include <SDL3/SDL.h>

Platform::Platform() {
  LOG_DEBUG("Platform");
  SDL_Init(SDL_INIT_VIDEO | SDL_INIT_GAMEPAD);
}

Platform::~Platform() {
  SDL_Quit();
  LOG_DEBUG("~Platform");
}

extern "C" {
void idunn_platform_init(void **pPlatform) { *pPlatform = new Platform(); }

void idunn_platform_uninit(void *platform) {
  delete static_cast<Platform *>(platform);
}
}
