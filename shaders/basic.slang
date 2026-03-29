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

Texture2D<float4> textures[];
SamplerState samplers[];
// RWTexture2D<float4> images[];

struct Draw {
  uint transformId;
};

struct PushConstants {
  float4x4 proj;
  uint64_t drawBuffer;
  uint64_t transformBuffer;
  uint64_t vertexBuffer;
};

[[vk::push_constant]]
ConstantBuffer<PushConstants> pushConstants;

// https://shader-slang.org/slang/user-guide/spirv-target-specific

[shader("vertex")] VertexOutput vertexMain(
    uint vertexID : SV_VulkanVertexID,
    uint instanceID : SV_InstanceID,
    uint baseInstance : SV_StartInstanceLocation) {
  VertexOutput output;

  // printf("\INSTANCE__ID: %i", instanceID);
  float4x4 *transforms = (float4x4 *)pushConstants.transformBuffer;
  Draw *draws = (Draw *)pushConstants.drawBuffer;
  Vertex *vertices = (Vertex *)pushConstants.vertexBuffer;

  uint instanceIdx = instanceID + baseInstance;
  Vertex vertex = vertices[vertexID];
  Draw draw = draws[instanceIdx];
  float4x4 model = transforms[draw.transformId];
  output.position = mul(pushConstants.proj, mul(model, float4(vertex.position, 1.0)));

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
