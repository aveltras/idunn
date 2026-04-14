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
void idunn_gpu_buffer_uninit(void *gpu, void *buffer);
void idunn_gpu_buffer_write(void *gpu, void *buffer, idunn_gpu_buffer_write_info *writeInfo);

// vkCmdBindIndexBuffer(commandBuffer, indexBuffer->buffer, 0, VK_INDEX_TYPE_UINT32);
// vkCmdBindPipeline(commandBuffer, VK_PIPELINE_BIND_POINT_GRAPHICS, pipeline->pipeline);
// vkCmdBindDescriptorSets(commandBuffer, VK_PIPELINE_BIND_POINT_GRAPHICS, pipeline->layout, 0, 1, &descriptorSet, 0, nullptr);
// vkCmdPushConstants(commandBuffer, pipeline->layout, VK_SHADER_STAGE_VERTEX_BIT, 0, sizeof(World::PushConstants), &pushConstants);
// vkCmdDrawIndexedIndirect(commandBuffer, indirectBuffer->buffer, 0, world->currentMeshCount, sizeof(VkDrawIndexedIndirectCommand));

typedef struct idunn_gpu_render_info {
  void *indexBuffer;
  void *vertexBuffer;
  void *indirectBuffer;
  void *transformBuffer;
  void *instanceBuffer;
  float projection[16];
} idunn_gpu_render_info;

void idunn_gpu_render(void *gpu, void *surface, idunn_gpu_render_info *renderInfo);

typedef struct idunn_gpu_mesh {
  uint32_t indexOffset;
  uint32_t indexCount;
  uint32_t vertexOffset;
  uint32_t vertexCount;
} idunn_gpu_mesh;

typedef struct idunn_gpu_mesh_upload {
  void *vertices;
  uint32_t *indices;
  idunn_gpu_mesh *meshes;
  uint32_t meshCount;
  uint32_t *meshHandles;
} idunn_gpu_mesh_upload;

typedef struct idunn_gpu_mesh_instance {
  uint32_t transformIdx;
} idunn_gpu_mesh_instance;

typedef struct idunn_gpu_world_config {
  uint32_t vertexSize;
  uint32_t indexSize;
  float (**transformData)[16];
  bool *transformDirty;
} idunn_gpu_world_config;

typedef struct idunn_gpu_draw {
  uint32_t indexCount;
  uint32_t instanceCount;
  uint32_t firstIndex;
  int32_t vertexOffset;
  uint32_t firstInstance;
} idunn_gpu_draw;

void idunn_gpu_world_init(void *gpu, idunn_gpu_world_config *config, uint64_t *pWorldHandle);
void idunn_gpu_world_uninit(void *gpu, uint64_t worldHandle);
/* void idunn_gpu_world_upload_meshes(void *gpu, uint64_t worldHandle, idunn_gpu_mesh_upload *uploadInfo); */

#ifdef __cplusplus
}
#endif

// NOLINTEND
