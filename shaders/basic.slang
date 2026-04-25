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

struct Vertex {
  float3 position;
};

struct VertexOutput {
  float4 position : SV_Position;
  // float3 color : COLOR;
};

// Texture2D<float4> textures[];
// SamplerState samplers[];
// RWTexture2D<float4> images[];

struct Instance {
  uint32_t transformIdx;
};

struct PushConstants {
  float4x4 proj;
  uint64_t instanceBuffer;
  uint64_t transformBuffer;
  uint64_t vertexBuffer;
};

[[vk::push_constant]]
ConstantBuffer<PushConstants> pushConstants;

// https://shader-slang.org/slang/user-guide/spirv-target-specific

void printMat4(float4x4 M) {
  printf("Row 0: %v4f\nRow 1: %v4f\nRow 2: %v4f\nRow 3: %v4f\n", M[0], M[1], M[2], M[3]);
}

void printVec3(float3 x) {
  printf("X: %f, Y: %f, Z: %f", x.x, x.y, x.z);
}

[shader("vertex")] VertexOutput vertexMain(
    uint vertexID : SV_VulkanVertexID,
    uint instanceID : SV_InstanceID,
    uint baseInstance : SV_StartInstanceLocation) {
  VertexOutput output;

  // printf("GPU VertexBuffer Address: 0x%llx\n", pushConstants.vertexBuffer);
  // printf("GPU TransformBuffer Address: 0x%llx\n", pushConstants.transformBuffer);
  // printf("GPU InstanceBuffer Address: 0x%llx\n", pushConstants.instanceBuffer);

  float4x4 *transforms = (float4x4 *)pushConstants.transformBuffer;
  Instance *instances = (Instance *)pushConstants.instanceBuffer;
  Vertex *vertices = (Vertex *)pushConstants.vertexBuffer;

  uint instanceIdx = instanceID + baseInstance;
  Vertex vertex = vertices[vertexID];
  Instance instance = instances[instanceIdx];

  // printf("\nIN VERTEX!!: %u", instance.transformIdx);

  float4x4 model = transforms[instance.transformIdx];

  // printf("\nVertexID: %i", vertexID);
  // printMat4(model);
  // printVec3(vertex.position.xyz);

  // printf("\nINSTANCE: %i, TRANSLATION: %f, %f, %f", baseInstance, model[0][3], model[1][3], model[2][3]);
  // printf("\nVertexID: %i, TRANSLATION: %v3f", vertexID, vertex.position.xyz);

  output.position = mul(pushConstants.proj, mul(model, float4(vertex.position, 1.0)));
  // output.position = float4(vertex.position, 1.0);
  // output.position = float4(1.0, 1.0, 1.0, 1.0);
  // printf("\nINSTANCE: %i, TRANSLATION: %f, %f, %f", baseInstance, model[0][3], model[1][3], model[2][3]);
  // printf("\nVertexID: %i, TRANSLATION: %v3f", vertexID, vertex.position.xyz);

  return output;
};

[shader("fragment")] float4 fragmentMain(VertexOutput inVert) : SV_Target {

  // return float4(inVert.color, 1.0);
  // printf("\nTEXTURE_ID: %i, SAMPLER_ID: %i", pushConstants.textureId, pushConstants.samplerId);
  // float4 color = textures[pushConstants.textureId].Sample(samplers[pushConstants.samplerId], inVert.uv);
  float4 color = float4(1.0, 1.0, 1.0, 1.0);
  return color;
  // return inVert.color;
}
