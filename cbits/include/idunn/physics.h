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

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

void idunn_physics_init(void **pPhysics);
void idunn_physics_uninit(void *physics);

typedef void (*idunn_physics_on_contact_added)(uint32_t bodyID1, uint32_t bodyID2);

typedef struct idunn_physics_system_config {
  unsigned int maxBodies;
  unsigned int bodyMutexes;
  unsigned int maxBodyPairs;
  unsigned int maxContactConstraints;
  uint32_t broadPhaseLayerCount;
  char **broadPhaseLayerNames;
  uint32_t objectLayerCount;
  uint32_t *objectToBroadPhaseLayers;
  uint32_t *objectCollisions;
  uint32_t *broadCollisions;
  uint32_t *pContactRemovedCount;
  uint64_t **pContactRemoved;
  idunn_physics_on_contact_added onContactAdded;
  uint32_t *pActiveBodyCount;
  uint32_t **ppActiveBodies;
  float (**transformData)[16];
} idunn_physics_system_config;

void idunn_physics_system_init(void *physics, idunn_physics_system_config *config, void **pSystem);
void idunn_physics_system_uninit(void *system);
void idunn_physics_system_update(void *system);

typedef struct idunn_physics_sphere_shape_settings {
  float radius;
} idunn_physics_sphere_shape_settings;

typedef struct idunn_physics_box_shape_settings {
  float halfExtentX;
  float halfExtentY;
  float halfExtentZ;
  float convexRadius;
} idunn_physics_box_shape_settings;

typedef enum idunn_physics_motion_type : uint8_t {
  Static,
  Kinematic,
  Dynamic,
} idunn_physics_motion_type;

typedef enum idunn_physics_shape_type : uint8_t {
  Sphere,
  Box,
} idunn_physics_shape_type;

typedef struct idunn_physics_body_settings {
  uint32_t bodyID;
  idunn_physics_motion_type motionType;
  float *position;
  uint32_t objectLayer;
  idunn_physics_shape_type shapeType;
  union {
    idunn_physics_box_shape_settings box;
    idunn_physics_sphere_shape_settings sphere;
  } shapeSettings;
} idunn_physics_body_settings;

void idunn_physics_body_init(void *system, idunn_physics_body_settings *settings);
void idunn_physics_body_contact_subscribe(void *system, uint32_t bodyID);

#ifdef __cplusplus
}
#endif

// NOLINTEND
