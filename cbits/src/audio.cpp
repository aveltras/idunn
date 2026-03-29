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

#include "audio.hpp"
#include "logger.hpp"

#include <cassert>

extern "C" {
void idunn_audio_init(void **pAudio) {
  *pAudio = new Audio();
}

void idunn_audio_uninit(void *audio) {
  delete static_cast<Audio *>(audio);
}

void idunn_audio_sound_play(void *audio, const char *soundPath) {
  static_cast<Audio *>(audio)->play(soundPath);
}
}

Audio::Audio() : miniaudio(new ma_engine) {
  LOG_DEBUG("Audio");
  ma_result result = ma_engine_init(nullptr, miniaudio);
  assert(result == MA_SUCCESS);
}

Audio::~Audio() {
  ma_engine_uninit(miniaudio);
  LOG_DEBUG("~Audio");
}

auto Audio::play(const char *soundPath) -> void {
  ma_result result = ma_engine_play_sound(miniaudio, soundPath, nullptr);
  assert(result == MA_SUCCESS);
}
