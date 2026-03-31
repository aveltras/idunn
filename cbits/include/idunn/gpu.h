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

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct idunn_gpu_config {
  const char *appName;
  uint32_t version;
  const char *shadersPath;
} idunn_gpu_config;

void idunn_gpu_init(idunn_gpu_config *config, void **pGpu);
void idunn_gpu_uninit(void *gpu);

typedef struct idunn_gpu_mesh {
  uint32_t indexOffset;
  uint32_t indexCount;
  uint32_t vertexOffset;
  uint32_t vertexCount;
} idunn_gpu_mesh;

typedef struct idunn_gpu_world_config {
  uint32_t vertexSize;
  size_t *vertexCount;
  bool *vertexDirty;
  void **vertexData;
  uint32_t indexSize;
  size_t *indexCount;
  bool *indexDirty;
  uint32_t **indexData;
  size_t *meshCount;
  bool *meshDirty;
  idunn_gpu_mesh **meshData;
  float (**transformData)[16];
  bool *transformDirty;
} idunn_gpu_world_config;

void idunn_gpu_world_init(void *gpu, idunn_gpu_world_config *config, uint64_t *pWorldHandle);
void idunn_gpu_world_uninit(void *gpu, uint64_t worldHandle);

#ifdef __cplusplus
}
#endif

// NOLINTEND
