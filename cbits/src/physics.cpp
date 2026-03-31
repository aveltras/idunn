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

#include "physics.hpp"
#include "logger.hpp"

#include <Jolt/RegisterTypes.h>
#include <Jolt/Core/Factory.h>
#include <Jolt/Core/TempAllocator.h>
#include <Jolt/Core/JobSystemThreadPool.h>
#include <Jolt/Physics/PhysicsSettings.h>

#include <Jolt/Physics/Collision/Shape/BoxShape.h>
#include <Jolt/Physics/Collision/Shape/SphereShape.h>
#include <Jolt/Physics/Body/BodyCreationSettings.h>
#include <Jolt/Physics/Body/BodyActivationListener.h>

#include <cstdarg>
#include <thread>

extern "C" {
void idunn_physics_init(void **pPhysics) {
  *pPhysics = new Physics();
}

void idunn_physics_uninit(void *physics) {
  delete static_cast<Physics *>(physics);
}

void idunn_physics_system_init(void *physics, idunn_physics_system_config *config, void **pSystem) {
  *pSystem = new Physics::System(static_cast<Physics *>(physics), config);
}

void idunn_physics_system_uninit(void *system) {
  delete static_cast<Physics::System *>(system);
}

void idunn_physics_system_update(void *system) {
  static_cast<Physics::System *>(system)->update();
}

void idunn_physics_body_init(void *system, idunn_physics_body_settings *settings, uint32_t *pBodyId) {
  *pBodyId = static_cast<Physics::System *>(system)->create(settings);
}

void idunn_physics_body_contact_subscribe(void *system, uint32_t bodyID) {
  static_cast<Physics::System *>(system)->subscribe(bodyID);
}
}

using namespace JPH::literals;

static void TraceImpl(const char *inFMT, ...) {
  // Format the message
  va_list list;
  va_start(list, inFMT);
  char buffer[1024];
  vsnprintf(buffer, sizeof(buffer), inFMT, list);
  va_end(list);

  // Print to the TTY
  LOG_DEBUG("[physics]: %s", buffer);
}

// Callback for asserts, connect this to your own assert handler if you have one
static auto AssertFailedImpl(const char *inExpression, const char *inMessage, const char *inFile, uint inLine) -> bool {
  // Print to the TTY
  LOG_WARNING("[physics]: %s:%u: (%s) %s", inFile, inLine, inExpression, inMessage);

  // Breakpoint
  return true;
};

JPH::TraceFunction JPH::Trace = TraceImpl;
JPH::AssertFailedFunction JPH::AssertFailed = AssertFailedImpl;

Physics::Physics() {
  LOG_DEBUG("Physics");
  JPH::RegisterDefaultAllocator();
  JPH::Factory::sInstance = new JPH::Factory();
  JPH::RegisterTypes();
  tempAllocator = new JPH::TempAllocatorImpl(10 * 1024 * 1024);
  jobSystem = new JPH::JobSystemThreadPool(JPH::cMaxPhysicsJobs, JPH::cMaxPhysicsBarriers, std::thread::hardware_concurrency() - 1);
}

Physics::~Physics() {
  delete jobSystem;
  delete tempAllocator;
  JPH::UnregisterTypes();
  delete JPH::Factory::sInstance;
  JPH::Factory::sInstance = nullptr;
  LOG_DEBUG("~Physics");
}

Physics::System::System(Physics *physics, idunn_physics_system_config *config)
    : physics(physics),
      broadPhaseLayerCount(config->broadPhaseLayerCount),
      objectLayerCount(config->objectLayerCount),
      contactAddedCallback(config->onContactAdded),
      pContactRemovedCount(config->pContactRemovedCount),
      pContactRemoved(config->pContactRemoved) {
  LOG_DEBUG("System");

  for (uint32_t i = 0; i < config->broadPhaseLayerCount; i++) {
    broadPhaseLayerNames.push_back(config->broadPhaseLayerNames[i]);
  }

  for (uint32_t i = 0; i < config->objectLayerCount; i++) {
    objectToBroadPhaseLayers.emplace_back(config->objectToBroadPhaseLayers[i]);
  }

  uint32_t totalObjectPairs = objectLayerCount * objectLayerCount;
  for (uint32_t i = 0; i < totalObjectPairs; i++) {
    objectCollisions.push_back(config->objectCollisions[i] != 0);
  }

  uint32_t totalBroadPairs = objectLayerCount * broadPhaseLayerCount;
  for (uint32_t i = 0; i < totalBroadPairs; i++) {
    broadCollisions.push_back(config->broadCollisions[i] != 0);
  }

  system.Init(
      config->maxBodies,
      config->bodyMutexes,
      config->maxBodyPairs,
      config->maxContactConstraints,
      *this,
      *this,
      *this);

  system.SetBodyActivationListener(this);
  system.SetContactListener(this);
}

Physics::System::~System() {
  LOG_DEBUG("~System");
}

auto Physics::System::GetNumBroadPhaseLayers() const -> uint {
  // LOG_DEBUG("GetNumBroadPhaseLayers: %i", broadPhaseLayerCount);
  return broadPhaseLayerCount;
}

auto Physics::System::GetBroadPhaseLayer(JPH::ObjectLayer inLayer) const -> JPH::BroadPhaseLayer {
  // LOG_DEBUG("GetBroadPhaseLayer");
  return objectToBroadPhaseLayers[inLayer];
}

#if defined(JPH_EXTERNAL_PROFILE) || defined(JPH_PROFILE_ENABLED)
auto Physics::System::GetBroadPhaseLayerName(JPH::BroadPhaseLayer inLayer) const -> const char * {
  return broadPhaseLayerNames[inLayer.GetValue()];
}
#endif

auto Physics::System::ShouldCollide(JPH::ObjectLayer inLayer1, JPH::BroadPhaseLayer inLayer2) const -> bool {
  return broadCollisions[(inLayer1 * broadPhaseLayerCount) + inLayer2.GetValue()];
}

auto Physics::System::ShouldCollide(JPH::ObjectLayer inLayer1, JPH::ObjectLayer inLayer2) const -> bool {
  return objectCollisions[(inLayer1 * objectLayerCount) + inLayer2];
}

auto Physics::System::OnContactValidate(const JPH::Body &inBody1, const JPH::Body &inBody2, JPH::RVec3Arg inBaseOffset, const JPH::CollideShapeResult &inCollisionResult) -> JPH::ValidateResult {
  LOG_DEBUG("OnContactValidate");
  return JPH::ValidateResult::AcceptAllContactsForThisBodyPair;
}

auto Physics::System::OnContactAdded(const JPH::Body &inBody1, const JPH::Body &inBody2, const JPH::ContactManifold &inManifold, JPH::ContactSettings &ioSettings) -> void {
  LOG_DEBUG("A contact was added");
  auto body1Listens = contactListeners.contains(inBody1.GetID());
  auto body2Listens = contactListeners.contains(inBody2.GetID());
  if (body1Listens || body2Listens) {
    contactAddedCallback(inBody1.GetID().GetIndexAndSequenceNumber(), inBody2.GetID().GetIndexAndSequenceNumber());
  }
}

auto Physics::System::OnContactPersisted(const JPH::Body &inBody1, const JPH::Body &inBody2, const JPH::ContactManifold &inManifold, JPH::ContactSettings &ioSettings) -> void {
  LOG_DEBUG("A contact was persisted");
}

auto Physics::System::OnContactRemoved(const JPH::SubShapeIDPair &inSubShapePair) -> void {
  auto rawBody1 = inSubShapePair.GetBody1ID().GetIndexAndSequenceNumber();
  auto rawBody2 = inSubShapePair.GetBody2ID().GetIndexAndSequenceNumber();
  LOG_DEBUG("A contact was removed between %u and %u", rawBody1, rawBody2);
  contactRemoved.push_back(((uint64_t)rawBody1 << 32) | rawBody2);
}

auto Physics::System::OnBodyActivated(const JPH::BodyID &inBodyID, uint64_t inBodyUserData) -> void {
  LOG_DEBUG("A body got activated");
}

auto Physics::System::OnBodyDeactivated(const JPH::BodyID &inBodyID, uint64_t inBodyUserData) -> void {
  LOG_DEBUG("A body went to sleep");
}

auto Physics::System::create(idunn_physics_body_settings *settings) -> uint32_t {
  JPH::BodyInterface &bodyInterface = system.GetBodyInterface();
  JPH::Shape *shape;
  switch (settings->shapeType) {
  case Sphere:
    shape = new JPH::SphereShape(settings->shapeSettings.sphere.radius);
    break;
  case Box:
    shape = new JPH::BoxShape(JPH::Vec3(settings->shapeSettings.box.halfExtentX, settings->shapeSettings.box.halfExtentY, settings->shapeSettings.box.halfExtentZ), settings->shapeSettings.box.convexRadius);
    break;
  }

  shape->SetEmbedded();

  JPH::BodyCreationSettings bodyCreationSettings(
      shape,
      JPH::RVec3(settings->position[0], settings->position[1], settings->position[2]),
      JPH::Quat::sIdentity(),
      static_cast<JPH::EMotionType>(settings->motionType),
      settings->objectLayer);

  // JPH::Body *body = body_interface.CreateBody(bodyCreationSettings);
  // return body->GetID().GetIndexAndSequenceNumber();

  JPH::BodyID bodyID = bodyInterface.CreateAndAddBody(bodyCreationSettings, JPH::EActivation::Activate);

  return bodyID.GetIndexAndSequenceNumber();
}

auto Physics::System::subscribe(uint32_t bodyID) -> void {
  contactListeners.insert(JPH::BodyID(bodyID));
}

auto Physics::System::update() -> void {
  // system.GetActiveBodies(EBodyType inType, BodyIDVector &outBodyIDs)
  // JPH::RVec3 position = body_interface.GetCenterOfMassPosition(sphereID);
  // JPH::Vec3 velocity = body_interface.GetLinearVelocity(sphereID);
  // LOG_DEBUG("[physics]: Position = (%f, %f, %f), Velocity = (%f, %f, %f)", position.GetX(), position.GetY(), position.GetZ(), velocity.GetX(), velocity.GetY(), velocity.GetZ());

  // system.GetActiveBodies(EBodyType inType, BodyIDVector &outBodyIDs)
  const float cDeltaTime = 1.0F / 60.0F;
  const int cCollisionSteps = 1;
  contactRemoved.clear();
  system.Update(cDeltaTime, cCollisionSteps, physics->tempAllocator, physics->jobSystem);
  *pContactRemovedCount = contactRemoved.size();
  *pContactRemoved = contactRemoved.data();
}
