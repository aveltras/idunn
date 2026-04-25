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

#include <idunn/gpu.h>
#include <volk.h>
#include <vk_mem_alloc.h>
#include <SDL3/SDL_video.h>
#include <filesystem>
#include <future>
#include <vector>
#include <slang.h>
#include <slang-com-ptr.h>
#include <glm/mat4x4.hpp>

#include "flags.hpp"

struct Gpu {

  enum class DescriptorSync : uint8_t {
    None = 0,
    SampledImage = 1 << 0,
    Sampler = 1 << 1,
    StorageImage = 1 << 2,
  };

  struct Buffer {
    friend Gpu;

    explicit Buffer(Gpu *gpu, idunn_gpu_buffer_config *config);
    ~Buffer();
    auto resize(size_t capacity) -> void;
    auto write(VkCommandBuffer commandBuffer, idunn_gpu_buffer_write_info *writeInfo) -> void;

  private:
    auto freeResources() -> void;

    Gpu *gpu;
    VkBuffer buffer;
    VmaAllocation allocation;
    VmaAllocationInfo allocationInfo;
    VkMemoryPropertyFlags memoryFlags;
    VkImageUsageFlags usageFlags;
    VkDeviceAddress address;
    VkDeviceSize usedCapacity = 0;
#ifndef NDEBUG
    const char *debugName;
#endif
  };

  struct Pipeline {
    friend Gpu;

    explicit Pipeline(Gpu *gpu, idunn_gpu_pipeline_config *config);
    ~Pipeline();

  private:
    Gpu *gpu;
    VkPipeline pipeline;
    VkPipelineLayout layout;
  };

  struct Sampler {
    friend Gpu;

    explicit Sampler(Gpu *gpu, idunn_gpu_sampler_config *config);
    ~Sampler();

  private:
    Gpu *gpu;
    VkSampler sampler;
  };

  struct Texture {
    friend Gpu;

    explicit Texture(Gpu *gpu, idunn_gpu_texture_config *config);
    ~Texture();
    auto write(VkCommandBuffer commandBuffer, idunn_gpu_texture_write_info *writeInfo) -> void;

  private:
    Gpu *gpu;
    VkImage image;
    VkImageType imageType;
    VkImageView imageView;
    VkImageViewType imageViewType;
    VmaAllocation allocation;
    VmaAllocationInfo allocationInfo;
    VkExtent3D extent;
    VkFormat format;
    VkImageAspectFlags aspectFlags;
    VkImageUsageFlags usageFlags;
    VkMemoryPropertyFlags memoryFlags;
    uint32_t levelCount;
    uint32_t layerCount;
    VkImageLayout layout;
  };

  struct Surface {
    friend Gpu;

    explicit Surface(Gpu *gpu, idunn_gpu_surface_config *config);
    ~Surface();

    auto render(idunn_gpu_render_info *renderInfo, uint32_t width, uint32_t height, float clearColor) -> void;

  private:
    auto initSwapchain(uint32_t width, uint32_t height) -> void;
    auto cleanupSwapchainResources() -> void;

    Gpu *gpu;
    VkSurfaceKHR surface;
    VkSwapchainKHR swapchain = VK_NULL_HANDLE;
    VkExtent2D extent;
    VkSurfaceFormatKHR format;
    std::vector<VkImage> images;
    std::vector<VkImageView> imageViews;
    std::vector<VkSemaphore> readyForRender;
    std::vector<VkSemaphore> readyForPresent;
  };

  struct Task {
    explicit Task(std::packaged_task<void()> &&task, VkFence fence) : task(std::move(task)), fence(fence) {}
    std::packaged_task<void()> task;
    VkFence fence;
  };

  struct PushConstants {
    float proj[16];
    uint64_t instanceBuffer;
    uint64_t transformBuffer;
    uint64_t vertexBuffer;
  };

  explicit Gpu(idunn_gpu_config *config);
  ~Gpu();
  auto acquireCommandBuffer() -> VkCommandBuffer;
  auto submitCommandBuffer(VkCommandBuffer commandBuffer) -> void;

private:
  VkInstance instance;
  VkAllocationCallbacks *allocationCallbacks = nullptr;
  VkPhysicalDevice physicalDevice;
  uint32_t graphicsFamilyIndex;
  VkDevice device;
  VkQueue graphicsQueue;
  VkCommandPool graphicsCommandPool;
  VmaAllocator allocator;
  VkDescriptorSetLayout descriptorSetLayout;
  VkDescriptorPool descriptorPool;
  VkDescriptorSet descriptorSet;
  std::vector<VkFence> frameFences;
  std::vector<VkCommandBuffer> frameCommandBuffers;
  uint32_t frameNumber = 0;
  std::vector<Task> tasks;
  Idunn::Flags<DescriptorSync> descriptorSync = DescriptorSync::None;
  Slang::ComPtr<slang::IGlobalSession> globalSlangSession;
  Slang::ComPtr<slang::ISession> slangSession;
#ifndef NDEBUG
  VkDebugUtilsMessengerEXT debugUtilsMessenger;
#endif

  static auto checkRequiredLayers(const std::vector<const char *> &layers) -> bool;
  static auto checkRequiredInstanceExtensions(const std::vector<const char *> &extensions) -> bool;
  static auto checkExtensions(const std::vector<VkExtensionProperties> &availableExtensions, const std::vector<const char *> &extensions) -> bool;
  static auto logSlangDiagnostics(slang::IBlob *diagnosticsBlob) -> void;

  auto initInstance(const char *appName, uint32_t appVersion, uint32_t apiVersion, const std::vector<const char *> &layers, const std::vector<const char *> &extensions) -> bool;
  auto selectPhysicalDevice(uint32_t apiVersion, const std::vector<const char *> &requiredExtensions) -> bool;
  auto initDevice(const std::vector<const char *> &layers, const std::vector<const char *> &extensions) -> bool;
  auto initSlangSession(const char *shadersPath) -> void;
  // auto initDescriptors() -> void;
  // auto syncDescriptors() -> void;
  auto defer(std::packaged_task<void()> &&task) -> void;
  auto processReadyTasks() -> void;
  auto processAllTasks() -> void;
  auto submit(std::function<void(VkCommandBuffer commandBuffer)> &&recordCommands) -> void;

#ifndef NDEBUG
  static auto debugMessengerCallback(
      VkDebugUtilsMessageSeverityFlagBitsEXT messageSeverity,
      VkDebugUtilsMessageTypeFlagsEXT messageTypes,
      const VkDebugUtilsMessengerCallbackDataEXT *pCallbackData,
      void *pUserData) -> VkBool32;
#endif
};
