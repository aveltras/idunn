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

// NOLINTBEGIN

#ifdef __cplusplus
extern "C" {
#endif

void idunn_audio_init(void **pAudio);
void idunn_audio_uninit(void *audio);
void idunn_audio_sound_play(void *audio, const char *soundPath);

#ifdef __cplusplus
}
#endif

// NOLINTEND
