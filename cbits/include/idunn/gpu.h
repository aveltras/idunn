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
void idunn_gpu_command_init(void *gpu, void **pCommand);
void idunn_gpu_command_submit(void *gpu, void *command);

typedef enum idunn_gpu_buffer_usage : uint8_t {
  IDUNN_GPU_BUFFER_USAGE_INDEX = 0,
  IDUNN_GPU_BUFFER_USAGE_VERTEX,
  IDUNN_GPU_BUFFER_USAGE_INDIRECT,
  IDUNN_GPU_BUFFER_USAGE_STORAGE,
} idunn_gpu_buffer_usage;

typedef struct idunn_gpu_buffer_config {
  uint64_t capacity;
  idunn_gpu_buffer_usage usage;
} idunn_gpu_buffer_config;

typedef struct idunn_gpu_buffer_write_info {
  void *data;
  size_t size;
  bool append;
} idunn_gpu_buffer_write_info;

void idunn_gpu_buffer_init(void *gpu, idunn_gpu_buffer_config *config, void **pBuffer);
void idunn_gpu_buffer_uninit(void *buffer);
void idunn_gpu_buffer_write(void *buffer, void *command, idunn_gpu_buffer_write_info *writeInfo);

typedef enum idunn_gpu_pipeline_winding_order : uint8_t {
  IDUNN_GPU_PIPELINE_WINDING_ORDER_CLOCKWISE = 0,
  IDUNN_GPU_PIPELINE_WINDING_ORDER_COUNTER_CLOCKWISE,
} idunn_gpu_pipeline_winding_order;

typedef struct idunn_gpu_pipeline_config {
  idunn_gpu_pipeline_winding_order windingOrder;
  const char *shader;
} idunn_gpu_pipeline_config;

void idunn_gpu_pipeline_init(void *gpu, idunn_gpu_pipeline_config *config, void **pPipeline);
void idunn_gpu_pipeline_uninit(void *pipeline);

typedef enum idunn_gpu_sampler_address_mode : uint8_t {
  IDUNN_GPU_SAMPLER_ADDRESS_MODE_REPEAT = 0,
  IDUNN_GPU_SAMPLER_ADDRESS_MODE_MIRRORED_REPEAT,
  IDUNN_GPU_SAMPLER_ADDRESS_MODE_CLAMP_TO_EDGE,
  IDUNN_GPU_SAMPLER_ADDRESS_MODE_CLAMP_TO_BORDER,
  IDUNN_GPU_SAMPLER_ADDRESS_MODE_MIRROR_CLAMP_TO_EDGE,
} idunn_gpu_sampler_address_mode;

typedef struct idunn_gpu_sampler_config {
  idunn_gpu_sampler_address_mode addressMode;
} idunn_gpu_sampler_config;

void idunn_gpu_sampler_init(void *gpu, idunn_gpu_sampler_config *config, void **pSampler);
void idunn_gpu_sampler_uninit(void *sampler);

typedef enum idunn_gpu_texture_usage : uint8_t {
  IDUNN_GPU_TEXTURE_USAGE_COLOR_2D = 0,
  IDUNN_GPU_TEXTURE_USAGE_COLOR_TEXT_CURVES,
  IDUNN_GPU_TEXTURE_USAGE_COLOR_TEXT_BANDS,
} idunn_gpu_texture_usage;

typedef struct idunn_gpu_texture_region {
  uint32_t width;
  uint32_t height;
  uint32_t depth;
  int32_t offsetX;
  int32_t offsetY;
  int32_t offsetZ;
} idunn_gpu_texture_region;

typedef struct idunn_gpu_texture_write_info {
  idunn_gpu_texture_region *regions;
  size_t regionsSize;
  void *data;
  size_t dataSize;
} idunn_gpu_texture_write_info;

typedef struct idunn_gpu_texture_config {
  idunn_gpu_texture_usage usage;
  uint32_t width;
  uint32_t height;
  uint32_t depth;
} idunn_gpu_texture_config;

void idunn_gpu_texture_init(void *gpu, idunn_gpu_texture_config *config, void **pTexture);
void idunn_gpu_texture_uninit(void *texture);
void idunn_gpu_texture_write(void *texture, void *command, idunn_gpu_texture_write_info *writeInfo);

typedef struct idunn_gpu_surface_config {
  uint32_t width;
  uint32_t height;
  void *window;
} idunn_gpu_surface_config;

void idunn_gpu_surface_init(void *gpu, idunn_gpu_surface_config *config, void **pSurface);
void idunn_gpu_surface_uninit(void *surface);

typedef struct idunn_gpu_render_info {
  void *indexBuffer;
  void *vertexBuffer;
  void *indirectBuffer;
  void *transformBuffer;
  void *instanceBuffer;
  uint32_t instanceCount;
  void *pipeline;
  float projection[16];
} idunn_gpu_render_info;

void idunn_gpu_surface_render(void *surface, idunn_gpu_render_info *renderInfo);

typedef struct idunn_gpu_mesh_instance {
  uint32_t transformIdx;
} idunn_gpu_mesh_instance;

typedef struct idunn_gpu_draw {
  uint32_t indexCount;
  uint32_t instanceCount;
  uint32_t firstIndex;
  int32_t vertexOffset;
  uint32_t firstInstance;
} idunn_gpu_draw;

#ifdef __cplusplus
}
#endif

// NOLINTEND
