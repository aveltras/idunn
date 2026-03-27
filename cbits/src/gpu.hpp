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
#include <vector>
#include <volk.h>
#include <vk_mem_alloc.h>
#include <SDL3/SDL_video.h>

struct Surface;

struct Gpu {
  friend Surface;

  explicit Gpu(idunn_gpu_config *config);
  ~Gpu();

private:
  VkInstance instance;
  VkAllocationCallbacks *allocationCallbacks = nullptr;
  VkPhysicalDevice physicalDevice;
  uint32_t graphicsFamilyIndex;
  VkDevice device;
  VkQueue graphicsQueue;
  VkCommandPool graphicsCommandPool;
  VmaAllocator allocator;
#ifndef NDEBUG
  VkDebugUtilsMessengerEXT debugUtilsMessenger;
#endif

  static auto checkRequiredLayers(const std::vector<const char *> &layers) -> bool;
  static auto checkRequiredInstanceExtensions(const std::vector<const char *> &extensions) -> bool;
  static auto checkExtensions(const std::vector<VkExtensionProperties> &availableExtensions, const std::vector<const char *> &extensions) -> bool;
  auto initInstance(const char *appName, uint32_t appVersion, uint32_t apiVersion, const std::vector<const char *> &layers, const std::vector<const char *> &extensions) -> bool;
  auto selectPhysicalDevice(uint32_t apiVersion, const std::vector<const char *> &requiredExtensions) -> bool;
  auto initDevice(const std::vector<const char *> &layers, const std::vector<const char *> &extensions) -> bool;

#ifndef NDEBUG
  static auto debugMessengerCallback(
      VkDebugUtilsMessageSeverityFlagBitsEXT messageSeverity,
      VkDebugUtilsMessageTypeFlagsEXT messageTypes,
      const VkDebugUtilsMessengerCallbackDataEXT *pCallbackData,
      void *pUserData) -> VkBool32;
#endif
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
  std::vector<VkFence> frameFences;
  std::vector<VkCommandBuffer> frameCommandBuffers;
  uint32_t frameNumber = 0;

  auto initSwapchain(uint32_t width, uint32_t height) -> void;
  auto cleanupSwapchainResources() -> void;
};
