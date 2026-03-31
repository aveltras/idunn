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

#include <idunn/physics.h>
#include <Jolt/Jolt.h>
#include <Jolt/Physics/PhysicsSystem.h>
#include <Jolt/Physics/Body/BodyActivationListener.h>
#include <set>

struct Physics {

  struct System : public JPH::BroadPhaseLayerInterface,
                  public JPH::ObjectVsBroadPhaseLayerFilter,
                  public JPH::ObjectLayerPairFilter,
                  public JPH::BodyActivationListener,
                  public JPH::ContactListener {
    explicit System(Physics *physics, idunn_physics_system_config *config);
    ~System() override;

    [[nodiscard]] auto GetNumBroadPhaseLayers() const -> uint override;
    [[nodiscard]] auto GetBroadPhaseLayer(JPH::ObjectLayer inLayer) const -> JPH::BroadPhaseLayer override;
#if defined(JPH_EXTERNAL_PROFILE) || defined(JPH_PROFILE_ENABLED)
    [[nodiscard]] auto GetBroadPhaseLayerName(JPH::BroadPhaseLayer inLayer) const -> const char * override;
#endif
    [[nodiscard]] auto ShouldCollide(JPH::ObjectLayer inLayer1, JPH::BroadPhaseLayer inLayer2) const -> bool override;
    [[nodiscard]] auto ShouldCollide(JPH::ObjectLayer inLayer1, JPH::ObjectLayer inLayer2) const -> bool override;

    auto OnContactValidate(const JPH::Body &inBody1, const JPH::Body &inBody2, JPH::RVec3Arg inBaseOffset, const JPH::CollideShapeResult &inCollisionResult) -> JPH::ValidateResult override;
    auto OnContactAdded(const JPH::Body &inBody1, const JPH::Body &inBody2, const JPH::ContactManifold &inManifold, JPH::ContactSettings &ioSettings) -> void override;
    auto OnContactPersisted(const JPH::Body &inBody1, const JPH::Body &inBody2, const JPH::ContactManifold &inManifold, JPH::ContactSettings &ioSettings) -> void override;
    auto OnContactRemoved(const JPH::SubShapeIDPair &inSubShapePair) -> void override;
    auto OnBodyActivated(const JPH::BodyID &inBodyID, uint64_t inBodyUserData) -> void override;
    auto OnBodyDeactivated(const JPH::BodyID &inBodyID, uint64_t inBodyUserData) -> void override;

    auto subscribe(uint32_t bodyID) -> void;
    auto create(idunn_physics_body_settings *settings) -> void;

    auto update() -> void;

  private:
    auto create(JPH::Shape *inShape, JPH::RVec3Arg position, JPH::ObjectLayer objectLayer) -> uint32_t;

    Physics *physics;
    JPH::PhysicsSystem system;
    uint32_t broadPhaseLayerCount;
    uint32_t objectLayerCount;
    std::vector<JPH::BroadPhaseLayer> objectToBroadPhaseLayers;
    std::vector<bool> objectCollisions;
    std::vector<bool> broadCollisions;
    std::vector<const char *> broadPhaseLayerNames;

    std::set<JPH::BodyID> contactListeners;
    idunn_physics_on_contact_added contactAddedCallback;

    uint32_t *pContactRemovedCount;
    uint64_t **pContactRemoved;
    std::vector<uint64_t> contactRemoved;

    uint32_t *pActiveBodyCount;
    uint32_t **ppActiveBodies;
    std::vector<uint32_t> activeRawBodyIds;
    float (**transformData)[16];
  };

  explicit Physics();
  ~Physics();

private:
  JPH::TempAllocator *tempAllocator;
  JPH::JobSystem *jobSystem;
};
