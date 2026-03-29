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
#include <spirv_reflect.h>
#include <vulkan/utility/vk_format_utils.h>
#include <vulkan/vk_enum_string_helper.h>
#include <glm/glm.hpp>
#include <glm/vec4.hpp>
#include <glm/matrix.hpp>
#include <glm/ext.hpp>
#include <utility>

extern "C" {
void idunn_gpu_init(idunn_gpu_config *config, void **pGpu) {
  *pGpu = new Gpu(config);
}

void idunn_gpu_uninit(void *gpu) {
  delete static_cast<Gpu *>(gpu);
}

void idunn_gpu_world_init(void *gpu, idunn_gpu_world_config *config, uint64_t *pWorldHandle) {
  *pWorldHandle = static_cast<Gpu *>(gpu)->create(config).raw();
}

void idunn_gpu_world_uninit(void *gpu, uint64_t worldHandle) {
  static_cast<Gpu *>(gpu)->destroy(Handle<Gpu::World>(worldHandle));
}
}

#define VK_CHECK(func)                     \
  do {                                     \
    VkResult vkResult = (func);            \
    if (vkResult != VK_SUCCESS) {          \
      LOG_ERROR("vkResult: %i", vkResult); \
      assert(false && "VKCHECK");          \
    }                                      \
  } while (0)

constexpr uint32_t kMaxBindlessResources = 50;
constexpr uint32_t kDescriptorBindingCount = 3;
constexpr uint32_t kDescriptorBindingTextures = 0;
constexpr uint32_t kDescriptorBindingSamplers = 1;
constexpr uint32_t kDescriptorBindingStorageImages = 2;

Gpu::Gpu(idunn_gpu_config *config)
    : buffers(kMaxBindlessResources, [this](Buffer &buffer) -> void { destroy(buffer); }),
      pipelines(kMaxBindlessResources, [this](Pipeline &pipeline) -> void { destroy(pipeline); }),
      samplers(kMaxBindlessResources, [this](Sampler &sampler) -> void { destroy(sampler); }),
      surfaces(1, [this](Surface &surface) -> void { destroy(surface); }),
      textures(kMaxBindlessResources, [this](Texture &texture) -> void { destroy(texture); }),
      worlds(2, [this](World &world) -> void { destroy(world); }) {
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

  frameFences.resize(2); // TODO: from config
  frameCommandBuffers.resize(frameFences.size());

  VkCommandBufferAllocateInfo commandBufferAllocateInfo = {};
  commandBufferAllocateInfo.sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO;
  commandBufferAllocateInfo.commandPool = graphicsCommandPool;
  commandBufferAllocateInfo.level = VK_COMMAND_BUFFER_LEVEL_PRIMARY;
  commandBufferAllocateInfo.commandBufferCount = frameCommandBuffers.size();
  VK_CHECK(vkAllocateCommandBuffers(device, &commandBufferAllocateInfo, frameCommandBuffers.data()));

  VkFenceCreateInfo fenceCreateInfo{};
  fenceCreateInfo.sType = VK_STRUCTURE_TYPE_FENCE_CREATE_INFO;
  fenceCreateInfo.flags |= VK_FENCE_CREATE_SIGNALED_BIT;

  for (auto i = 0; i < frameFences.size(); i++) {
    VK_CHECK(vkCreateFence(device, &fenceCreateInfo, allocationCallbacks, &frameFences[i]));
#ifndef NDEBUG
    VkDebugUtilsObjectNameInfoEXT debugUtilsObjectNameInfoEXT = {};
    debugUtilsObjectNameInfoEXT.sType = VK_STRUCTURE_TYPE_DEBUG_UTILS_OBJECT_NAME_INFO_EXT;

    std::string fenceName = std::format("Frame {} Fence", i);
    debugUtilsObjectNameInfoEXT.pObjectName = fenceName.c_str();
    debugUtilsObjectNameInfoEXT.objectType = VK_OBJECT_TYPE_FENCE;
    debugUtilsObjectNameInfoEXT.objectHandle = (uint64_t)frameFences[i];
    VK_CHECK(vkSetDebugUtilsObjectNameEXT(device, &debugUtilsObjectNameInfoEXT));

    std::string commandBufferName = std::format("Frame {} Command Buffer", i);
    debugUtilsObjectNameInfoEXT.pObjectName = commandBufferName.c_str();
    debugUtilsObjectNameInfoEXT.objectType = VK_OBJECT_TYPE_COMMAND_BUFFER;
    debugUtilsObjectNameInfoEXT.objectHandle = (uint64_t)frameCommandBuffers[i];
    VK_CHECK(vkSetDebugUtilsObjectNameEXT(device, &debugUtilsObjectNameInfoEXT));
#endif
  }

  initSlangSession(config->shadersPath);
  initDescriptors();
}

Gpu::~Gpu() {
  buffers.clear();
  pipelines.clear();
  samplers.clear();
  textures.clear();
  surfaces.clear();
  processAllTasks();
  for (auto &frameFence : frameFences) {
    vkDestroyFence(device, frameFence, allocationCallbacks);
  }
  vkDestroyDescriptorPool(device, descriptorPool, allocationCallbacks);
  vkDestroyDescriptorSetLayout(device, descriptorSetLayout, allocationCallbacks);
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

auto Gpu::initSlangSession(const char *shadersPath) -> void {
  createGlobalSession(globalSlangSession.writeRef());

  slang::TargetDesc targetDesc = {};
  targetDesc.format = SLANG_SPIRV;
  targetDesc.profile = globalSlangSession->findProfile("spirv_1_5");

  slang::SessionDesc sessionDesc = {};
  sessionDesc.targets = &targetDesc;
  sessionDesc.targetCount = 1;
  sessionDesc.defaultMatrixLayoutMode = SLANG_MATRIX_LAYOUT_COLUMN_MAJOR;
  sessionDesc.searchPaths = &shadersPath;
  sessionDesc.searchPathCount = 1;

  slang::CompilerOptionEntry emitSpirVDirectly = {};
  emitSpirVDirectly.name = slang::CompilerOptionName::EmitSpirvDirectly;
  emitSpirVDirectly.value.intValue0 = 1;

  slang::CompilerOptionEntry debugInformation = {};
  debugInformation.name = slang::CompilerOptionName::DebugInformation;
  debugInformation.value.intValue0 = SLANG_DEBUG_INFO_LEVEL_STANDARD;

  slang::CompilerOptionEntry vulkanUseEntryPointName = {};
  vulkanUseEntryPointName.name = slang::CompilerOptionName::VulkanUseEntryPointName;
  vulkanUseEntryPointName.value.intValue0 = 1;

  slang::CompilerOptionEntry matrixLayoutColumn = {};
  matrixLayoutColumn.name = slang::CompilerOptionName::MatrixLayoutColumn;
  matrixLayoutColumn.value.intValue0 = 1;

  std::array<slang::CompilerOptionEntry, 4> slangCompilerOptions = {
      emitSpirVDirectly,
      debugInformation,
      vulkanUseEntryPointName,
      matrixLayoutColumn,
  };

  sessionDesc.compilerOptionEntries = slangCompilerOptions.data();
  sessionDesc.compilerOptionEntryCount = slangCompilerOptions.size();

  globalSlangSession->createSession(sessionDesc, slangSession.writeRef());
}

auto Gpu::initDescriptors() -> void {
  VkShaderStageFlags shaderStageFlags = {};
  shaderStageFlags |= VK_SHADER_STAGE_VERTEX_BIT;
  shaderStageFlags |= VK_SHADER_STAGE_TESSELLATION_CONTROL_BIT;
  shaderStageFlags |= VK_SHADER_STAGE_TESSELLATION_EVALUATION_BIT;
  shaderStageFlags |= VK_SHADER_STAGE_FRAGMENT_BIT;
  shaderStageFlags |= VK_SHADER_STAGE_COMPUTE_BIT;

  VkDescriptorSetLayoutBinding texturesBinding = {};
  texturesBinding.binding = kDescriptorBindingTextures;
  texturesBinding.descriptorType = VK_DESCRIPTOR_TYPE_SAMPLED_IMAGE;
  texturesBinding.descriptorCount = kMaxBindlessResources;
  texturesBinding.stageFlags = shaderStageFlags;
  texturesBinding.pImmutableSamplers = nullptr;

  VkDescriptorSetLayoutBinding samplersBinding = {};
  samplersBinding.binding = kDescriptorBindingSamplers;
  samplersBinding.descriptorType = VK_DESCRIPTOR_TYPE_SAMPLER;
  samplersBinding.descriptorCount = kMaxBindlessResources;
  samplersBinding.stageFlags = shaderStageFlags;
  samplersBinding.pImmutableSamplers = nullptr;

  VkDescriptorSetLayoutBinding storageImagesBinding = {};
  storageImagesBinding.binding = kDescriptorBindingStorageImages;
  storageImagesBinding.descriptorType = VK_DESCRIPTOR_TYPE_STORAGE_IMAGE;
  storageImagesBinding.descriptorCount = kMaxBindlessResources;
  storageImagesBinding.stageFlags = shaderStageFlags;
  storageImagesBinding.pImmutableSamplers = nullptr;

  VkDescriptorBindingFlagsEXT descriptorBindingFlagsEXT = {};
  descriptorBindingFlagsEXT |= VK_DESCRIPTOR_BINDING_UPDATE_AFTER_BIND_BIT;
  descriptorBindingFlagsEXT |= VK_DESCRIPTOR_BINDING_UPDATE_UNUSED_WHILE_PENDING_BIT;
  descriptorBindingFlagsEXT |= VK_DESCRIPTOR_BINDING_PARTIALLY_BOUND_BIT;

  std::array<VkDescriptorSetLayoutBinding, kDescriptorBindingCount> descriptorSetLayoutBindings;
  descriptorSetLayoutBindings[kDescriptorBindingTextures] = texturesBinding;
  descriptorSetLayoutBindings[kDescriptorBindingSamplers] = samplersBinding;
  descriptorSetLayoutBindings[kDescriptorBindingStorageImages] = storageImagesBinding;

  std::array<VkDescriptorBindingFlags, kDescriptorBindingCount> descriptorBindingFlags;
  descriptorBindingFlags[kDescriptorBindingTextures] = descriptorBindingFlagsEXT;
  descriptorBindingFlags[kDescriptorBindingSamplers] = descriptorBindingFlagsEXT;
  descriptorBindingFlags[kDescriptorBindingStorageImages] = descriptorBindingFlagsEXT;

  VkDescriptorSetLayoutBindingFlagsCreateInfo descriptorSetLayoutBindingFlagsCreateInfo = {};
  descriptorSetLayoutBindingFlagsCreateInfo.sType = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_BINDING_FLAGS_CREATE_INFO_EXT;
  descriptorSetLayoutBindingFlagsCreateInfo.bindingCount = kDescriptorBindingCount;
  descriptorSetLayoutBindingFlagsCreateInfo.pBindingFlags = descriptorBindingFlags.data();

  VkDescriptorSetLayoutCreateInfo descriptorSetLayoutCreateInfo = {};
  descriptorSetLayoutCreateInfo.sType = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO;
  descriptorSetLayoutCreateInfo.pNext = &descriptorSetLayoutBindingFlagsCreateInfo;
  descriptorSetLayoutCreateInfo.flags = VK_DESCRIPTOR_SET_LAYOUT_CREATE_UPDATE_AFTER_BIND_POOL_BIT_EXT;
  descriptorSetLayoutCreateInfo.bindingCount = kDescriptorBindingCount;
  descriptorSetLayoutCreateInfo.pBindings = descriptorSetLayoutBindings.data();
  VK_CHECK(vkCreateDescriptorSetLayout(device, &descriptorSetLayoutCreateInfo, allocationCallbacks, &descriptorSetLayout));

  std::array<VkDescriptorPoolSize, kDescriptorBindingCount> descriptorPoolSizes;
  VkDescriptorPoolSize descriptorPoolSize = {};
  descriptorPoolSize.descriptorCount = kMaxBindlessResources;
  descriptorPoolSize.type = VK_DESCRIPTOR_TYPE_SAMPLED_IMAGE;
  descriptorPoolSizes[kDescriptorBindingTextures] = descriptorPoolSize;
  descriptorPoolSize.type = VK_DESCRIPTOR_TYPE_SAMPLER;
  descriptorPoolSizes[kDescriptorBindingSamplers] = descriptorPoolSize;
  descriptorPoolSize.type = VK_DESCRIPTOR_TYPE_STORAGE_IMAGE;
  descriptorPoolSizes[kDescriptorBindingStorageImages] = descriptorPoolSize;

  VkDescriptorPoolCreateInfo descriptorPoolCreateInfo = {};
  descriptorPoolCreateInfo.sType = VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO;
  descriptorPoolCreateInfo.flags = VK_DESCRIPTOR_POOL_CREATE_UPDATE_AFTER_BIND_BIT;
  descriptorPoolCreateInfo.maxSets = 1;
  descriptorPoolCreateInfo.poolSizeCount = kDescriptorBindingCount;
  descriptorPoolCreateInfo.pPoolSizes = descriptorPoolSizes.data();
  VK_CHECK(vkCreateDescriptorPool(device, &descriptorPoolCreateInfo, allocationCallbacks, &descriptorPool));

  VkDescriptorSetAllocateInfo descriptorSetAllocateInfo = {};
  descriptorSetAllocateInfo.sType = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO;
  descriptorSetAllocateInfo.descriptorPool = descriptorPool;
  descriptorSetAllocateInfo.descriptorSetCount = 1;
  descriptorSetAllocateInfo.pSetLayouts = &descriptorSetLayout;
  VK_CHECK(vkAllocateDescriptorSets(device, &descriptorSetAllocateInfo, &descriptorSet));

  Sampler::Desc defaultSamplerDesc = {};
  defaultSamplerDesc.addressMode = Sampler::AddressMode::Repeat;
#ifndef NDEBUG
  defaultSamplerDesc.debugName = "Default Sampler";
#endif
  defaultSampler = create(defaultSamplerDesc);

  Texture::Desc defaultTextureDesc = {};
  defaultTextureDesc.usage = Texture::Usage::Color2D;
  defaultTextureDesc.width = 4;
  defaultTextureDesc.height = 4;
#ifndef NDEBUG
  defaultTextureDesc.debugName = "Default Texture";
#endif
  defaultTexture = create(defaultTextureDesc);

  syncDescriptors();
}

auto Gpu::syncDescriptors() -> void {
  std::vector<VkWriteDescriptorSet> writeDescriptorSets = {};

  std::vector<VkDescriptorImageInfo> textureInfos;
  std::vector<VkDescriptorImageInfo> samplerInfos;

  VkWriteDescriptorSet writeDescriptorSet = {};
  writeDescriptorSet.sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET;
  writeDescriptorSet.dstSet = descriptorSet;
  writeDescriptorSet.dstArrayElement = 0;

  LOG_ERROR("SYNC");

  if (descriptorSync.has(DescriptorSync::SampledImage)) {
    Texture *texture = textures.get(defaultTexture);

    VkDescriptorImageInfo descriptorImageInfo = {};
    descriptorImageInfo.imageLayout = VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL;
    descriptorImageInfo.imageView = texture->imageView;

    textureInfos.resize(textures.getSize(), descriptorImageInfo);
    auto textureIdx = 0;

    for (auto &item : textures) {
      descriptorImageInfo.imageView = item.imageView;
      textureInfos[textureIdx++] = descriptorImageInfo;
    }

    writeDescriptorSet.dstBinding = kDescriptorBindingTextures;
    writeDescriptorSet.descriptorCount = textureInfos.size();
    writeDescriptorSet.descriptorType = VK_DESCRIPTOR_TYPE_SAMPLED_IMAGE;
    writeDescriptorSet.pImageInfo = textureInfos.data();
    writeDescriptorSets.emplace_back(writeDescriptorSet);
  }

  if (descriptorSync.has(DescriptorSync::Sampler)) {
    Sampler *sampler = samplers.get(defaultSampler);
    VkDescriptorImageInfo descriptorImageInfo = {};
    descriptorImageInfo.sampler = sampler->sampler;

    samplerInfos.resize(samplers.getSize(), descriptorImageInfo);
    auto samplerIdx = 0;

    for (auto &item : samplers) {
      descriptorImageInfo.sampler = item.sampler;
      samplerInfos[samplerIdx++] = descriptorImageInfo;
    }

    writeDescriptorSet.dstBinding = kDescriptorBindingSamplers;
    writeDescriptorSet.descriptorCount = samplerInfos.size();
    writeDescriptorSet.descriptorType = VK_DESCRIPTOR_TYPE_SAMPLER;
    writeDescriptorSet.pImageInfo = samplerInfos.data();
    writeDescriptorSets.emplace_back(writeDescriptorSet);
  }

  if (!writeDescriptorSets.empty()) {
    vkUpdateDescriptorSets(device, writeDescriptorSets.size(), writeDescriptorSets.data(), 0, nullptr);
  }

  descriptorSync = DescriptorSync::None;
}

auto Gpu::defer(std::packaged_task<void()> &&task) -> void {
  VkFence fence = frameFences[frameNumber % frameFences.size()];
  assert(fence != VK_NULL_HANDLE);
  tasks.emplace_back(std::move(task), fence);
}

auto Gpu::processReadyTasks() -> void {
  auto task = tasks.begin();
  while (task != tasks.end() && vkWaitForFences(device, 1, &task->fence, VK_TRUE, 0) == VK_SUCCESS) {
    (task++)->task();
  }
  tasks.erase(tasks.begin(), task);
}

auto Gpu::processAllTasks() -> void {
  for (auto &task : tasks) {
    while (vkWaitForFences(device, 1, &task.fence, VK_TRUE, UINT64_MAX) == VK_TIMEOUT) {
      ;
    }
    task.task();
  }
  tasks.clear();
}

auto Gpu::logSlangDiagnostics(slang::IBlob *diagnosticsBlob) -> void {
  if (diagnosticsBlob != nullptr) {
    LOG_WARNING((const char *)diagnosticsBlob->getBufferPointer());
  }
}

auto Gpu::create(Buffer::Desc &description) -> Handle<Buffer> {
  LOG_DEBUG("Buffer");
  Buffer buffer = {};

  switch (description.usage) {
  case Buffer::Usage::Index:
    buffer.usageFlags |= VK_BUFFER_USAGE_INDEX_BUFFER_BIT;
    break;
  case Buffer::Usage::Vertex:
    buffer.usageFlags |= VK_BUFFER_USAGE_VERTEX_BUFFER_BIT;
    buffer.usageFlags |= VK_BUFFER_USAGE_SHADER_DEVICE_ADDRESS_BIT;
    break;
  case Buffer::Usage::Indirect:
    buffer.usageFlags |= VK_BUFFER_USAGE_INDIRECT_BUFFER_BIT;
    break;
  case Buffer::Usage::Storage:
    buffer.usageFlags |= VK_BUFFER_USAGE_STORAGE_BUFFER_BIT;
    buffer.usageFlags |= VK_BUFFER_USAGE_SHADER_DEVICE_ADDRESS_BIT;
    break;
  }

#ifndef NDEBUG
  buffer.debugName = description.debugName;
#endif

  return create(buffer, description.size);
}

auto Gpu::create(Buffer &buffer, size_t size) -> Handle<Buffer> {
  LOG_DEBUG("Buffer");

  VkBufferCreateInfo bufferCreateInfo = {};
  bufferCreateInfo.sType = VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO;
  bufferCreateInfo.flags = 0;
  bufferCreateInfo.size = std::max<VkDeviceSize>(size, 1024);
  bufferCreateInfo.usage = buffer.usageFlags;
  bufferCreateInfo.sharingMode = VK_SHARING_MODE_EXCLUSIVE;
  bufferCreateInfo.queueFamilyIndexCount = 0;
  bufferCreateInfo.pQueueFamilyIndices = nullptr;

  VmaAllocationCreateInfo allocationCreateInfo = {};
  allocationCreateInfo.usage = VMA_MEMORY_USAGE_AUTO;
  allocationCreateInfo.flags |= VMA_ALLOCATION_CREATE_HOST_ACCESS_SEQUENTIAL_WRITE_BIT;
  allocationCreateInfo.flags |= VMA_ALLOCATION_CREATE_HOST_ACCESS_ALLOW_TRANSFER_INSTEAD_BIT;
  allocationCreateInfo.flags |= VMA_ALLOCATION_CREATE_MAPPED_BIT;

  VK_CHECK(vmaCreateBuffer(
      allocator,
      &bufferCreateInfo,
      &allocationCreateInfo,
      &buffer.buffer,
      &buffer.allocation,
      &buffer.allocationInfo));

  if ((buffer.usageFlags & VK_BUFFER_USAGE_SHADER_DEVICE_ADDRESS_BIT) != 0U) {
    VkBufferDeviceAddressInfo bufferDeviceAddressInfo = {};
    bufferDeviceAddressInfo.sType = VK_STRUCTURE_TYPE_BUFFER_DEVICE_ADDRESS_INFO;
    bufferDeviceAddressInfo.buffer = buffer.buffer;
    buffer.address = vkGetBufferDeviceAddress(device, &bufferDeviceAddressInfo);
  }

  vmaGetAllocationMemoryProperties(allocator, buffer.allocation, &buffer.memoryFlags);

#ifndef NDEBUG
  VkDebugUtilsObjectNameInfoEXT debugUtilsObjectNameInfoEXT = {};
  debugUtilsObjectNameInfoEXT.sType = VK_STRUCTURE_TYPE_DEBUG_UTILS_OBJECT_NAME_INFO_EXT;
  debugUtilsObjectNameInfoEXT.pObjectName = buffer.debugName;
  debugUtilsObjectNameInfoEXT.objectType = VK_OBJECT_TYPE_BUFFER;
  debugUtilsObjectNameInfoEXT.objectHandle = (uint64_t)buffer.buffer;
  VK_CHECK(vkSetDebugUtilsObjectNameEXT(device, &debugUtilsObjectNameInfoEXT));
#endif

  return buffers.allocate(nullptr, buffer);
}

auto Gpu::write(Handle<Buffer> handle, VkCommandBuffer commandBuffer, const Buffer::Write &writeInfo) -> void {
  Buffer &buffer = *buffers.get(handle);

  size_t totalSize = 0;
  for (uint32_t i = 0; i < writeInfo.writesSize; i++) {
    totalSize += writeInfo.writesSizes[i];
  }

  if (totalSize > buffer.allocationInfo.size) {
    destroy(buffer);
    create(buffer, totalSize);
  }

  if ((buffer.memoryFlags & VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT) != 0U) {
    auto *destinationPtr = static_cast<uint8_t *>(buffer.allocationInfo.pMappedData);
    for (uint32_t i = 0; i < writeInfo.writesSize; i++) {
      memcpy(destinationPtr, writeInfo.writesData[i], writeInfo.writesSizes[i]);
      destinationPtr += writeInfo.writesSizes[i];
    }

    VK_CHECK(vmaFlushAllocation(allocator, buffer.allocation, 0, VK_WHOLE_SIZE));

    VkBufferMemoryBarrier bufferMemoryBarrier = {};
    bufferMemoryBarrier.sType = VK_STRUCTURE_TYPE_BUFFER_MEMORY_BARRIER;
    bufferMemoryBarrier.srcAccessMask = VK_ACCESS_HOST_WRITE_BIT;
    bufferMemoryBarrier.dstAccessMask = VK_ACCESS_TRANSFER_READ_BIT | VK_ACCESS_VERTEX_ATTRIBUTE_READ_BIT |
                                        VK_ACCESS_INDEX_READ_BIT | VK_ACCESS_INDIRECT_COMMAND_READ_BIT |
                                        VK_ACCESS_SHADER_READ_BIT;
    bufferMemoryBarrier.srcQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED;
    bufferMemoryBarrier.dstQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED;
    bufferMemoryBarrier.buffer = buffer.buffer;
    bufferMemoryBarrier.offset = 0;
    bufferMemoryBarrier.size = VK_WHOLE_SIZE;

    vkCmdPipelineBarrier(
        commandBuffer,
        VK_PIPELINE_STAGE_HOST_BIT,
        VK_PIPELINE_STAGE_TRANSFER_BIT | VK_PIPELINE_STAGE_VERTEX_INPUT_BIT |
            VK_PIPELINE_STAGE_DRAW_INDIRECT_BIT | VK_PIPELINE_STAGE_VERTEX_SHADER_BIT |
            VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT,
        0,
        0,
        nullptr,
        1,
        &bufferMemoryBarrier,
        0,
        nullptr);

  } else {
    LOG_ERROR("USING STAGING BUFFER");
    VkBufferCreateInfo stagingBufferCreateInfo = {};
    stagingBufferCreateInfo.sType = VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO;
    stagingBufferCreateInfo.usage = VK_BUFFER_USAGE_TRANSFER_SRC_BIT;
    stagingBufferCreateInfo.size = buffer.allocationInfo.size;

    VmaAllocationCreateInfo stagingAllocationCreateInfo = {};
    stagingAllocationCreateInfo.usage = VMA_MEMORY_USAGE_AUTO;
    stagingAllocationCreateInfo.flags |= VMA_ALLOCATION_CREATE_HOST_ACCESS_SEQUENTIAL_WRITE_BIT;
    stagingAllocationCreateInfo.flags |= VMA_ALLOCATION_CREATE_MAPPED_BIT;

    VkBuffer stagingBuffer;
    VmaAllocation stagingAllocation;
    VmaAllocationInfo stagingAllocationInfo;

    VK_CHECK(vmaCreateBuffer(
        allocator,
        &stagingBufferCreateInfo,
        &stagingAllocationCreateInfo,
        &stagingBuffer,
        &stagingAllocation,
        &stagingAllocationInfo));

    auto *destinationPtr = static_cast<uint8_t *>(stagingAllocationInfo.pMappedData);
    for (uint32_t i = 0; i < writeInfo.writesSize; i++) {
      memcpy(destinationPtr, writeInfo.writesData[i], writeInfo.writesSizes[i]);
      destinationPtr += writeInfo.writesSizes[i];
    }

    VK_CHECK(vmaFlushAllocation(allocator, stagingAllocation, 0, VK_WHOLE_SIZE));

    VkBufferMemoryBarrier bufferMemoryBarrier = {};
    bufferMemoryBarrier.sType = VK_STRUCTURE_TYPE_BUFFER_MEMORY_BARRIER;
    bufferMemoryBarrier.srcAccessMask = VK_ACCESS_HOST_WRITE_BIT;
    bufferMemoryBarrier.dstAccessMask = VK_ACCESS_TRANSFER_READ_BIT;
    bufferMemoryBarrier.srcQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED;
    bufferMemoryBarrier.dstQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED;
    bufferMemoryBarrier.buffer = stagingBuffer;
    bufferMemoryBarrier.offset = 0;
    bufferMemoryBarrier.size = VK_WHOLE_SIZE;

    vkCmdPipelineBarrier(
        commandBuffer,
        VK_PIPELINE_STAGE_HOST_BIT,
        VK_PIPELINE_STAGE_TRANSFER_BIT,
        0,
        0,
        nullptr,
        1,
        &bufferMemoryBarrier,
        0,
        nullptr);

    VkBufferCopy bufferCopy = {};
    bufferCopy.srcOffset = 0;
    bufferCopy.dstOffset = 0;
    bufferCopy.size = totalSize;

    vkCmdCopyBuffer(commandBuffer, stagingBuffer, buffer.buffer, 1, &bufferCopy);

    VkBufferMemoryBarrier bufferMemoryBarrier2 = {};
    bufferMemoryBarrier2.sType = VK_STRUCTURE_TYPE_BUFFER_MEMORY_BARRIER;
    bufferMemoryBarrier2.srcAccessMask = VK_ACCESS_TRANSFER_WRITE_BIT;
    bufferMemoryBarrier2.dstAccessMask = VK_ACCESS_UNIFORM_READ_BIT;
    bufferMemoryBarrier2.srcQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED;
    bufferMemoryBarrier2.dstQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED;
    bufferMemoryBarrier2.buffer = buffer.buffer;
    bufferMemoryBarrier2.offset = 0;
    bufferMemoryBarrier2.size = VK_WHOLE_SIZE;

    vkCmdPipelineBarrier(
        commandBuffer,
        VK_PIPELINE_STAGE_TRANSFER_BIT,
        VK_PIPELINE_STAGE_VERTEX_SHADER_BIT,
        0,
        0,
        nullptr,
        1,
        &bufferMemoryBarrier2,
        0,
        nullptr);

    // TODO: destroy staging buffer
  }
}

auto Gpu::destroy(Handle<Buffer> buffer) -> void {
  buffers.free(buffer);
}

auto Gpu::destroy(Buffer &buffer) -> void {
  defer(std::packaged_task<void()>([&, vkBuffer = buffer.buffer, vkAllocation = buffer.allocation]() -> void {
    vmaDestroyBuffer(allocator, vkBuffer, vkAllocation);
  }));
}

auto Gpu::create(Pipeline::Desc &description) -> Handle<Pipeline> {
  LOG_DEBUG("Pipeline");
  Pipeline pipeline = {};

  Slang::ComPtr<slang::IModule> slangModule;
  {
    Slang::ComPtr<slang::IBlob> diagnosticsBlob;
    slangModule = slangSession->loadModule(description.shader.c_str(), diagnosticsBlob.writeRef());
    logSlangDiagnostics(diagnosticsBlob);
    if (slangModule == nullptr) {
      throw "todo";
    }
  }

  Slang::ComPtr<slang::IComponentType> linkedProgram;
  {
    Slang::ComPtr<slang::IBlob> diagnosticsBlob;
    SlangResult result = slangModule->link(linkedProgram.writeRef(), diagnosticsBlob.writeRef());
    logSlangDiagnostics(diagnosticsBlob);
    if (SLANG_FAILED(result)) {
      throw "todo";
    }
  }

  Slang::ComPtr<slang::IBlob> spirvCode;
  {
    Slang::ComPtr<slang::IBlob> diagnosticsBlob;
    SlangResult result = linkedProgram->getTargetCode(0, spirvCode.writeRef(), diagnosticsBlob.writeRef());
    logSlangDiagnostics(diagnosticsBlob);
    if (SLANG_FAILED(result)) {
      throw "todo";
    }
  }

  VkShaderModuleCreateInfo shaderModuleCreateInfo = {};
  shaderModuleCreateInfo.sType = VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO;
  shaderModuleCreateInfo.codeSize = spirvCode->getBufferSize();
  shaderModuleCreateInfo.pCode = static_cast<const uint32_t *>(spirvCode->getBufferPointer());

  VkShaderModule shaderModule = VK_NULL_HANDLE;
  VK_CHECK(vkCreateShaderModule(device, &shaderModuleCreateInfo, allocationCallbacks, &shaderModule));

  SpvReflectShaderModule reflectModule = {};
  SpvReflectResult result = spvReflectCreateShaderModule(shaderModuleCreateInfo.codeSize, shaderModuleCreateInfo.pCode, &reflectModule);
  assert(result == SPV_REFLECT_RESULT_SUCCESS);

  assert(reflectModule.entry_point_count == 2);

  std::vector<VkPushConstantRange> pushConstantRanges = {};
  std::vector<VkPipelineShaderStageCreateInfo> shaderStageCreateInfos(reflectModule.entry_point_count);

  VkPipelineVertexInputStateCreateInfo vertexInputStateCreateInfo = {};
  vertexInputStateCreateInfo.sType = VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO;

  VkVertexInputBindingDescription vertexInputBindingDescription = {};

  for (uint32_t stageIdx = 0; stageIdx < reflectModule.entry_point_count; ++stageIdx) {
    SpvReflectEntryPoint entryPoint = reflectModule.entry_points[stageIdx];

    VkPipelineShaderStageCreateInfo pipelineShaderStageCreateInfo = {};
    pipelineShaderStageCreateInfo.sType = VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO;
    pipelineShaderStageCreateInfo.stage = (VkShaderStageFlagBits)entryPoint.shader_stage;
    pipelineShaderStageCreateInfo.module = shaderModule;
    pipelineShaderStageCreateInfo.pName = entryPoint.name;

    shaderStageCreateInfos[stageIdx] = pipelineShaderStageCreateInfo;

    if (entryPoint.shader_stage == SPV_REFLECT_SHADER_STAGE_VERTEX_BIT) {
      uint32_t inputVariablesCount = 0;
      {
        auto reflectResult = spvReflectEnumerateEntryPointInputVariables(&reflectModule, entryPoint.name, &inputVariablesCount, nullptr);
        assert(result == SPV_REFLECT_RESULT_SUCCESS);
      }

      if (inputVariablesCount > 0) {
        std::vector<SpvReflectInterfaceVariable *> inputVariables(inputVariablesCount);

        {
          auto reflectResult = spvReflectEnumerateEntryPointInputVariables(&reflectModule, entryPoint.name, &inputVariablesCount, inputVariables.data());
          assert(result == SPV_REFLECT_RESULT_SUCCESS);
        }

        vertexInputBindingDescription.binding = 0;
        vertexInputBindingDescription.stride = 0;
        vertexInputBindingDescription.inputRate = VK_VERTEX_INPUT_RATE_VERTEX;

        std::vector<VkVertexInputAttributeDescription> vertexInputAttributeDescriptions;

        for (uint32_t inputVariableIdx = 0; inputVariableIdx < inputVariablesCount; ++inputVariableIdx) {
          const SpvReflectInterfaceVariable reflectVar = *inputVariables[inputVariableIdx];

          if ((reflectVar.decoration_flags & SPV_REFLECT_DECORATION_BUILT_IN) != 0U) {
            continue;
          }

          VkVertexInputAttributeDescription vertexInputAttributeDescription = {};
          vertexInputAttributeDescription.location = reflectVar.location;
          vertexInputAttributeDescription.binding = vertexInputBindingDescription.binding;
          vertexInputAttributeDescription.format = (VkFormat)reflectVar.format;
          vertexInputAttributeDescription.offset = 0;
          vertexInputAttributeDescriptions.emplace_back(vertexInputAttributeDescription);
        }

        std::ranges::sort(
            vertexInputAttributeDescriptions,
            [](const VkVertexInputAttributeDescription &a, const VkVertexInputAttributeDescription &b) -> bool {
              return a.location < b.location;
            });

        for (auto &vertexInputAttributeDescription : vertexInputAttributeDescriptions) {
          uint32_t formatSize = vkuFormatTexelBlockSize(vertexInputAttributeDescription.format);
          vertexInputAttributeDescription.offset = vertexInputBindingDescription.stride;
          vertexInputBindingDescription.stride += formatSize;
        }

        vertexInputStateCreateInfo.vertexBindingDescriptionCount = 1;
        vertexInputStateCreateInfo.pVertexBindingDescriptions = &vertexInputBindingDescription;
        vertexInputStateCreateInfo.vertexAttributeDescriptionCount = vertexInputAttributeDescriptions.size();
        vertexInputStateCreateInfo.pVertexAttributeDescriptions = vertexInputAttributeDescriptions.data();
      }
    } // Vertex

    // uint32_t descriptorSetsCount = 0;

    // {
    //   auto reflectResult = spvReflectEnumerateEntryPointDescriptorSets(&reflectModule, entryPoint.name, &descriptorSetsCount, nullptr);
    //   assert(result == SPV_REFLECT_RESULT_SUCCESS);
    // }

    // descriptorSetsCount = 0; // TODO

    // if (descriptorSetsCount > 0) {
    //   SpvReflectDescriptorSet** descriptorSets = malloc(descriptorSetsCount * sizeof(SpvReflectDescriptorSet*));

    //   {
    //     auto reflectResult = spvReflectEnumerateEntryPointDescriptorSets(&reflectModule, entryPoint.name, &descriptorSetsCount, descriptorSets);
    //     assert(result == SPV_REFLECT_RESULT_SUCCESS);
    //   }

    //   for (uint32_t descriptorSetIndex = 0; descriptorSetIndex < descriptorSetsCount; ++descriptorSetIndex) {
    //     const SpvReflectDescriptorSet reflectSet = *descriptorSets[descriptorSetIndex];
    //     VkDescriptorSetLayoutBinding* descriptorSetLayoutBindings = malloc(reflectSet.binding_count * sizeof(VkDescriptorSetLayoutBinding));

    //     for (uint32_t bindingIdx = 0; bindingIdx < reflectSet.binding_count; ++bindingIdx) {
    //       const SpvReflectDescriptorBinding reflectBinding = *(reflectSet.bindings[bindingIdx]);
    //       VkDescriptorSetLayoutBinding descriptorSetLayoutBinding = descriptorSetLayoutBindings[bindingIdx];
    //       descriptorSetLayoutBinding.binding = reflectBinding.binding;
    //       descriptorSetLayoutBinding.descriptorType = (VkDescriptorType)reflectBinding.descriptor_type;
    //       descriptorSetLayoutBinding.descriptorCount = 1;
    //       for (uint32_t i_dim = 0; i_dim < reflectBinding.array.dims_count; ++i_dim) {
    //         descriptorSetLayoutBinding.descriptorCount *= reflectBinding.array.dims[i_dim];
    //       }
    //       descriptorSetLayoutBinding.stageFlags = pipelineShaderStageCreateInfo.stage;
    //     }

    //     VkDescriptorSetLayoutCreateInfo descriptorSetLayoutCreateInfo = {
    //         .sType = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
    //         .bindingCount = reflectSet.binding_count,
    //         .pBindings = descriptorSetLayoutBindings,
    //     };

    //     VkDescriptorSetLayout* descriptorSetLayout = DescriptorSetLayouts_push(&descriptorSetLayouts, (VkDescriptorSetLayout){});
    //     VK_CHECK(vkCreateDescriptorSetLayout(inVulkan->device, &descriptorSetLayoutCreateInfo, nullptr, descriptorSetLayout));

    //     free(descriptorSetLayoutBindings);
    //   }

    //   free(descriptorSets);
    // }

    uint32_t pushConstantBlocksCount = 0;

    {
      auto reflectResult = spvReflectEnumerateEntryPointPushConstantBlocks(&reflectModule, entryPoint.name, &pushConstantBlocksCount, nullptr);
      assert(result == SPV_REFLECT_RESULT_SUCCESS);
    }

    if (pushConstantBlocksCount > 0) {
      std::vector<SpvReflectBlockVariable *> pushConstantBlocks(pushConstantBlocksCount);

      {
        auto reflectResult = spvReflectEnumerateEntryPointPushConstantBlocks(&reflectModule, entryPoint.name, &pushConstantBlocksCount, pushConstantBlocks.data());
        assert(result == SPV_REFLECT_RESULT_SUCCESS);
      }

      VkPushConstantRange pushConstantRange = {};
      pushConstantRange.stageFlags = pipelineShaderStageCreateInfo.stage;
      pushConstantRange.offset = pushConstantBlocks[0]->offset;
      pushConstantRange.size = pushConstantBlocks[0]->size;
      pushConstantRanges.emplace_back(pushConstantRange);
    }
  }

  VkPipelineInputAssemblyStateCreateInfo inputAssemblyStateCreateInfo = {};
  inputAssemblyStateCreateInfo.sType = VK_STRUCTURE_TYPE_PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO;
  inputAssemblyStateCreateInfo.topology = VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST;

  VkPipelineTessellationStateCreateInfo tessellationStateCreateInfo = {};
  tessellationStateCreateInfo.sType = VK_STRUCTURE_TYPE_PIPELINE_TESSELLATION_STATE_CREATE_INFO;

  VkPipelineViewportStateCreateInfo viewportStateCreateInfo = {};
  viewportStateCreateInfo.sType = VK_STRUCTURE_TYPE_PIPELINE_VIEWPORT_STATE_CREATE_INFO;
  viewportStateCreateInfo.viewportCount = 1;
  viewportStateCreateInfo.scissorCount = 1;

  VkPipelineRasterizationStateCreateInfo rasterizationStateCreateInfo = {};
  rasterizationStateCreateInfo.sType = VK_STRUCTURE_TYPE_PIPELINE_RASTERIZATION_STATE_CREATE_INFO;
  rasterizationStateCreateInfo.depthClampEnable = VK_FALSE;
  rasterizationStateCreateInfo.rasterizerDiscardEnable = VK_FALSE;
  rasterizationStateCreateInfo.polygonMode = VK_POLYGON_MODE_LINE;
  rasterizationStateCreateInfo.cullMode = VK_CULL_MODE_NONE;
  rasterizationStateCreateInfo.frontFace = description.windingOrder == Pipeline::WindingOrder::ClockWise ? VK_FRONT_FACE_CLOCKWISE : VK_FRONT_FACE_COUNTER_CLOCKWISE;
  rasterizationStateCreateInfo.depthBiasEnable = VK_FALSE;
  rasterizationStateCreateInfo.depthBiasSlopeFactor = 1.0F;
  rasterizationStateCreateInfo.lineWidth = 1.0F;

  VkPipelineMultisampleStateCreateInfo multisampleStateCreateInfo = {};
  multisampleStateCreateInfo.sType = VK_STRUCTURE_TYPE_PIPELINE_MULTISAMPLE_STATE_CREATE_INFO;
  multisampleStateCreateInfo.rasterizationSamples = VK_SAMPLE_COUNT_1_BIT;
  multisampleStateCreateInfo.sampleShadingEnable = VK_FALSE;

  VkPipelineDepthStencilStateCreateInfo depthStencilStateCreateInfo = {};
  depthStencilStateCreateInfo.sType = VK_STRUCTURE_TYPE_PIPELINE_DEPTH_STENCIL_STATE_CREATE_INFO;
  depthStencilStateCreateInfo.depthTestEnable = VK_FALSE;
  depthStencilStateCreateInfo.depthWriteEnable = VK_FALSE;
  depthStencilStateCreateInfo.stencilTestEnable = VK_FALSE;

  VkPipelineColorBlendAttachmentState colorBlendAttachmentState = {};
  colorBlendAttachmentState.blendEnable = VK_TRUE;
  colorBlendAttachmentState.srcColorBlendFactor = VK_BLEND_FACTOR_SRC_ALPHA;
  colorBlendAttachmentState.dstColorBlendFactor = VK_BLEND_FACTOR_ONE_MINUS_SRC_ALPHA;
  colorBlendAttachmentState.colorBlendOp = VK_BLEND_OP_ADD;
  colorBlendAttachmentState.srcAlphaBlendFactor = VK_BLEND_FACTOR_ONE;
  colorBlendAttachmentState.dstAlphaBlendFactor = VK_BLEND_FACTOR_ONE_MINUS_SRC_ALPHA;
  colorBlendAttachmentState.alphaBlendOp = VK_BLEND_OP_ADD;
  colorBlendAttachmentState.colorWriteMask |= VK_COLOR_COMPONENT_R_BIT;
  colorBlendAttachmentState.colorWriteMask |= VK_COLOR_COMPONENT_G_BIT;
  colorBlendAttachmentState.colorWriteMask |= VK_COLOR_COMPONENT_B_BIT;
  colorBlendAttachmentState.colorWriteMask |= VK_COLOR_COMPONENT_A_BIT;

  VkPipelineColorBlendStateCreateInfo colorBlendStateCreateInfo = {};
  colorBlendStateCreateInfo.sType = VK_STRUCTURE_TYPE_PIPELINE_COLOR_BLEND_STATE_CREATE_INFO;
  colorBlendStateCreateInfo.logicOpEnable = VK_FALSE;
  colorBlendStateCreateInfo.logicOp = VK_LOGIC_OP_COPY;
  colorBlendStateCreateInfo.attachmentCount = 1;
  colorBlendStateCreateInfo.pAttachments = &colorBlendAttachmentState;

  std::array<VkDynamicState, 2> dynamicStates = {
      VK_DYNAMIC_STATE_VIEWPORT,
      VK_DYNAMIC_STATE_SCISSOR,
  };

  VkPipelineDynamicStateCreateInfo dynamicStateCreateInfo = {};
  dynamicStateCreateInfo.sType = VK_STRUCTURE_TYPE_PIPELINE_DYNAMIC_STATE_CREATE_INFO;
  dynamicStateCreateInfo.dynamicStateCount = dynamicStates.size();
  dynamicStateCreateInfo.pDynamicStates = dynamicStates.data();

  VkPipelineLayoutCreateInfo layoutCreateInfo = {};
  layoutCreateInfo.sType = VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO;
  layoutCreateInfo.pSetLayouts = &descriptorSetLayout;
  layoutCreateInfo.setLayoutCount = 1;
  layoutCreateInfo.pushConstantRangeCount = pushConstantRanges.size();
  layoutCreateInfo.pPushConstantRanges = pushConstantRanges.data();

  VK_CHECK(vkCreatePipelineLayout(device, &layoutCreateInfo, allocationCallbacks, &pipeline.layout));

  auto colorAttachmentFormat = VK_FORMAT_B8G8R8A8_SRGB;
  VkPipelineRenderingCreateInfo pipelineRenderingCreateInfo = {};
  pipelineRenderingCreateInfo.sType = VK_STRUCTURE_TYPE_PIPELINE_RENDERING_CREATE_INFO;
  pipelineRenderingCreateInfo.colorAttachmentCount = 1;
  pipelineRenderingCreateInfo.pColorAttachmentFormats = &colorAttachmentFormat;

  VkGraphicsPipelineCreateInfo graphicsPipelineCreateInfo = {};
  graphicsPipelineCreateInfo.sType = VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_CREATE_INFO;
  graphicsPipelineCreateInfo.pNext = &pipelineRenderingCreateInfo;
  graphicsPipelineCreateInfo.stageCount = reflectModule.entry_point_count;
  graphicsPipelineCreateInfo.pStages = shaderStageCreateInfos.data();
  graphicsPipelineCreateInfo.pVertexInputState = &vertexInputStateCreateInfo;
  graphicsPipelineCreateInfo.pInputAssemblyState = &inputAssemblyStateCreateInfo;
  graphicsPipelineCreateInfo.pTessellationState = &tessellationStateCreateInfo;
  graphicsPipelineCreateInfo.pViewportState = &viewportStateCreateInfo;
  graphicsPipelineCreateInfo.pRasterizationState = &rasterizationStateCreateInfo;
  graphicsPipelineCreateInfo.pMultisampleState = &multisampleStateCreateInfo;
  graphicsPipelineCreateInfo.pDepthStencilState = &depthStencilStateCreateInfo;
  graphicsPipelineCreateInfo.pColorBlendState = &colorBlendStateCreateInfo;
  graphicsPipelineCreateInfo.pDynamicState = &dynamicStateCreateInfo;
  graphicsPipelineCreateInfo.layout = pipeline.layout;

  VK_CHECK(vkCreateGraphicsPipelines(
      device,
      VK_NULL_HANDLE, // TODO
      1,
      &graphicsPipelineCreateInfo,
      allocationCallbacks,
      &pipeline.pipeline));

  spvReflectDestroyShaderModule(&reflectModule);
  vkDestroyShaderModule(device, shaderModule, allocationCallbacks);

#ifndef NDEBUG
  std::string pipelineName = std::format("{} (Pipeline)", description.debugName);
  std::string layoutName = std::format("{} (Layout)", description.debugName);
  VkDebugUtilsObjectNameInfoEXT debugUtilsObjectNameInfoEXT = {};
  debugUtilsObjectNameInfoEXT.sType = VK_STRUCTURE_TYPE_DEBUG_UTILS_OBJECT_NAME_INFO_EXT;
  debugUtilsObjectNameInfoEXT.pObjectName = pipelineName.c_str();
  debugUtilsObjectNameInfoEXT.objectType = VK_OBJECT_TYPE_PIPELINE;
  debugUtilsObjectNameInfoEXT.objectHandle = (uint64_t)pipeline.pipeline;
  VK_CHECK(vkSetDebugUtilsObjectNameEXT(device, &debugUtilsObjectNameInfoEXT));
  debugUtilsObjectNameInfoEXT.pObjectName = layoutName.c_str();
  debugUtilsObjectNameInfoEXT.objectType = VK_OBJECT_TYPE_PIPELINE_LAYOUT;
  debugUtilsObjectNameInfoEXT.objectHandle = (uint64_t)pipeline.layout;
  VK_CHECK(vkSetDebugUtilsObjectNameEXT(device, &debugUtilsObjectNameInfoEXT));
#endif

  return pipelines.allocate(nullptr, pipeline);
}

auto Gpu::destroy(Handle<Pipeline> pipeline) -> void {
  pipelines.free(pipeline);
}

auto Gpu::destroy(Pipeline &pipeline) -> void {
  defer(std::packaged_task<void()>([&, vkPipeline = pipeline.pipeline, vkPipelineLayout = pipeline.layout]() -> void {
    vkDestroyPipeline(device, vkPipeline, allocationCallbacks);
    vkDestroyPipelineLayout(device, vkPipelineLayout, allocationCallbacks);
  }));
}

auto Gpu::create(Sampler::Desc &description) -> Handle<Sampler> {
  LOG_DEBUG("Sampler");

  Sampler sampler = {};

  VkSamplerCreateInfo samplerCreateInfo = {};
  samplerCreateInfo.sType = VK_STRUCTURE_TYPE_SAMPLER_CREATE_INFO;
  samplerCreateInfo.pNext = nullptr;
  samplerCreateInfo.flags = 0;
  samplerCreateInfo.magFilter = VK_FILTER_LINEAR;
  samplerCreateInfo.minFilter = VK_FILTER_LINEAR;
  samplerCreateInfo.mipmapMode = VK_SAMPLER_MIPMAP_MODE_LINEAR;
  samplerCreateInfo.addressModeU = static_cast<VkSamplerAddressMode>(description.addressMode);
  samplerCreateInfo.addressModeV = static_cast<VkSamplerAddressMode>(description.addressMode);
  samplerCreateInfo.addressModeW = static_cast<VkSamplerAddressMode>(description.addressMode);
  samplerCreateInfo.mipLodBias = 0.0F;
  samplerCreateInfo.anisotropyEnable = VK_FALSE;
  samplerCreateInfo.maxAnisotropy = 0.0F;
  samplerCreateInfo.compareEnable = VK_FALSE;
  samplerCreateInfo.compareOp = VK_COMPARE_OP_ALWAYS;
  samplerCreateInfo.minLod = 0.0F;
  samplerCreateInfo.maxLod = 0.0F;
  samplerCreateInfo.borderColor = VK_BORDER_COLOR_INT_OPAQUE_BLACK;
  samplerCreateInfo.unnormalizedCoordinates = VK_FALSE;
  VK_CHECK(vkCreateSampler(device, &samplerCreateInfo, allocationCallbacks, &sampler.sampler));
#ifndef NDEBUG
  VkDebugUtilsObjectNameInfoEXT debugUtilsObjectNameInfoEXT = {};
  debugUtilsObjectNameInfoEXT.sType = VK_STRUCTURE_TYPE_DEBUG_UTILS_OBJECT_NAME_INFO_EXT;
  debugUtilsObjectNameInfoEXT.pObjectName = description.debugName;
  debugUtilsObjectNameInfoEXT.objectType = VK_OBJECT_TYPE_SAMPLER;
  debugUtilsObjectNameInfoEXT.objectHandle = (uint64_t)sampler.sampler;
  VK_CHECK(vkSetDebugUtilsObjectNameEXT(device, &debugUtilsObjectNameInfoEXT));
#endif

  return samplers.allocate(nullptr, sampler);
}

auto Gpu::destroy(Handle<Sampler> sampler) -> void {
  samplers.free(sampler);
}

auto Gpu::destroy(Sampler &sampler) -> void {
  defer(std::packaged_task<void()>([&, vkSampler = sampler.sampler]() -> void {
    vkDestroySampler(device, vkSampler, allocationCallbacks);
  }));
}

auto Gpu::create(Texture::Desc &description) -> Handle<Texture> {
  LOG_DEBUG("Texture");
  Texture texture = {};

  VkExtent3D extent = {};
  extent.width = description.width;
  extent.height = description.height;
  extent.depth = description.depth;

  texture.layout = VK_IMAGE_LAYOUT_UNDEFINED;
  texture.levelCount = 1;
  texture.layerCount = 1;
  texture.extent = extent;

  switch (description.usage) {
  case Texture::Usage::Color2D:
    texture.imageType = VK_IMAGE_TYPE_2D;
    texture.imageViewType = VK_IMAGE_VIEW_TYPE_2D;
    texture.format = VK_FORMAT_R8G8B8A8_SRGB;
    texture.aspectFlags = VK_IMAGE_ASPECT_COLOR_BIT;
    texture.usageFlags |= VK_IMAGE_USAGE_SAMPLED_BIT;
    texture.usageFlags |= VK_IMAGE_USAGE_TRANSFER_DST_BIT;
    break;
  case Texture::Usage::TextCurves:
    texture.imageType = VK_IMAGE_TYPE_2D;
    texture.imageViewType = VK_IMAGE_VIEW_TYPE_2D;
    texture.format = VK_FORMAT_R16G16B16A16_UINT;
    texture.aspectFlags = VK_IMAGE_ASPECT_COLOR_BIT;
    texture.usageFlags |= VK_IMAGE_USAGE_SAMPLED_BIT;
    texture.usageFlags |= VK_IMAGE_USAGE_TRANSFER_DST_BIT;
    break;
  case Texture::Usage::TextBands:
    texture.imageType = VK_IMAGE_TYPE_2D;
    texture.imageViewType = VK_IMAGE_VIEW_TYPE_2D;
    texture.format = VK_FORMAT_R16G16_UINT;
    texture.aspectFlags = VK_IMAGE_ASPECT_COLOR_BIT;
    texture.usageFlags |= VK_IMAGE_USAGE_SAMPLED_BIT;
    texture.usageFlags |= VK_IMAGE_USAGE_TRANSFER_DST_BIT;
    break;
  }

  VkImageCreateInfo imageCreateInfo = {};
  imageCreateInfo.sType = VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO;
  imageCreateInfo.flags = 0;
  imageCreateInfo.imageType = texture.imageType;
  imageCreateInfo.format = texture.format;
  imageCreateInfo.extent = extent;
  imageCreateInfo.mipLevels = texture.levelCount;
  imageCreateInfo.arrayLayers = texture.layerCount;
  imageCreateInfo.samples = VK_SAMPLE_COUNT_1_BIT;
  imageCreateInfo.tiling = VK_IMAGE_TILING_OPTIMAL;
  imageCreateInfo.usage = texture.usageFlags;
  imageCreateInfo.sharingMode = VK_SHARING_MODE_EXCLUSIVE;
  imageCreateInfo.queueFamilyIndexCount = 0;
  imageCreateInfo.pQueueFamilyIndices = nullptr;
  imageCreateInfo.initialLayout = texture.layout;

  VmaAllocationCreateInfo allocationCreateInfo = {};
  allocationCreateInfo.usage = VMA_MEMORY_USAGE_AUTO;

  VK_CHECK(vmaCreateImage(
      allocator,
      &imageCreateInfo,
      &allocationCreateInfo,
      &texture.image,
      &texture.allocation,
      &texture.allocationInfo));

  LOG_ERROR("texture.memoryFlags: %i", texture.memoryFlags);
  vmaGetAllocationMemoryProperties(allocator, texture.allocation, &texture.memoryFlags);

  LOG_ERROR("texture.memoryFlags: %i", texture.memoryFlags);

  VkComponentMapping componentMapping = {};
  componentMapping.r = VK_COMPONENT_SWIZZLE_IDENTITY;
  componentMapping.g = VK_COMPONENT_SWIZZLE_IDENTITY;
  componentMapping.b = VK_COMPONENT_SWIZZLE_IDENTITY;
  componentMapping.a = VK_COMPONENT_SWIZZLE_IDENTITY;

  VkImageSubresourceRange imageSubresourceRange = {};
  imageSubresourceRange.aspectMask = texture.aspectFlags;
  imageSubresourceRange.baseMipLevel = 0;
  imageSubresourceRange.levelCount = texture.levelCount;
  imageSubresourceRange.baseArrayLayer = 0;
  imageSubresourceRange.layerCount = texture.layerCount;

  VkImageViewCreateInfo imageViewInfo = {};
  imageViewInfo.sType = VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO;
  imageViewInfo.image = texture.image;
  imageViewInfo.viewType = texture.imageViewType;
  imageViewInfo.format = texture.format;
  imageViewInfo.components = componentMapping;
  imageViewInfo.subresourceRange = imageSubresourceRange;

  VK_CHECK(vkCreateImageView(device, &imageViewInfo, allocationCallbacks, &texture.imageView));

#ifndef NDEBUG
  std::string imageName = std::format("{} (Image)", description.debugName);
  std::string imageViewName = std::format("{} (Image View)", description.debugName);
  VkDebugUtilsObjectNameInfoEXT debugUtilsObjectNameInfoEXT = {};
  debugUtilsObjectNameInfoEXT.sType = VK_STRUCTURE_TYPE_DEBUG_UTILS_OBJECT_NAME_INFO_EXT;
  debugUtilsObjectNameInfoEXT.pObjectName = imageName.c_str();
  debugUtilsObjectNameInfoEXT.objectType = VK_OBJECT_TYPE_IMAGE;
  debugUtilsObjectNameInfoEXT.objectHandle = (uint64_t)texture.image;
  VK_CHECK(vkSetDebugUtilsObjectNameEXT(device, &debugUtilsObjectNameInfoEXT));
  debugUtilsObjectNameInfoEXT.pObjectName = imageViewName.c_str();
  debugUtilsObjectNameInfoEXT.objectType = VK_OBJECT_TYPE_IMAGE_VIEW;
  debugUtilsObjectNameInfoEXT.objectHandle = (uint64_t)texture.imageView;
  VK_CHECK(vkSetDebugUtilsObjectNameEXT(device, &debugUtilsObjectNameInfoEXT));
#endif

  descriptorSync |= DescriptorSync::SampledImage;

  return textures.allocate(nullptr, texture);
}

auto Gpu::write(Handle<Texture> handle, VkCommandBuffer commandBuffer, const Texture::Write &writeInfo) -> void {
  Texture &texture = *textures.get(handle);

  if ((texture.memoryFlags & VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT) == 0U) {
    assert(false && "TODO: write texture allocated in host visible memory");
  }

  VkBufferCreateInfo stagingBufferCreateInfo = {};
  stagingBufferCreateInfo.sType = VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO;
  stagingBufferCreateInfo.size = writeInfo.dataSize;
  stagingBufferCreateInfo.usage = VK_BUFFER_USAGE_TRANSFER_SRC_BIT;

  VmaAllocationCreateInfo stagingAllocationCreateInfo = {};
  stagingAllocationCreateInfo.usage = VMA_MEMORY_USAGE_AUTO;
  stagingAllocationCreateInfo.flags |= VMA_ALLOCATION_CREATE_HOST_ACCESS_SEQUENTIAL_WRITE_BIT;
  stagingAllocationCreateInfo.flags |= VMA_ALLOCATION_CREATE_MAPPED_BIT;

  VkBuffer stagingBuffer = {};
  VmaAllocation stagingAllocation = {};
  VmaAllocationInfo stagingAllocationInfo = {};

  VK_CHECK(vmaCreateBuffer(
      allocator,
      &stagingBufferCreateInfo,
      &stagingAllocationCreateInfo,
      &stagingBuffer,
      &stagingAllocation,
      &stagingAllocationInfo));

  VK_CHECK(vmaCopyMemoryToAllocation(allocator, writeInfo.data, stagingAllocation, 0, stagingBufferCreateInfo.size));

  VkBufferMemoryBarrier bufferMemoryBarrier = {};
  bufferMemoryBarrier.sType = VK_STRUCTURE_TYPE_BUFFER_MEMORY_BARRIER,
  bufferMemoryBarrier.srcAccessMask = VK_ACCESS_HOST_WRITE_BIT;
  bufferMemoryBarrier.dstAccessMask = VK_ACCESS_TRANSFER_READ_BIT;
  bufferMemoryBarrier.srcQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED;
  bufferMemoryBarrier.dstQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED;
  bufferMemoryBarrier.buffer = stagingBuffer;
  bufferMemoryBarrier.offset = 0;
  bufferMemoryBarrier.size = VK_WHOLE_SIZE;

  VkImageMemoryBarrier imageMemoryBarrier = {};
  imageMemoryBarrier.sType = VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER;
  imageMemoryBarrier.srcAccessMask = 0;
  imageMemoryBarrier.dstAccessMask = VK_ACCESS_TRANSFER_WRITE_BIT;
  imageMemoryBarrier.oldLayout = texture.layout;
  imageMemoryBarrier.newLayout = VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL;
  imageMemoryBarrier.srcQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED;
  imageMemoryBarrier.dstQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED;
  imageMemoryBarrier.image = texture.image;
  imageMemoryBarrier.subresourceRange.aspectMask = texture.aspectFlags;
  imageMemoryBarrier.subresourceRange.baseMipLevel = 0;
  imageMemoryBarrier.subresourceRange.levelCount = texture.levelCount;
  imageMemoryBarrier.subresourceRange.baseArrayLayer = 0;
  imageMemoryBarrier.subresourceRange.layerCount = texture.layerCount;

  vkCmdPipelineBarrier(
      commandBuffer,
      VK_PIPELINE_STAGE_HOST_BIT,
      VK_PIPELINE_STAGE_TRANSFER_BIT,
      0,
      0,
      nullptr,
      1,
      &bufferMemoryBarrier,
      1,
      &imageMemoryBarrier);

  VkBufferImageCopy bufferImageCopy[writeInfo.regions.size()];

  for (uint32_t i = 0; i < writeInfo.regions.size(); i++) {
    const Texture::Region &region = writeInfo.regions[i];
    bufferImageCopy[i] = (VkBufferImageCopy){};
    bufferImageCopy[i].bufferOffset = 0;
    bufferImageCopy[i].bufferRowLength = 0;
    bufferImageCopy[i].bufferImageHeight = 0;
    bufferImageCopy[i].imageSubresource.aspectMask = texture.aspectFlags;
    bufferImageCopy[i].imageSubresource.layerCount = texture.layerCount;
    bufferImageCopy[i].imageSubresource.mipLevel = 0;
    bufferImageCopy[i].imageSubresource.baseArrayLayer = 0;
    bufferImageCopy[i].imageExtent.width = region.width;
    bufferImageCopy[i].imageExtent.height = region.height;
    bufferImageCopy[i].imageExtent.depth = region.depth;
    bufferImageCopy[i].imageOffset.x = region.offsetX;
    bufferImageCopy[i].imageOffset.y = region.offsetY;
    bufferImageCopy[i].imageOffset.z = region.offsetZ;
  }

  vkCmdCopyBufferToImage(
      commandBuffer,
      stagingBuffer,
      texture.image,
      imageMemoryBarrier.newLayout,
      writeInfo.regions.size(),
      bufferImageCopy);

  imageMemoryBarrier.oldLayout = imageMemoryBarrier.newLayout;
  imageMemoryBarrier.newLayout = VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL;
  imageMemoryBarrier.srcAccessMask = imageMemoryBarrier.dstAccessMask;
  imageMemoryBarrier.dstAccessMask = VK_ACCESS_SHADER_READ_BIT;

  vkCmdPipelineBarrier(
      commandBuffer,
      VK_PIPELINE_STAGE_TRANSFER_BIT,
      VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT,
      0,
      0,
      nullptr,
      0,
      nullptr,
      1,
      &imageMemoryBarrier);

  descriptorSync |= DescriptorSync::SampledImage;

  defer(std::packaged_task<void()>([&, vkBuffer = stagingBuffer, vkAllocation = stagingAllocation]() -> void {
    vmaDestroyBuffer(allocator, vkBuffer, vkAllocation);
  }));
}

auto Gpu::destroy(Handle<Texture> texture) -> void {
  textures.free(texture);
}

auto Gpu::destroy(Texture &texture) -> void {
  defer(std::packaged_task<void()>([&, vkImage = texture.image, vkImageView = texture.imageView, vkAllocation = texture.allocation]() -> void {
    vkDestroyImageView(device, vkImageView, allocationCallbacks);
    vmaDestroyImage(allocator, vkImage, vkAllocation);
  }));
}

auto Gpu::create(World::Desc *description) -> Handle<World> {
  Buffer::Desc vertexBufferDesc = {};
  vertexBufferDesc.usage = Buffer::Usage::Vertex;
  vertexBufferDesc.size = description->vertexCount * description->vertexSize;

  Buffer::Desc indexBufferDesc = {};
  indexBufferDesc.usage = Buffer::Usage::Index;
  indexBufferDesc.size = description->indexCount * description->indexSize;

  Buffer::Desc indirectBufferDesc = {};
  indirectBufferDesc.usage = Buffer::Usage::Indirect;
  indirectBufferDesc.size = description->meshCount * sizeof(VkDrawIndexedIndirectCommand);

  Buffer::Desc transformBufferDesc = {};
  transformBufferDesc.usage = Buffer::Usage::Storage;
  transformBufferDesc.size = description->meshCount * sizeof(glm::mat4);

  Buffer::Desc drawBufferDesc = {};
  drawBufferDesc.usage = Buffer::Usage::Storage;
  drawBufferDesc.size = description->meshCount * sizeof(Draw);

  Pipeline::Desc pipelineDesc = {};
  pipelineDesc.shader = "basic";
  pipelineDesc.colorAttachmentFormat = VK_FORMAT_B8G8R8A8_SRGB;
  pipelineDesc.windingOrder = Pipeline::WindingOrder::CounterClockwise;

#ifndef NDEBUG
  vertexBufferDesc.debugName = "Vertex Buffer";
  indexBufferDesc.debugName = "Index Buffer";
  indirectBufferDesc.debugName = "Indirect Buffer";
  transformBufferDesc.debugName = "Transform Buffer";
  drawBufferDesc.debugName = "Draw Buffer";
  pipelineDesc.debugName = "Pipeline";
#endif

  World world = {};
  world.description = description;
  world.vertexBuffer = create(vertexBufferDesc);
  world.indexBuffer = create(indexBufferDesc);
  world.indirectBuffer = create(indirectBufferDesc);
  world.transformBuffer = create(transformBufferDesc);
  world.drawBuffer = create(drawBufferDesc);
  world.pipeline = create(pipelineDesc);

  std::vector<VkDrawIndexedIndirectCommand> drawCommands(description->meshCount);
  std::vector<Draw> draws(description->meshCount);

  for (auto i = 0; std::cmp_less(i, description->meshCount); i++) {
    drawCommands[i].indexCount = description->meshData[i].indexCount;
    drawCommands[i].instanceCount = 1;
    drawCommands[i].firstIndex = description->meshData[i].indexOffset;
    drawCommands[i].vertexOffset = static_cast<int32_t>(description->meshData[i].vertexOffset);
    drawCommands[i].firstInstance = i;
    draws[i].transformIdx = i;
  }

  submit([&](VkCommandBuffer commandBuffer) -> void {
    Buffer::Write vertexBufferWrite = {};
    void *pVertexData[] = {description->vertexData};
    vertexBufferWrite.writesData = pVertexData;
    vertexBufferWrite.writesSize = 1;
    vertexBufferWrite.writesSizes = &vertexBufferDesc.size;
    write(world.vertexBuffer, commandBuffer, vertexBufferWrite);

    Buffer::Write indexBufferWrite = {};
    void *pIndexData[] = {description->indexData};
    indexBufferWrite.writesData = pIndexData;
    indexBufferWrite.writesSize = 1;
    indexBufferWrite.writesSizes = &indexBufferDesc.size;
    write(world.indexBuffer, commandBuffer, indexBufferWrite);

    Buffer::Write indirectBufferWrite = {};
    void *pIndirectData[] = {drawCommands.data()};
    indirectBufferWrite.writesData = pIndirectData;
    indirectBufferWrite.writesSize = 1;
    indirectBufferWrite.writesSizes = &indirectBufferDesc.size;
    write(world.indirectBuffer, commandBuffer, indirectBufferWrite);

    Buffer::Write transformBufferWrite = {};
    void *pTransformData[] = {description->transformData};
    transformBufferWrite.writesData = pTransformData;
    transformBufferWrite.writesSize = 1;
    transformBufferWrite.writesSizes = &transformBufferDesc.size;
    write(world.transformBuffer, commandBuffer, transformBufferWrite);

    Buffer::Write drawBufferWrite = {};
    void *pDrawData[] = {draws.data()};
    drawBufferWrite.writesData = pDrawData;
    drawBufferWrite.writesSize = 1;
    drawBufferWrite.writesSizes = &drawBufferDesc.size;
    write(world.drawBuffer, commandBuffer, drawBufferWrite);
  });

  return worlds.allocate(nullptr, world);
}

auto Gpu::destroy(Handle<World> world) -> void {
}

auto Gpu::destroy(World &world) -> void {
}

auto Gpu::render(Handle<Surface> surfaceHandle, Handle<World> worldHandle, glm::mat4 projection, uint32_t width, uint32_t height, float clearColor) -> void {
  Surface &surface = *surfaces.get(surfaceHandle);

  if (width != surface.extent.width || height != surface.extent.height) {
    initSwapchain(surface, width, height);
  }

  const VkFence fence = frameFences[frameNumber % frameFences.size()];
  assert(fence != VK_NULL_HANDLE);

  while (vkWaitForFences(device, 1, &fence, VK_TRUE, UINT64_MAX) == VK_TIMEOUT) {
    ;
  }
  VK_CHECK(vkResetFences(device, 1, &fence));

  VkSemaphore imageReadyForRender = surface.readyForRender[frameNumber % surface.readyForRender.size()];

  uint32_t swapchainImageIndex = {};
  VkResult acquireResult = vkAcquireNextImageKHR(device, surface.swapchain, UINT64_MAX, imageReadyForRender, VK_NULL_HANDLE, &swapchainImageIndex);
  VkSemaphore imageReadyForPresent = surface.readyForPresent[swapchainImageIndex];

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
  imageMemoryBarrier2.image = surface.images[swapchainImageIndex];
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
  renderingAttachmentInfo.imageView = surface.imageViews[swapchainImageIndex];
  renderingAttachmentInfo.imageLayout = VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL;
  renderingAttachmentInfo.loadOp = VK_ATTACHMENT_LOAD_OP_CLEAR;
  renderingAttachmentInfo.storeOp = VK_ATTACHMENT_STORE_OP_STORE;
  renderingAttachmentInfo.clearValue.color = clearColorValue;

  VkRenderingInfo renderingInfo = {};
  renderingInfo.sType = VK_STRUCTURE_TYPE_RENDERING_INFO;
  renderingInfo.layerCount = 1;
  renderingInfo.colorAttachmentCount = 1;
  renderingInfo.pColorAttachments = &renderingAttachmentInfo;
  renderingInfo.renderArea.extent = surface.extent;
  renderingInfo.renderArea.offset.x = 0;
  renderingInfo.renderArea.offset.y = 0;

  vkCmdBeginRendering(commandBuffer, &renderingInfo);

  VkViewport viewport = {};
  viewport.x = 0;
  viewport.y = 0;
  viewport.width = (float)surface.extent.width;
  viewport.height = (float)surface.extent.height;
  viewport.minDepth = 0;
  viewport.maxDepth = 1;
  vkCmdSetViewport(commandBuffer, 0, 1, &viewport);

  assert(surface.extent.width > 0);

  VkRect2D scissor = {};
  scissor.extent = surface.extent;
  scissor.offset.x = 0;
  scissor.offset.y = 0;
  vkCmdSetScissor(commandBuffer, 0, 1, &scissor);

  World *world = worlds.get(worldHandle);
  Buffer *vertexBuffer = buffers.get(world->vertexBuffer);
  Buffer *indexBuffer = buffers.get(world->indexBuffer);
  Buffer *indirectBuffer = buffers.get(world->indirectBuffer);
  Buffer *drawBuffer = buffers.get(world->drawBuffer);
  Buffer *transformBuffer = buffers.get(world->transformBuffer);
  Pipeline *pipeline = pipelines.get(world->pipeline);

  World::PushConstants pushConstants = {};
  pushConstants.drawBuffer = drawBuffer->address;
  pushConstants.transformBuffer = transformBuffer->address;
  pushConstants.vertexBuffer = vertexBuffer->address;
  pushConstants.proj = projection;
  pushConstants.proj[1][1] *= -1;

  vkCmdBindIndexBuffer(commandBuffer, indexBuffer->buffer, 0, VK_INDEX_TYPE_UINT32);
  vkCmdBindPipeline(commandBuffer, VK_PIPELINE_BIND_POINT_GRAPHICS, pipeline->pipeline);
  vkCmdBindDescriptorSets(commandBuffer, VK_PIPELINE_BIND_POINT_GRAPHICS, pipeline->layout, 0, 1, &descriptorSet, 0, nullptr);
  vkCmdPushConstants(commandBuffer, pipeline->layout, VK_SHADER_STAGE_VERTEX_BIT, 0, sizeof(World::PushConstants), &pushConstants);
  vkCmdDrawIndexedIndirect(commandBuffer, indirectBuffer->buffer, 0, world->description->meshCount, sizeof(VkDrawIndexedIndirectCommand));

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
  imageMemoryBarrier2.image = surface.images[swapchainImageIndex];
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
  VK_CHECK(vkQueueSubmit(graphicsQueue, 1, &submitInfo, fence));

  VkPresentInfoKHR presentInfo = {};
  presentInfo.sType = VK_STRUCTURE_TYPE_PRESENT_INFO_KHR;
  presentInfo.waitSemaphoreCount = 1;
  presentInfo.pWaitSemaphores = &imageReadyForPresent;
  presentInfo.swapchainCount = 1;
  presentInfo.pSwapchains = &surface.swapchain;
  presentInfo.pImageIndices = &swapchainImageIndex;
  VK_CHECK(vkQueuePresentKHR(graphicsQueue, &presentInfo));

  frameNumber++;
}

auto Gpu::submit(std::function<void(VkCommandBuffer commandBuffer)> &&recordCommands) const -> void {
  VkCommandBuffer commandBuffer = VK_NULL_HANDLE;

  VkCommandBufferAllocateInfo commandBufferAllocateInfo = {};
  commandBufferAllocateInfo.sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO;
  commandBufferAllocateInfo.commandPool = graphicsCommandPool;
  commandBufferAllocateInfo.level = VK_COMMAND_BUFFER_LEVEL_PRIMARY;
  commandBufferAllocateInfo.commandBufferCount = 1;
  VK_CHECK(vkAllocateCommandBuffers(device, &commandBufferAllocateInfo, &commandBuffer));

  VkCommandBufferBeginInfo commandBufferBeginInfo = {};
  commandBufferBeginInfo.sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO;
  commandBufferBeginInfo.flags = VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT;
  commandBufferBeginInfo.pInheritanceInfo = nullptr;
  VK_CHECK(vkBeginCommandBuffer(commandBuffer, &commandBufferBeginInfo));

  recordCommands(commandBuffer);

  VK_CHECK(vkEndCommandBuffer(commandBuffer));

  VkCommandBufferSubmitInfo commandBufferSubmitInfo = {};
  commandBufferSubmitInfo.sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_SUBMIT_INFO;
  commandBufferSubmitInfo.commandBuffer = commandBuffer;

  VkSubmitInfo2 submitInfo2 = {};
  submitInfo2.sType = VK_STRUCTURE_TYPE_SUBMIT_INFO_2;
  submitInfo2.commandBufferInfoCount = 1;
  submitInfo2.pCommandBufferInfos = &commandBufferSubmitInfo;
  VK_CHECK(vkQueueSubmit2(graphicsQueue, 1, &submitInfo2, VK_NULL_HANDLE));

  vkDeviceWaitIdle(device);
}

auto Gpu::create(Surface::Desc &description) -> Handle<Surface> {
  LOG_DEBUG("Surface");
  Surface surface = {};
  bool surfaceOk = SDL_Vulkan_CreateSurface(description.window, instance, allocationCallbacks, &surface.surface);
  assert(surfaceOk && "SDL failed creating surface");
  assert(surface.surface != VK_NULL_HANDLE);
  initSwapchain(surface, description.width, description.height);
  return surfaces.allocate(nullptr, surface);
}

auto Gpu::destroy(Handle<Surface> surface) -> void {
  surfaces.free(surface);
}

auto Gpu::destroy(Surface &surface) -> void {
  vkDeviceWaitIdle(device);
  cleanupSwapchainResources(surface);
  vkDestroySwapchainKHR(device, surface.swapchain, allocationCallbacks);
  vkDestroySurfaceKHR(instance, surface.surface, allocationCallbacks);
  LOG_DEBUG("~Surface");
}

auto Gpu::initSwapchain(Surface &surface, uint32_t width, uint32_t height) -> void {
  if (surface.swapchain != VK_NULL_HANDLE) {
    cleanupSwapchainResources(surface);
  }

  VkSurfaceCapabilitiesKHR surfaceCapabilities = {};
  VK_CHECK(vkGetPhysicalDeviceSurfaceCapabilitiesKHR(physicalDevice, surface.surface, &surfaceCapabilities));

  uint32_t surfaceFormatCount = 0;
  VK_CHECK(vkGetPhysicalDeviceSurfaceFormatsKHR(physicalDevice, surface.surface, &surfaceFormatCount, nullptr));
  std::vector<VkSurfaceFormatKHR> availableSurfaceFormats(surfaceFormatCount);
  VK_CHECK(vkGetPhysicalDeviceSurfaceFormatsKHR(physicalDevice, surface.surface, &surfaceFormatCount, availableSurfaceFormats.data()));

  surface.format = availableSurfaceFormats[0];
  for (uint32_t i = 0; i < surfaceFormatCount; i++) {
    if (availableSurfaceFormats[i].format == VK_FORMAT_B8G8R8A8_SRGB && availableSurfaceFormats[i].colorSpace == VK_COLOR_SPACE_SRGB_NONLINEAR_KHR) {
      surface.format = availableSurfaceFormats[i];
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

  surface.extent.width = std::max(std::min(width, surfaceCapabilities.maxImageExtent.width), surfaceCapabilities.minImageExtent.width);
  surface.extent.height = std::max(std::min(height, surfaceCapabilities.maxImageExtent.height), surfaceCapabilities.minImageExtent.height);

  uint32_t imageCount = surfaceCapabilities.minImageCount + 1;
  if (surfaceCapabilities.maxImageCount > 0 && imageCount > surfaceCapabilities.maxImageCount) {
    imageCount = surfaceCapabilities.maxImageCount;
  }

  VkSwapchainCreateInfoKHR swapchainCreateInfo = {};
  swapchainCreateInfo.sType = VK_STRUCTURE_TYPE_SWAPCHAIN_CREATE_INFO_KHR;
  swapchainCreateInfo.surface = surface.surface;
  swapchainCreateInfo.minImageCount = imageCount;
  swapchainCreateInfo.imageFormat = surface.format.format;
  swapchainCreateInfo.imageColorSpace = surface.format.colorSpace;
  swapchainCreateInfo.imageExtent = surface.extent;
  swapchainCreateInfo.imageArrayLayers = 1;
  swapchainCreateInfo.imageUsage = VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT;
  swapchainCreateInfo.imageSharingMode = VK_SHARING_MODE_EXCLUSIVE;
  swapchainCreateInfo.preTransform = surfaceCapabilities.currentTransform;
  swapchainCreateInfo.compositeAlpha = VK_COMPOSITE_ALPHA_OPAQUE_BIT_KHR;
  swapchainCreateInfo.presentMode = presentMode;
  swapchainCreateInfo.clipped = VK_TRUE;
  swapchainCreateInfo.oldSwapchain = surface.swapchain;

  VkSemaphoreCreateInfo semaphoreCreateInfo = {};
  semaphoreCreateInfo.sType = VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO;

  VK_CHECK(vkCreateSwapchainKHR(device, &swapchainCreateInfo, allocationCallbacks, &surface.swapchain));
  assert(surface.swapchain != VK_NULL_HANDLE);

  uint32_t swapchainImageCount = 0;
  VK_CHECK(vkGetSwapchainImagesKHR(device, surface.swapchain, &swapchainImageCount, nullptr));
  surface.images.resize(swapchainImageCount);
  surface.imageViews.resize(swapchainImageCount);
  surface.readyForRender.resize(swapchainImageCount);
  surface.readyForPresent.resize(swapchainImageCount);
  VK_CHECK(vkGetSwapchainImagesKHR(device, surface.swapchain, &swapchainImageCount, surface.images.data()));

  VkImageViewCreateInfo imageViewCreateInfo = {};
  imageViewCreateInfo.sType = VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO;
  imageViewCreateInfo.viewType = VK_IMAGE_VIEW_TYPE_2D;
  imageViewCreateInfo.format = surface.format.format;
  imageViewCreateInfo.components.r = VK_COMPONENT_SWIZZLE_IDENTITY;
  imageViewCreateInfo.components.g = VK_COMPONENT_SWIZZLE_IDENTITY;
  imageViewCreateInfo.components.b = VK_COMPONENT_SWIZZLE_IDENTITY;
  imageViewCreateInfo.components.a = VK_COMPONENT_SWIZZLE_IDENTITY;
  imageViewCreateInfo.subresourceRange.aspectMask = VK_IMAGE_ASPECT_COLOR_BIT;
  imageViewCreateInfo.subresourceRange.baseMipLevel = 0;
  imageViewCreateInfo.subresourceRange.levelCount = VK_REMAINING_MIP_LEVELS;
  imageViewCreateInfo.subresourceRange.baseArrayLayer = 0;
  imageViewCreateInfo.subresourceRange.layerCount = 1;

  for (uint32_t i = 0; i < surface.images.size(); i++) {
    imageViewCreateInfo.image = surface.images[i];
    VK_CHECK(vkCreateSemaphore(device, &semaphoreCreateInfo, allocationCallbacks, &surface.readyForRender[i]));
    VK_CHECK(vkCreateSemaphore(device, &semaphoreCreateInfo, allocationCallbacks, &surface.readyForPresent[i]));
    VK_CHECK(vkCreateImageView(device, &imageViewCreateInfo, allocationCallbacks, &surface.imageViews[i]));
#ifndef NDEBUG
    std::string imageName = std::format("Swapchain Image {}", i);
    std::string readyForRenderName = std::format("Swapchain Image {} Ready For Render Semaphore", i);
    std::string readyForPresentName = std::format("Swapchain Image {} Ready For Present Semaphore", i);
    std::string imageViewName = std::format("Swapchain Image {} View", i);

    VkDebugUtilsObjectNameInfoEXT debugUtilsObjectNameInfoEXT = {};
    debugUtilsObjectNameInfoEXT.sType = VK_STRUCTURE_TYPE_DEBUG_UTILS_OBJECT_NAME_INFO_EXT;

    debugUtilsObjectNameInfoEXT.pObjectName = imageName.c_str();
    debugUtilsObjectNameInfoEXT.objectType = VK_OBJECT_TYPE_IMAGE;
    debugUtilsObjectNameInfoEXT.objectHandle = (uint64_t)surface.images[i];
    VK_CHECK(vkSetDebugUtilsObjectNameEXT(device, &debugUtilsObjectNameInfoEXT));

    debugUtilsObjectNameInfoEXT.pObjectName = imageViewName.c_str();
    debugUtilsObjectNameInfoEXT.objectType = VK_OBJECT_TYPE_IMAGE_VIEW;
    debugUtilsObjectNameInfoEXT.objectHandle = (uint64_t)surface.imageViews[i];
    VK_CHECK(vkSetDebugUtilsObjectNameEXT(device, &debugUtilsObjectNameInfoEXT));

    debugUtilsObjectNameInfoEXT.pObjectName = readyForRenderName.c_str();
    debugUtilsObjectNameInfoEXT.objectType = VK_OBJECT_TYPE_SEMAPHORE;
    debugUtilsObjectNameInfoEXT.objectHandle = (uint64_t)surface.readyForRender[i];
    VK_CHECK(vkSetDebugUtilsObjectNameEXT(device, &debugUtilsObjectNameInfoEXT));

    debugUtilsObjectNameInfoEXT.pObjectName = readyForPresentName.c_str();
    debugUtilsObjectNameInfoEXT.objectType = VK_OBJECT_TYPE_SEMAPHORE;
    debugUtilsObjectNameInfoEXT.objectHandle = (uint64_t)surface.readyForPresent[i];
    VK_CHECK(vkSetDebugUtilsObjectNameEXT(device, &debugUtilsObjectNameInfoEXT));
#endif
  }
}

auto Gpu::cleanupSwapchainResources(Surface &surface) -> void {
  for (uint32_t i = 0; i < surface.images.size(); i++) {
    vkDestroyImageView(device, surface.imageViews[i], allocationCallbacks);
    vkDestroySemaphore(device, surface.readyForRender[i], allocationCallbacks);
    vkDestroySemaphore(device, surface.readyForPresent[i], allocationCallbacks);
  }
}
