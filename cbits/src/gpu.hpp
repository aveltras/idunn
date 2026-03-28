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

#include "flags.hpp"
#include "pool.hpp"

struct Gpu {

  enum class DescriptorSync : uint8_t {
    None = 0,
    SampledImage = 1 << 0,
    Sampler = 1 << 1,
    StorageImage = 1 << 2,
  };

  struct Buffer {
    friend Gpu;

    enum class Usage : uint8_t {
      Index = 0,
      Vertex,
      Indirect,
      Storage,
    };

    struct Desc {
      Usage usage;
      size_t size;
#ifndef NDEBUG
      const char *debugName;
#endif
    };

    struct Write {
      void **writesData;
      size_t *writesSizes;
      uint8_t writesSize;
    };

  private:
    VkBuffer buffer;
    VmaAllocation allocation;
    VmaAllocationInfo allocationInfo;
    VkMemoryPropertyFlags memoryFlags;
    VkImageUsageFlags usageFlags;
    VkDeviceAddress address;
#ifndef NDEBUG
    const char *debugName;
#endif
  };

  struct Pipeline {
    friend Gpu;

    enum class WindingOrder : uint8_t {
      ClockWise = 0,
      CounterClockwise,
    };

    struct Desc {
      WindingOrder windingOrder;
      std::filesystem::path shader;
      VkFormat colorAttachmentFormat;
#ifndef NDEBUG
      const char *debugName;
#endif
    };

  private:
    VkPipeline pipeline;
    VkPipelineLayout layout;
  };

  struct Sampler {
    friend Gpu;

    enum class AddressMode : uint8_t {
      Repeat = 0,
      MirroredRepeat,
      ClampToEdge,
      ClampToBorder,
      MirrorClampToEdge,
    };

    struct Desc {
      AddressMode addressMode = AddressMode::Repeat;
#ifndef NDEBUG
      const char *debugName;
#endif
    };

  private:
    VkSampler sampler;
  };

  struct Texture {
    friend Gpu;

    enum class Usage : uint8_t {
      Color2D = 0,
      TextCurves,
      TextBands,
    };

    struct Desc {
      Usage usage;
      uint32_t width;
      uint32_t height;
      uint32_t depth = 1;
#ifndef NDEBUG
      const char *debugName;
#endif
    };

    struct Region {
      uint32_t width;
      uint32_t height;
      uint32_t depth = 1;
      int32_t offsetX = 0;
      int32_t offsetY = 0;
      int32_t offsetZ = 0;
    };

    struct Write {
      std::vector<Region> regions;
      void *data;
      size_t dataSize;
    };

  private:
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
    explicit Surface(Gpu *gpu, SDL_Window *window, uint32_t width, uint32_t height);
    ~Surface();
    auto draw(uint32_t width, uint32_t height, float clearColor) -> void;

  private:
    Gpu *gpu;
    VkSurfaceKHR surface;
    VkSwapchainKHR swapchain = VK_NULL_HANDLE;
    VkExtent2D extent;
    VkSurfaceFormatKHR format;
    std::vector<VkImage> images;
    std::vector<VkImageView> imageViews;
    std::vector<VkSemaphore> readyForRender;
    std::vector<VkSemaphore> readyForPresent;

    auto initSwapchain(uint32_t width, uint32_t height) -> void;
    auto cleanupSwapchainResources() -> void;
  };

  struct Task {
    explicit Task(std::packaged_task<void()> &&task, VkFence fence) : task(std::move(task)), fence(fence) {}
    std::packaged_task<void()> task;
    VkFence fence;
  };

  explicit Gpu(idunn_gpu_config *config);
  ~Gpu();

  auto create(Buffer::Desc &description) -> Handle<Buffer>;
  auto create(Buffer &buffer, size_t size) -> Handle<Buffer>;
  auto write(Handle<Buffer> handle, VkCommandBuffer commandBuffer, const Buffer::Write &writeInfo) -> void;
  auto destroy(Handle<Buffer> buffer) -> void;
  auto destroy(Buffer &buffer) -> void;

  auto create(Pipeline::Desc &description) -> Handle<Pipeline>;
  auto destroy(Handle<Pipeline> pipeline) -> void;
  auto destroy(Pipeline &pipeline) -> void;

  auto create(Sampler::Desc &description) -> Handle<Sampler>;
  auto destroy(Handle<Sampler> sampler) -> void;
  auto destroy(Sampler &sampler) -> void;

  auto create(Texture::Desc &description) -> Handle<Texture>;
  auto write(Handle<Texture> handle, VkCommandBuffer commandBuffer, const Texture::Write &writeInfo) -> void;
  auto destroy(Handle<Texture> texture) -> void;
  auto destroy(Texture &texture) -> void;

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
  Pool<Buffer> buffers;
  Pool<Pipeline> pipelines;
  Pool<Sampler> samplers;
  Pool<Texture> textures;
  Handle<Sampler> defaultSampler;
  Handle<Texture> defaultTexture;
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
  auto initDescriptors() -> void;
  auto syncDescriptors() -> void;
  auto defer(std::packaged_task<void()> &&task) -> void;
  auto processReadyTasks() -> void;
  auto processAllTasks() -> void;

#ifndef NDEBUG
  static auto debugMessengerCallback(
      VkDebugUtilsMessageSeverityFlagBitsEXT messageSeverity,
      VkDebugUtilsMessageTypeFlagsEXT messageTypes,
      const VkDebugUtilsMessengerCallbackDataEXT *pCallbackData,
      void *pUserData) -> VkBool32;
#endif
};
