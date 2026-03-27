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

#define VOLK_IMPLEMENTATION
#define VMA_IMPLEMENTATION
#define VMA_STATIC_VULKAN_FUNCTIONS 0
#define VMA_DYNAMIC_VULKAN_FUNCTIONS 0
#include "gpu.hpp"
#include "logger.hpp"
#include <cassert>
#include <format>
#include <string>
#include <SDL3/SDL_vulkan.h>

extern "C" {
void idunn_gpu_init(idunn_gpu_config *config, void **pGpu) { *pGpu = new Gpu(config); }
void idunn_gpu_uninit(void *gpu) { delete static_cast<Gpu *>(gpu); }
}

#define VK_CHECK(func)                     \
  do {                                     \
    VkResult vkResult = (func);            \
    if (vkResult != VK_SUCCESS) {          \
      LOG_ERROR("vkResult: %i", vkResult); \
      assert(false && "VKCHECK");          \
    }                                      \
  } while (0)

Gpu::Gpu(idunn_gpu_config *config) {
  LOG_DEBUG("Gpu");

  VK_CHECK(volkInitialize());

  auto apiVersion = VK_API_VERSION_1_3;
  std::vector<const char *> requiredLayers;
  std::vector<const char *> requiredInstanceExtensions;
  std::vector<const char *> requiredDeviceExtensions;

  uint32_t sdlExtensionsCount = 0;
  const char *const *sdlExtensions = SDL_Vulkan_GetInstanceExtensions(&sdlExtensionsCount);
  requiredInstanceExtensions.reserve(sdlExtensionsCount);
  for (uint32_t i = 0; i < sdlExtensionsCount; i++) {
    requiredInstanceExtensions.emplace_back(sdlExtensions[i]);
  }

#ifndef NDEBUG
  requiredLayers.emplace_back("VK_LAYER_KHRONOS_validation");
  requiredInstanceExtensions.emplace_back(VK_EXT_DEBUG_UTILS_EXTENSION_NAME);
#endif

  requiredDeviceExtensions.emplace_back(VK_KHR_SWAPCHAIN_EXTENSION_NAME);
  requiredDeviceExtensions.emplace_back(VK_KHR_SPIRV_1_4_EXTENSION_NAME);
  requiredDeviceExtensions.emplace_back(VK_KHR_SYNCHRONIZATION_2_EXTENSION_NAME);
  requiredDeviceExtensions.emplace_back(VK_KHR_CREATE_RENDERPASS_2_EXTENSION_NAME);

  assert(checkRequiredLayers(requiredLayers));
  assert(checkRequiredInstanceExtensions(requiredInstanceExtensions));
  assert(initInstance(config->appName, config->version, apiVersion, requiredLayers, requiredInstanceExtensions));

  volkLoadInstance(instance);

#ifndef NDEBUG
  VkDebugUtilsMessengerCreateInfoEXT debugUtilsMessengerCreateInfoEXT = {};
  debugUtilsMessengerCreateInfoEXT.sType = VK_STRUCTURE_TYPE_DEBUG_UTILS_MESSENGER_CREATE_INFO_EXT;
  debugUtilsMessengerCreateInfoEXT.messageSeverity |= VK_DEBUG_UTILS_MESSAGE_SEVERITY_VERBOSE_BIT_EXT;
  debugUtilsMessengerCreateInfoEXT.messageSeverity |= VK_DEBUG_UTILS_MESSAGE_SEVERITY_INFO_BIT_EXT;
  debugUtilsMessengerCreateInfoEXT.messageSeverity |= VK_DEBUG_UTILS_MESSAGE_SEVERITY_WARNING_BIT_EXT;
  debugUtilsMessengerCreateInfoEXT.messageSeverity |= VK_DEBUG_UTILS_MESSAGE_SEVERITY_ERROR_BIT_EXT;
  debugUtilsMessengerCreateInfoEXT.messageType |= VK_DEBUG_UTILS_MESSAGE_TYPE_GENERAL_BIT_EXT;
  debugUtilsMessengerCreateInfoEXT.messageType |= VK_DEBUG_UTILS_MESSAGE_TYPE_VALIDATION_BIT_EXT;
  debugUtilsMessengerCreateInfoEXT.pfnUserCallback = (PFN_vkDebugUtilsMessengerCallbackEXT)debugMessengerCallback;
  debugUtilsMessengerCreateInfoEXT.pUserData = nullptr;
  VK_CHECK(vkCreateDebugUtilsMessengerEXT(instance, &debugUtilsMessengerCreateInfoEXT, allocationCallbacks, &debugUtilsMessenger));
#endif

  assert(selectPhysicalDevice(apiVersion, requiredDeviceExtensions));
  assert(initDevice(requiredLayers, requiredDeviceExtensions));

  volkLoadDevice(device);

  vkGetDeviceQueue(device, graphicsFamilyIndex, 0, &graphicsQueue);

  VkCommandPoolCreateInfo commandPoolInfo{};
  commandPoolInfo.sType = VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO;
  commandPoolInfo.queueFamilyIndex = graphicsFamilyIndex;
  commandPoolInfo.flags |= VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT;
  commandPoolInfo.flags |= VK_COMMAND_POOL_CREATE_TRANSIENT_BIT;
  VK_CHECK(vkCreateCommandPool(device, &commandPoolInfo, allocationCallbacks, &graphicsCommandPool));

  VmaAllocatorCreateInfo allocatorCreateInfo{};
  allocatorCreateInfo.vulkanApiVersion = apiVersion;
  allocatorCreateInfo.physicalDevice = physicalDevice;
  allocatorCreateInfo.device = device;
  allocatorCreateInfo.instance = instance;
  allocatorCreateInfo.flags |= VMA_ALLOCATOR_CREATE_EXT_MEMORY_BUDGET_BIT;
  allocatorCreateInfo.flags |= VMA_ALLOCATOR_CREATE_BUFFER_DEVICE_ADDRESS_BIT;

  VmaVulkanFunctions vulkanFunctions{};
  VK_CHECK(vmaImportVulkanFunctionsFromVolk(&allocatorCreateInfo, &vulkanFunctions));
  allocatorCreateInfo.pVulkanFunctions = &vulkanFunctions;

  VK_CHECK(vmaCreateAllocator(&allocatorCreateInfo, &allocator));
  assert(allocator != VK_NULL_HANDLE);
}

Gpu::~Gpu() {
  vmaDestroyAllocator(allocator);
  vkDestroyCommandPool(device, graphicsCommandPool, allocationCallbacks);
  vkDestroyDevice(device, allocationCallbacks);
#ifndef NDEBUG
  vkDestroyDebugUtilsMessengerEXT(instance, debugUtilsMessenger, allocationCallbacks);
#endif
  vkDestroyInstance(instance, allocationCallbacks);
  LOG_DEBUG("~Gpu");
}

auto Gpu::checkRequiredLayers(const std::vector<const char *> &layers) -> bool {
  uint32_t availableLayerCount = 0;
  VK_CHECK(vkEnumerateInstanceLayerProperties(&availableLayerCount, nullptr));
  std::vector<VkLayerProperties> availableLayers(availableLayerCount);
  VK_CHECK(vkEnumerateInstanceLayerProperties(&availableLayerCount, availableLayers.data()));

  bool missingLayer = false;
  bool layerFound;
  for (const auto *requiredLayer : layers) {
    layerFound = false;
    for (const auto &availableLayer : availableLayers) {
      if (strcmp(static_cast<const char *>(availableLayer.layerName), requiredLayer) == 0) {
        layerFound = true;
        break;
      }
    }

    if (!layerFound) {
      LOG_ERROR("Vulkan: required layer missing: %s", requiredLayer);
      missingLayer = true;
    }
  }

  return !missingLayer;
}

auto Gpu::checkRequiredInstanceExtensions(const std::vector<const char *> &extensions) -> bool {
  uint32_t availableExtensionCount = 0;
  VK_CHECK(vkEnumerateInstanceExtensionProperties(nullptr, &availableExtensionCount, nullptr));
  std::vector<VkExtensionProperties> availableExtensions(availableExtensionCount);
  VK_CHECK(vkEnumerateInstanceExtensionProperties(nullptr, &availableExtensionCount, availableExtensions.data()));
  return checkExtensions(availableExtensions, extensions);
}

auto Gpu::checkExtensions(const std::vector<VkExtensionProperties> &availableExtensions, const std::vector<const char *> &extensions) -> bool {
  bool missingExtension = false;
  bool extensionFound;
  for (const auto *requiredExtension : extensions) {
    extensionFound = false;
    for (const auto &availableExtension : availableExtensions) {
      if (strcmp(static_cast<const char *>(availableExtension.extensionName), requiredExtension) == 0) {
        extensionFound = true;
        break;
      }
    }

    if (!extensionFound) {
      missingExtension = true;
      LOG_ERROR("Vulkan: required extension missing: %s", requiredExtension);
    }
  }

  return !missingExtension;
}

#ifndef NDEBUG
auto Gpu::debugMessengerCallback(
    VkDebugUtilsMessageSeverityFlagBitsEXT messageSeverity,
    VkDebugUtilsMessageTypeFlagsEXT messageTypes,
    const VkDebugUtilsMessengerCallbackDataEXT *pCallbackData,
    void *pUserData) -> VkBool32 {
  switch (messageSeverity) {
  case VK_DEBUG_UTILS_MESSAGE_SEVERITY_ERROR_BIT_EXT:
    LOG_ERROR("Vulkan: %s - %s", pCallbackData->pMessageIdName, pCallbackData->pMessage);
    break;
  case VK_DEBUG_UTILS_MESSAGE_SEVERITY_WARNING_BIT_EXT:
    LOG_WARNING("Vulkan: %s - %s", pCallbackData->pMessageIdName, pCallbackData->pMessage);
    break;
  case VK_DEBUG_UTILS_MESSAGE_SEVERITY_INFO_BIT_EXT:
    LOG_INFO("Vulkan: %s - %s", pCallbackData->pMessageIdName, pCallbackData->pMessage);
    break;
  case VK_DEBUG_UTILS_MESSAGE_SEVERITY_VERBOSE_BIT_EXT:
  default:
    LOG_DEBUG("Vulkan: %s - %s", pCallbackData->pMessageIdName, pCallbackData->pMessage);
    break;
  }
  return VK_FALSE;
}
#endif

auto Gpu::initInstance(
    const char *appName,
    uint32_t appVersion,
    uint32_t apiVersion,
    const std::vector<const char *> &layers,
    const std::vector<const char *> &extensions) -> bool {
  VkApplicationInfo applicationInfo = {};
  applicationInfo.sType = VK_STRUCTURE_TYPE_APPLICATION_INFO;
  applicationInfo.pApplicationName = appName;
  applicationInfo.applicationVersion = appVersion;
  applicationInfo.apiVersion = apiVersion;

  VkInstanceCreateInfo instanceCreateInfo = {};
  instanceCreateInfo.sType = VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO;
  instanceCreateInfo.pApplicationInfo = &applicationInfo;
  instanceCreateInfo.enabledLayerCount = layers.size();
  instanceCreateInfo.ppEnabledLayerNames = layers.data();
  instanceCreateInfo.enabledExtensionCount = extensions.size();
  instanceCreateInfo.ppEnabledExtensionNames = extensions.data();

#ifndef NDEBUG
  std::vector<VkValidationFeatureEnableEXT> enabledValidationFeatures;
  enabledValidationFeatures.emplace_back(VK_VALIDATION_FEATURE_ENABLE_DEBUG_PRINTF_EXT);

  VkValidationFeaturesEXT validationFeatures = {};
  validationFeatures.sType = VK_STRUCTURE_TYPE_VALIDATION_FEATURES_EXT;
  validationFeatures.enabledValidationFeatureCount = enabledValidationFeatures.size();
  validationFeatures.pEnabledValidationFeatures = enabledValidationFeatures.data();

  instanceCreateInfo.pNext = &validationFeatures;
#endif

  VK_CHECK(vkCreateInstance(&instanceCreateInfo, allocationCallbacks, &instance));

  return instance != VK_NULL_HANDLE;
}

auto Gpu::selectPhysicalDevice(uint32_t apiVersion, const std::vector<const char *> &requiredExtensions) -> bool {
  uint32_t availableDeviceCount = 0;
  VK_CHECK(vkEnumeratePhysicalDevices(instance, &availableDeviceCount, nullptr));
  std::vector<VkPhysicalDevice> availableDevices(availableDeviceCount);
  VK_CHECK(vkEnumeratePhysicalDevices(instance, &availableDeviceCount, availableDevices.data()));

  physicalDevice = VK_NULL_HANDLE;
  graphicsFamilyIndex = UINT32_MAX;

  for (uint32_t deviceIdx = 0; deviceIdx < availableDeviceCount; deviceIdx++) {
    VkPhysicalDeviceProperties2 deviceProperties{};
    deviceProperties.sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_PROPERTIES_2;

    vkGetPhysicalDeviceProperties2(availableDevices[deviceIdx], &deviceProperties);

    if (deviceProperties.properties.apiVersion < apiVersion) {
      continue;
    }

    uint32_t availableDeviceExtensionCount = 0;
    VK_CHECK(vkEnumerateDeviceExtensionProperties(availableDevices[deviceIdx], nullptr, &availableDeviceExtensionCount, nullptr));
    std::vector<VkExtensionProperties> availableDeviceExtensions(availableDeviceExtensionCount);
    VK_CHECK(vkEnumerateDeviceExtensionProperties(availableDevices[deviceIdx], nullptr, &availableDeviceExtensionCount, availableDeviceExtensions.data()));
    if (!checkExtensions(availableDeviceExtensions, requiredExtensions)) {
      continue;
    }

    VkQueueFamilyProperties2 queueFamilyProperties2{};
    queueFamilyProperties2.sType = VK_STRUCTURE_TYPE_QUEUE_FAMILY_PROPERTIES_2;

    uint32_t queueFamilyPropertyCount = 0;
    vkGetPhysicalDeviceQueueFamilyProperties2(availableDevices[deviceIdx], &queueFamilyPropertyCount, nullptr);
    std::vector<VkQueueFamilyProperties2> availableQueueFamilyProperties(queueFamilyPropertyCount, queueFamilyProperties2);
    vkGetPhysicalDeviceQueueFamilyProperties2(availableDevices[deviceIdx], &queueFamilyPropertyCount, availableQueueFamilyProperties.data());

    for (uint32_t queueFamilyIdx = 0; queueFamilyIdx < queueFamilyPropertyCount; ++queueFamilyIdx) {
      if ((availableQueueFamilyProperties[queueFamilyIdx].queueFamilyProperties.queueFlags & VK_QUEUE_GRAPHICS_BIT) != 0U) {
        physicalDevice = availableDevices[deviceIdx];
        graphicsFamilyIndex = queueFamilyIdx;
        break;
      }

      if (physicalDevice != VK_NULL_HANDLE) {
        break;
      }
    }
  }

  return physicalDevice != VK_NULL_HANDLE;
}

auto Gpu::initDevice(const std::vector<const char *> &layers, const std::vector<const char *> &extensions) -> bool {
  VkPhysicalDeviceExtendedDynamicStateFeaturesEXT extendedDynamicStateFeatures = {};
  extendedDynamicStateFeatures.sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_EXTENDED_DYNAMIC_STATE_FEATURES_EXT;
  extendedDynamicStateFeatures.pNext = nullptr;
  extendedDynamicStateFeatures.extendedDynamicState = VK_TRUE;

  VkPhysicalDeviceVulkan13Features vulkan13Features = {};
  vulkan13Features.sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_VULKAN_1_3_FEATURES;
  vulkan13Features.pNext = &extendedDynamicStateFeatures;
  vulkan13Features.synchronization2 = VK_TRUE;
  vulkan13Features.dynamicRendering = VK_TRUE;

  VkPhysicalDeviceVulkan12Features vulkan12Features = {};
  vulkan12Features.sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_VULKAN_1_2_FEATURES;
  vulkan12Features.pNext = &vulkan13Features;
  vulkan12Features.bufferDeviceAddress = VK_TRUE;

  VkPhysicalDeviceVulkan11Features vulkan11Features = {};
  vulkan11Features.sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_VULKAN_1_1_FEATURES;
  vulkan11Features.pNext = &vulkan12Features;
  vulkan11Features.shaderDrawParameters = VK_TRUE;

  VkPhysicalDeviceFeatures2 deviceFeatures = {};
  deviceFeatures.sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_FEATURES_2;
  deviceFeatures.pNext = &vulkan11Features;
  deviceFeatures.features.shaderInt64 = VK_TRUE;
  deviceFeatures.features.sampleRateShading = VK_TRUE;
  deviceFeatures.features.multiDrawIndirect = VK_TRUE;
  vkGetPhysicalDeviceFeatures2(physicalDevice, &deviceFeatures);

  float priority = 1.0F;

  VkDeviceQueueCreateInfo deviceQueueCreateInfo = {};
  deviceQueueCreateInfo.sType = VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO;
  deviceQueueCreateInfo.queueFamilyIndex = graphicsFamilyIndex;
  deviceQueueCreateInfo.queueCount = 1;
  deviceQueueCreateInfo.pQueuePriorities = &priority;

  VkDeviceCreateInfo deviceCreateInfo = {};
  deviceCreateInfo.sType = VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO;
  deviceCreateInfo.pNext = &deviceFeatures;
  deviceCreateInfo.queueCreateInfoCount = 1;
  deviceCreateInfo.pQueueCreateInfos = &deviceQueueCreateInfo;
  deviceCreateInfo.enabledLayerCount = layers.size();
  deviceCreateInfo.ppEnabledLayerNames = layers.data();
  deviceCreateInfo.enabledExtensionCount = extensions.size();
  deviceCreateInfo.ppEnabledExtensionNames = extensions.data();

  VK_CHECK(vkCreateDevice(physicalDevice, &deviceCreateInfo, allocationCallbacks, &device));

  return device != VK_NULL_HANDLE;
}

Surface::Surface(Gpu *gpu, SDL_Window *window, uint32_t width, uint32_t height) : gpu(gpu) {
  LOG_DEBUG("Surface");
  bool surfaceOk = SDL_Vulkan_CreateSurface(window, gpu->instance, gpu->allocationCallbacks, &surface);
  assert(surfaceOk && "SDL failed creating surface");
  assert(surface != VK_NULL_HANDLE);
  initSwapchain(width, height);

  VkFenceCreateInfo fenceCreateInfo{};
  fenceCreateInfo.sType = VK_STRUCTURE_TYPE_FENCE_CREATE_INFO;
  fenceCreateInfo.flags |= VK_FENCE_CREATE_SIGNALED_BIT;

  VkSemaphoreCreateInfo semaphoreCreateInfo = {};
  semaphoreCreateInfo.sType = VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO;

  frameFences.resize(2); // TODO: from config
  frameCommandBuffers.resize(frameFences.size());

  VkCommandBufferAllocateInfo commandBufferAllocateInfo = {};
  commandBufferAllocateInfo.sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO;
  commandBufferAllocateInfo.commandPool = gpu->graphicsCommandPool;
  commandBufferAllocateInfo.level = VK_COMMAND_BUFFER_LEVEL_PRIMARY;
  commandBufferAllocateInfo.commandBufferCount = frameCommandBuffers.size();
  VK_CHECK(vkAllocateCommandBuffers(gpu->device, &commandBufferAllocateInfo, frameCommandBuffers.data()));

  for (auto i = 0; i < frameFences.size(); i++) {
    VK_CHECK(vkCreateFence(gpu->device, &fenceCreateInfo, gpu->allocationCallbacks, &frameFences[i]));
#ifndef NDEBUG
    VkDebugUtilsObjectNameInfoEXT debugUtilsObjectNameInfoEXT = {};
    debugUtilsObjectNameInfoEXT.sType = VK_STRUCTURE_TYPE_DEBUG_UTILS_OBJECT_NAME_INFO_EXT;

    std::string fenceName = std::format("Frame {} Fence", i);
    debugUtilsObjectNameInfoEXT.pObjectName = fenceName.c_str();
    debugUtilsObjectNameInfoEXT.objectType = VK_OBJECT_TYPE_FENCE;
    debugUtilsObjectNameInfoEXT.objectHandle = (uint64_t)frameFences[i];
    VK_CHECK(vkSetDebugUtilsObjectNameEXT(gpu->device, &debugUtilsObjectNameInfoEXT));

    std::string commandBufferName = std::format("Frame {} Command Buffer", i);
    debugUtilsObjectNameInfoEXT.pObjectName = commandBufferName.c_str();
    debugUtilsObjectNameInfoEXT.objectType = VK_OBJECT_TYPE_COMMAND_BUFFER;
    debugUtilsObjectNameInfoEXT.objectHandle = (uint64_t)frameCommandBuffers[i];
    VK_CHECK(vkSetDebugUtilsObjectNameEXT(gpu->device, &debugUtilsObjectNameInfoEXT));
#endif
  }
}

Surface::~Surface() {
  vkDeviceWaitIdle(gpu->device);
  cleanupSwapchainResources();
  vkDestroySwapchainKHR(gpu->device, swapchain, gpu->allocationCallbacks);
  for (auto &frameFence : frameFences) {
    vkDestroyFence(gpu->device, frameFence, gpu->allocationCallbacks);
  }
  vkDestroySurfaceKHR(gpu->instance, surface, gpu->allocationCallbacks);
  LOG_DEBUG("~Surface");
};

auto Surface::initSwapchain(uint32_t width, uint32_t height) -> void {
  if (swapchain != VK_NULL_HANDLE) {
    cleanupSwapchainResources();
  }

  VkSurfaceCapabilitiesKHR surfaceCapabilities = {};
  VK_CHECK(vkGetPhysicalDeviceSurfaceCapabilitiesKHR(gpu->physicalDevice, surface, &surfaceCapabilities));

  uint32_t surfaceFormatCount = 0;
  VK_CHECK(vkGetPhysicalDeviceSurfaceFormatsKHR(gpu->physicalDevice, surface, &surfaceFormatCount, nullptr));
  std::vector<VkSurfaceFormatKHR> availableSurfaceFormats(surfaceFormatCount);
  VK_CHECK(vkGetPhysicalDeviceSurfaceFormatsKHR(gpu->physicalDevice, surface, &surfaceFormatCount, availableSurfaceFormats.data()));

  format = availableSurfaceFormats[0];
  for (uint32_t i = 0; i < surfaceFormatCount; i++) {
    if (availableSurfaceFormats[i].format == VK_FORMAT_B8G8R8A8_SRGB && availableSurfaceFormats[i].colorSpace == VK_COLOR_SPACE_SRGB_NONLINEAR_KHR) {
      format = availableSurfaceFormats[i];
      break;
    }
  }

  VkPresentModeKHR presentMode = VK_PRESENT_MODE_FIFO_KHR;
  // uint32_t presentModeCount = 0;
  // VK_CHECK(vkGetPhysicalDeviceSurfacePresentModesKHR(gpu.>physicalDevice, surface, &presentModeCount, NULL));
  // std::vector<VkPresentModeKHR> availablePresentModes(presentModeCount);
  // VK_CHECK(vkGetPhysicalDeviceSurfacePresentModesKHR(gpu.>physicalDevice, surface, &presentModeCount, availablePresentModes.data()));

  // for (uint32_t i = 0; i < presentModeCount; i++) {
  //   if (availablePresentModes[i] == VK_PRESENT_MODE_MAILBOX_KHR) {
  //     presentMode = VK_PRESENT_MODE_MAILBOX_KHR;
  //     break;
  //   }
  // }

  extent.width = std::max(std::min(width, surfaceCapabilities.maxImageExtent.width), surfaceCapabilities.minImageExtent.width);
  extent.height = std::max(std::min(height, surfaceCapabilities.maxImageExtent.height), surfaceCapabilities.minImageExtent.height);

  uint32_t imageCount = surfaceCapabilities.minImageCount + 1;
  if (surfaceCapabilities.maxImageCount > 0 && imageCount > surfaceCapabilities.maxImageCount) {
    imageCount = surfaceCapabilities.maxImageCount;
  }

  VkSwapchainCreateInfoKHR swapchainCreateInfo = {};
  swapchainCreateInfo.sType = VK_STRUCTURE_TYPE_SWAPCHAIN_CREATE_INFO_KHR;
  swapchainCreateInfo.surface = surface;
  swapchainCreateInfo.minImageCount = imageCount;
  swapchainCreateInfo.imageFormat = format.format;
  swapchainCreateInfo.imageColorSpace = format.colorSpace;
  swapchainCreateInfo.imageExtent = extent;
  swapchainCreateInfo.imageArrayLayers = 1;
  swapchainCreateInfo.imageUsage = VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT;
  swapchainCreateInfo.imageSharingMode = VK_SHARING_MODE_EXCLUSIVE;
  swapchainCreateInfo.preTransform = surfaceCapabilities.currentTransform;
  swapchainCreateInfo.compositeAlpha = VK_COMPOSITE_ALPHA_OPAQUE_BIT_KHR;
  swapchainCreateInfo.presentMode = presentMode;
  swapchainCreateInfo.clipped = VK_TRUE;
  swapchainCreateInfo.oldSwapchain = swapchain;

  VkSemaphoreCreateInfo semaphoreCreateInfo = {};
  semaphoreCreateInfo.sType = VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO;

  VK_CHECK(vkCreateSwapchainKHR(gpu->device, &swapchainCreateInfo, gpu->allocationCallbacks, &swapchain));
  assert(swapchain != VK_NULL_HANDLE);

  uint32_t swapchainImageCount = 0;
  VK_CHECK(vkGetSwapchainImagesKHR(gpu->device, swapchain, &swapchainImageCount, nullptr));
  images.resize(swapchainImageCount);
  imageViews.resize(swapchainImageCount);
  readyForRender.resize(swapchainImageCount);
  readyForPresent.resize(swapchainImageCount);
  VK_CHECK(vkGetSwapchainImagesKHR(gpu->device, swapchain, &swapchainImageCount, images.data()));

  VkImageViewCreateInfo imageViewCreateInfo = {};
  imageViewCreateInfo.sType = VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO;
  imageViewCreateInfo.viewType = VK_IMAGE_VIEW_TYPE_2D;
  imageViewCreateInfo.format = format.format;
  imageViewCreateInfo.components.r = VK_COMPONENT_SWIZZLE_IDENTITY;
  imageViewCreateInfo.components.g = VK_COMPONENT_SWIZZLE_IDENTITY;
  imageViewCreateInfo.components.b = VK_COMPONENT_SWIZZLE_IDENTITY;
  imageViewCreateInfo.components.a = VK_COMPONENT_SWIZZLE_IDENTITY;
  imageViewCreateInfo.subresourceRange.aspectMask = VK_IMAGE_ASPECT_COLOR_BIT;
  imageViewCreateInfo.subresourceRange.baseMipLevel = 0;
  imageViewCreateInfo.subresourceRange.levelCount = VK_REMAINING_MIP_LEVELS;
  imageViewCreateInfo.subresourceRange.baseArrayLayer = 0;
  imageViewCreateInfo.subresourceRange.layerCount = 1;

  for (uint32_t i = 0; i < images.size(); i++) {
    imageViewCreateInfo.image = images[i];
    VK_CHECK(vkCreateSemaphore(gpu->device, &semaphoreCreateInfo, gpu->allocationCallbacks, &readyForRender[i]));
    VK_CHECK(vkCreateSemaphore(gpu->device, &semaphoreCreateInfo, gpu->allocationCallbacks, &readyForPresent[i]));
    VK_CHECK(vkCreateImageView(gpu->device, &imageViewCreateInfo, gpu->allocationCallbacks, &imageViews[i]));
#ifndef NDEBUG
    std::string imageName = std::format("Swapchain Image {}", i);
    std::string readyForRenderName = std::format("Swapchain Image {} Ready For Render Semaphore", i);
    std::string readyForPresentName = std::format("Swapchain Image {} Ready For Present Semaphore", i);
    std::string imageViewName = std::format("Swapchain Image {} View", i);

    VkDebugUtilsObjectNameInfoEXT debugUtilsObjectNameInfoEXT = {};
    debugUtilsObjectNameInfoEXT.sType = VK_STRUCTURE_TYPE_DEBUG_UTILS_OBJECT_NAME_INFO_EXT;

    debugUtilsObjectNameInfoEXT.pObjectName = imageName.c_str();
    debugUtilsObjectNameInfoEXT.objectType = VK_OBJECT_TYPE_IMAGE;
    debugUtilsObjectNameInfoEXT.objectHandle = (uint64_t)images[i];
    VK_CHECK(vkSetDebugUtilsObjectNameEXT(gpu->device, &debugUtilsObjectNameInfoEXT));

    debugUtilsObjectNameInfoEXT.pObjectName = imageViewName.c_str();
    debugUtilsObjectNameInfoEXT.objectType = VK_OBJECT_TYPE_IMAGE_VIEW;
    debugUtilsObjectNameInfoEXT.objectHandle = (uint64_t)imageViews[i];
    VK_CHECK(vkSetDebugUtilsObjectNameEXT(gpu->device, &debugUtilsObjectNameInfoEXT));

    debugUtilsObjectNameInfoEXT.pObjectName = readyForRenderName.c_str();
    debugUtilsObjectNameInfoEXT.objectType = VK_OBJECT_TYPE_SEMAPHORE;
    debugUtilsObjectNameInfoEXT.objectHandle = (uint64_t)readyForRender[i];
    VK_CHECK(vkSetDebugUtilsObjectNameEXT(gpu->device, &debugUtilsObjectNameInfoEXT));

    debugUtilsObjectNameInfoEXT.pObjectName = readyForPresentName.c_str();
    debugUtilsObjectNameInfoEXT.objectType = VK_OBJECT_TYPE_SEMAPHORE;
    debugUtilsObjectNameInfoEXT.objectHandle = (uint64_t)readyForPresent[i];
    VK_CHECK(vkSetDebugUtilsObjectNameEXT(gpu->device, &debugUtilsObjectNameInfoEXT));
#endif
  }
}

auto Surface::cleanupSwapchainResources() -> void {
  for (uint32_t i = 0; i < images.size(); i++) {
    vkDestroyImageView(gpu->device, imageViews[i], gpu->allocationCallbacks);
    vkDestroySemaphore(gpu->device, readyForRender[i], gpu->allocationCallbacks);
    vkDestroySemaphore(gpu->device, readyForPresent[i], gpu->allocationCallbacks);
  }
}

auto Surface::draw(uint32_t width, uint32_t height, float clearColor) -> void {
  if (width != extent.width || height != extent.height) {
    initSwapchain(width, height);
  }

  const VkFence fence = frameFences[frameNumber % frameFences.size()];
  assert(fence != VK_NULL_HANDLE);

  while (vkWaitForFences(gpu->device, 1, &fence, VK_TRUE, UINT64_MAX) == VK_TIMEOUT) {
    ;
  }
  VK_CHECK(vkResetFences(gpu->device, 1, &fence));

  VkSemaphore imageReadyForRender = readyForRender[frameNumber % readyForRender.size()];

  uint32_t swapchainImageIndex = {};
  VkResult acquireResult = vkAcquireNextImageKHR(gpu->device, swapchain, UINT64_MAX, imageReadyForRender, VK_NULL_HANDLE, &swapchainImageIndex);
  VkSemaphore imageReadyForPresent = readyForPresent[swapchainImageIndex];

  VkCommandBufferBeginInfo commandBufferBeginInfo = {};
  commandBufferBeginInfo.sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO;
  commandBufferBeginInfo.flags = VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT;
  commandBufferBeginInfo.pInheritanceInfo = nullptr;

  VkCommandBuffer commandBuffer = frameCommandBuffers[frameNumber % frameCommandBuffers.size()];
  assert(commandBuffer != VK_NULL_HANDLE);

  VK_CHECK(vkResetCommandBuffer(commandBuffer, 0));
  VK_CHECK(vkBeginCommandBuffer(commandBuffer, &commandBufferBeginInfo));

  VkImageMemoryBarrier2 imageMemoryBarrier2 = {};
  imageMemoryBarrier2.sType = VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER_2;
  imageMemoryBarrier2.srcStageMask = VK_PIPELINE_STAGE_2_TOP_OF_PIPE_BIT;
  imageMemoryBarrier2.srcAccessMask = 0;
  imageMemoryBarrier2.dstStageMask = VK_PIPELINE_STAGE_2_COLOR_ATTACHMENT_OUTPUT_BIT;
  imageMemoryBarrier2.dstAccessMask = VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT;
  imageMemoryBarrier2.oldLayout = VK_IMAGE_LAYOUT_UNDEFINED;
  imageMemoryBarrier2.newLayout = VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL;
  imageMemoryBarrier2.srcQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED;
  imageMemoryBarrier2.dstQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED;
  imageMemoryBarrier2.image = images[swapchainImageIndex];
  imageMemoryBarrier2.subresourceRange.aspectMask = VK_IMAGE_ASPECT_COLOR_BIT;
  imageMemoryBarrier2.subresourceRange.baseMipLevel = 0;
  imageMemoryBarrier2.subresourceRange.levelCount = 1;
  imageMemoryBarrier2.subresourceRange.baseArrayLayer = 0;
  imageMemoryBarrier2.subresourceRange.layerCount = 1;

  VkDependencyInfo dependencyInfo = {};
  dependencyInfo.sType = VK_STRUCTURE_TYPE_DEPENDENCY_INFO;
  dependencyInfo.imageMemoryBarrierCount = 1;
  dependencyInfo.pImageMemoryBarriers = &imageMemoryBarrier2;

  vkCmdPipelineBarrier2(commandBuffer, &dependencyInfo);

  VkClearColorValue clearColorValue = {.float32 = {clearColor, 0.0F, 0.0F, 0.0F}};

  VkRenderingAttachmentInfo renderingAttachmentInfo = {};
  renderingAttachmentInfo.sType = VK_STRUCTURE_TYPE_RENDERING_ATTACHMENT_INFO;
  renderingAttachmentInfo.imageView = imageViews[swapchainImageIndex];
  renderingAttachmentInfo.imageLayout = VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL;
  renderingAttachmentInfo.loadOp = VK_ATTACHMENT_LOAD_OP_CLEAR;
  renderingAttachmentInfo.storeOp = VK_ATTACHMENT_STORE_OP_STORE;
  renderingAttachmentInfo.clearValue.color = clearColorValue;

  VkRenderingInfo renderingInfo = {};
  renderingInfo.sType = VK_STRUCTURE_TYPE_RENDERING_INFO;
  renderingInfo.layerCount = 1;
  renderingInfo.colorAttachmentCount = 1;
  renderingInfo.pColorAttachments = &renderingAttachmentInfo;
  renderingInfo.renderArea.extent = extent;
  renderingInfo.renderArea.offset.x = 0;
  renderingInfo.renderArea.offset.y = 0;

  vkCmdBeginRendering(commandBuffer, &renderingInfo);

  VkViewport viewport = {};
  viewport.x = 0;
  viewport.y = 0;
  viewport.width = (float)extent.width;
  viewport.height = (float)extent.height;
  viewport.minDepth = 0;
  viewport.maxDepth = 1;
  vkCmdSetViewport(commandBuffer, 0, 1, &viewport);

  assert(extent.width > 0);

  VkRect2D scissor = {};
  scissor.extent = extent;
  scissor.offset.x = 0;
  scissor.offset.y = 0;
  vkCmdSetScissor(commandBuffer, 0, 1, &scissor);

  vkCmdEndRendering(commandBuffer);

  imageMemoryBarrier2.sType = VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER_2;
  imageMemoryBarrier2.srcStageMask = VK_PIPELINE_STAGE_2_COLOR_ATTACHMENT_OUTPUT_BIT;
  imageMemoryBarrier2.srcAccessMask = VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT;
  imageMemoryBarrier2.dstStageMask = VK_PIPELINE_STAGE_2_BOTTOM_OF_PIPE_BIT;
  imageMemoryBarrier2.dstAccessMask = 0;
  imageMemoryBarrier2.oldLayout = VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL;
  imageMemoryBarrier2.newLayout = VK_IMAGE_LAYOUT_PRESENT_SRC_KHR;
  imageMemoryBarrier2.srcQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED;
  imageMemoryBarrier2.dstQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED;
  imageMemoryBarrier2.image = images[swapchainImageIndex];
  imageMemoryBarrier2.subresourceRange.aspectMask = VK_IMAGE_ASPECT_COLOR_BIT;
  imageMemoryBarrier2.subresourceRange.baseMipLevel = 0;
  imageMemoryBarrier2.subresourceRange.levelCount = 1;
  imageMemoryBarrier2.subresourceRange.baseArrayLayer = 0;
  imageMemoryBarrier2.subresourceRange.layerCount = 1;

  dependencyInfo.sType = VK_STRUCTURE_TYPE_DEPENDENCY_INFO;
  dependencyInfo.imageMemoryBarrierCount = 1;
  dependencyInfo.pImageMemoryBarriers = &imageMemoryBarrier2;

  vkCmdPipelineBarrier2(commandBuffer, &dependencyInfo);

  VK_CHECK(vkEndCommandBuffer(commandBuffer));

  VkSubmitInfo submitInfo = {};
  submitInfo.sType = VK_STRUCTURE_TYPE_SUBMIT_INFO;
  submitInfo.waitSemaphoreCount = 1;
  submitInfo.pWaitSemaphores = &imageReadyForRender;
  submitInfo.commandBufferCount = 1;
  submitInfo.pCommandBuffers = &commandBuffer;
  submitInfo.signalSemaphoreCount = 1;
  submitInfo.pSignalSemaphores = &imageReadyForPresent;
  std::array<VkPipelineStageFlags, 1> waitStages = {VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT};
  submitInfo.pWaitDstStageMask = waitStages.data();
  VK_CHECK(vkQueueSubmit(gpu->graphicsQueue, 1, &submitInfo, fence));

  VkPresentInfoKHR presentInfo = {};
  presentInfo.sType = VK_STRUCTURE_TYPE_PRESENT_INFO_KHR;
  presentInfo.waitSemaphoreCount = 1;
  presentInfo.pWaitSemaphores = &imageReadyForPresent;
  presentInfo.swapchainCount = 1;
  presentInfo.pSwapchains = &swapchain;
  presentInfo.pImageIndices = &swapchainImageIndex;
  VK_CHECK(vkQueuePresentKHR(gpu->graphicsQueue, &presentInfo));

  frameNumber++;
}
