module window.window;

import std.stdio;
import std.conv;
import std.string;
import std.array;
import std.typecons;
import std.algorithm.comparison: clamp;
import std.process: execute;
import std.file;

import doml.vector_2i;
import doml.vector_2d;
import doml.vector_3d;

import delta_time;
import aaset;

import erupted;
import erupted.types;
import erupted.vulkan_lib_loader;
import erupted.platform_extensions;

import loader = bindbc.loader.sharedlib;
import bindbc.glfw;

mixin(bindGLFW_Vulkan);


private Vector3d clearColor;

// GLFW fields
private string title;
private Vector2i windowSize;

private GLFWwindow* window = null;
private GLFWmonitor* monitor = null;
private GLFWvidmode videoMode;
private bool fullscreen = false;
// 0 none, 1 normal vsync, 2 double buffered
private int vsync = 1;

// These 3 functions calculate the FPS
private double deltaAccumulator = 0.0;
private int fpsCounter = 0;
private int FPS = 0;

// Vulkan fields

private VkInstance instance;
VkDebugUtilsMessengerEXT debugMessenger;
VkPhysicalDevice physicalDevice = VK_NULL_HANDLE;
VkDevice device;
VkQueue graphicsQueue;
VkSurfaceKHR surface;
VkQueue presentQueue;
VkSwapchainKHR swapChain;
VkImage[] swapChainImages;
VkFormat swapChainImageFormat;
VkExtent2D swapChainExtent;
VkImageView[] swapChainImageViews;
VkRenderPass renderPass;
VkPipelineLayout pipelineLayout;
VkPipeline graphicsPipeline;
VkFramebuffer[] swapChainFramebuffers;

// For Vulkan debugging
private bool enableValidationLayers  = true;
// For EXCESSIVE debugging
bool excessiveDebug = false;

const string[] validationLayers = [
    "VK_LAYER_KHRONOS_validation"
];

const string[] deviceExtensions = [
    VK_KHR_SWAPCHAIN_EXTENSION_NAME
];

// Just the initializer for the module
void initialize() {
    if (!initializeGLFW()) {
        throw new Exception("GLFW failed");
    }
    initializeVulkan();
}

//* =================================================== VULKAN TOOLS ========================================

//** ------- BEGIN VULKAN STRUCTS --------------
// Simply holds instruction queues
private struct QueueFamilyIndices {
    Nullable!uint graphicsFamily;
    Nullable!uint presentFamily;

    /// Check if the graphics family index exists
    bool isComplete() {
        return !this.graphicsFamily.isNull() && !this.presentFamily.isNull();
    }
}

struct SwapChainSupportDetails {
    VkSurfaceCapabilitiesKHR capabilities;
    VkSurfaceFormatKHR[] formats;
    VkPresentModeKHR[] presentModes;
}

//!! -------------- END VULKAN STRUCTS -------

//** ---------------- BEGIN VULKAN INIT --------------------------------------------

private void initializeVulkan() {

    // Attempt to load the BindBC Vulkan library
    if (!loadGLFW_Vulkan()) {
        throw new Exception("Vulkan: Failed to load BindBC Vulkan library!");
    }

    // Attempt to load up Erupted global level functions
    if (!loadGlobalLevelFunctions()) {
        throw new Exception("Vulkan: Failed to load Erupted global level functions!");
    }

    // Create the Vulkan instance
    createVulkanInstance();

    setupDebugMessenger();

    createSurface();

    // Now load up calls from Erupted into memory
    loadDeviceLevelFunctions(instance);

    pickPhysicalDevice();
    
    createLogicalDevice();

    createSwapChain();

    createImageViews();

    createRenderPass();

    // This literally just runs an executable to turn glsl into spir-v
    executeHackJobShaderCompile();

    createGraphicsPipeline();

    createFramebuffers();
}

//!! ---------------- END VULKAN INIT -------------------------------

//** ----------------- BEGIN FRAMEBUFFER TOOLS --------------------


void createFramebuffers() {

    swapChainFramebuffers.length = swapChainImageViews.length;

    for (size_t i = 0; i < swapChainImageViews.length; i++) {
        VkImageView[] attachments = [
            swapChainImageViews[i]
        ];

        VkFramebufferCreateInfo framebufferInfo;
        framebufferInfo.sType = VK_STRUCTURE_TYPE_FRAMEBUFFER_CREATE_INFO;
        framebufferInfo.renderPass = renderPass;
        framebufferInfo.attachmentCount = 1;
        framebufferInfo.pAttachments = attachments.ptr;
        framebufferInfo.width = swapChainExtent.width;
        framebufferInfo.height = swapChainExtent.height;
        framebufferInfo.layers = 1;

        if (vkCreateFramebuffer(device, &framebufferInfo, VK_NULL_HANDLE, &swapChainFramebuffers[i]) != VK_SUCCESS) {
            throw new Exception("Vulkan: Failed to create framebuffer!");
        }
    }
    writeln("Vulkan: Successfully created framebuffers!");

}


//!! ----------------- END FRAMEBUFFER TOOLS -----------------------

//** ---------------------  BEGIN RENDER PASS TOOLS ---------------------

void createRenderPass() {

    // Create color attachment

    VkAttachmentDescription colorAttachment;
    colorAttachment.format = swapChainImageFormat;
    colorAttachment.samples = VK_SAMPLE_COUNT_1_BIT;

    /**

    Notes for loadOp:

    VK_ATTACHMENT_LOAD_OP_LOAD: Preserve the existing contents of the attachment
    VK_ATTACHMENT_LOAD_OP_CLEAR: Clear the values to a constant at the start
    VK_ATTACHMENT_LOAD_OP_DONT_CARE: Existing contents are undefined; we don't care about them

    Notes for storeOp:

    VK_ATTACHMENT_STORE_OP_STORE: Rendered contents will be stored in memory and can be read later
    VK_ATTACHMENT_STORE_OP_DONT_CARE: Contents of the framebuffer will be undefined after the rendering operation

    */

    colorAttachment.loadOp = VK_ATTACHMENT_LOAD_OP_CLEAR;
    colorAttachment.storeOp = VK_ATTACHMENT_STORE_OP_STORE;

    colorAttachment.stencilLoadOp = VK_ATTACHMENT_LOAD_OP_DONT_CARE;
    colorAttachment.stencilStoreOp = VK_ATTACHMENT_STORE_OP_DONT_CARE;

    /**

    Notes for finalLayout:

    VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL: Images used as color attachment
    VK_IMAGE_LAYOUT_PRESENT_SRC_KHR: Images to be presented in the swap chain
    VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL: Images to be used as destination for a memory copy operation

    */
    colorAttachment.initialLayout = VK_IMAGE_LAYOUT_UNDEFINED;
    colorAttachment.finalLayout = VK_IMAGE_LAYOUT_PRESENT_SRC_KHR;


    // Createattachment references

    VkAttachmentReference colorAttachmentRef;
    colorAttachmentRef.attachment = 0;
    colorAttachmentRef.layout = VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL;

    // Create subpass

    /**

    Notes for subpass:

    pInputAttachments: Attachments that are read from a shader
    pResolveAttachments: Attachments used for multisampling color attachments
    pDepthStencilAttachment: Attachment for depth and stencil data
    pPreserveAttachments: Attachments that are not used by this subpass, but for which the data must be preserved

    */

    VkSubpassDescription subpass;
    subpass.pipelineBindPoint = VK_PIPELINE_BIND_POINT_GRAPHICS;
    // The index of the attachment in this array is directly referenced from the fragment shader with the layout(location = 0) out vec4 outColor directive!
    subpass.colorAttachmentCount = 1;
    subpass.pColorAttachments = &colorAttachmentRef;

    // Now finally create the render pass

    VkRenderPassCreateInfo renderPassInfo;
    renderPassInfo.sType = VK_STRUCTURE_TYPE_RENDER_PASS_CREATE_INFO;
    renderPassInfo.attachmentCount = 1;
    renderPassInfo.pAttachments = &colorAttachment;
    renderPassInfo.subpassCount = 1;
    renderPassInfo.pSubpasses = &subpass;

    if (vkCreateRenderPass(device, &renderPassInfo, VK_NULL_HANDLE, &renderPass) != VK_SUCCESS) {
        throw new Exception("Vulkan: Failed to create render pass!");
    }

    writeln("Vulkan: Successfully created render pass!");


}



//!! --------------------- END RENDER PASS TOOLS -------------------------

//** -------------- BEGIN SHADER TOOLS -------------------------

//! This is a beautiful hack to compile shaders during runtime
void executeHackJobShaderCompile() {

    /**
    ENFORCE having the glslc compiler onboard!

    It may look weird that we're throwing an error from catching another.
    But we must explain what to do to fix it!

    Thanks for the help, rikki_cattermole!
    */
    try {
        auto spirvCompilerExecutable = execute(["glslc", "--version"]);
        if (spirvCompilerExecutable.status != 0) {
            throw new Exception("");
        }
    } catch(Exception e) {
        throw new Exception("Vulkan: FAILED to find glslc! Is glslc installed on your system? This is required to compile shaders during runtime!");
    }

    auto hackJobVertexShader = execute(["glslc", "./shaders/vertex.vert", "-o", "./shaders/vert.spv"]);

    if (hackJobVertexShader.status != 0) {
        writeln(hackJobVertexShader.output);
        throw new Exception("Vulkan: Vertex Shader failed to compile!");
    }

    auto hackJobFragmentShader = execute(["glslc", "./shaders/frag.frag", "-o", "./shaders/frag.spv"]);

    if (hackJobFragmentShader.status != 0) {
        writeln(hackJobFragmentShader.output);
        throw new Exception("Vulkan: Fragment Shader failed to compile!");
    }
}

VkShaderModule createShaderModule(char[] code) {
    VkShaderModuleCreateInfo createInfo;
    createInfo.sType = VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO;
    createInfo.codeSize = code.length;
    createInfo.pCode = cast(const uint*)code.ptr;

    VkShaderModule shaderModule;
    if (vkCreateShaderModule(device, &createInfo, VK_NULL_HANDLE, &shaderModule) != VK_SUCCESS) {
        throw new Exception("Vulkan: Failed to create shader module!");
    }

    return shaderModule;
}


char[] readFile(string fileLocation) {

    if (!exists(fileLocation)) {
        throw new Exception("Vulkan: File " ~ fileLocation ~ " does not exist!");
    }

    return cast(char[])read(fileLocation);
}


//!! --------------- END SHADER TOOLS ----------------------------


//** ----------------- BEGIN GRAPHICS PIPELINE TOOLS ------------------

void createGraphicsPipeline() {
    auto vertShaderCode = readFile("shaders/vert.spv");
    auto fragShaderCode = readFile("shaders/frag.spv");

    VkShaderModule vertShaderModule = createShaderModule(vertShaderCode);
    VkShaderModule fragShaderModule = createShaderModule(fragShaderCode);

    VkPipelineShaderStageCreateInfo vertShaderStageInfo;
    vertShaderStageInfo.sType = VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO;
    vertShaderStageInfo.stage = VK_SHADER_STAGE_VERTEX_BIT;
    vertShaderStageInfo.Module = vertShaderModule;
    vertShaderStageInfo.pName = "main";

    VkPipelineShaderStageCreateInfo fragShaderStageInfo;
    fragShaderStageInfo.sType = VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO;
    fragShaderStageInfo.stage = VK_SHADER_STAGE_FRAGMENT_BIT;
    fragShaderStageInfo.Module = fragShaderModule;
    fragShaderStageInfo.pName = "main";

    VkPipelineShaderStageCreateInfo[] shaderStages = [vertShaderStageInfo, fragShaderStageInfo];

    // Create shader state 

    VkDynamicState[] dynamicStates = [
        VK_DYNAMIC_STATE_VIEWPORT,
        VK_DYNAMIC_STATE_SCISSOR
    ];

    VkPipelineDynamicStateCreateInfo dynamicState;
    dynamicState.sType = VK_STRUCTURE_TYPE_PIPELINE_DYNAMIC_STATE_CREATE_INFO;
    dynamicState.dynamicStateCount = cast(uint)dynamicStates.length;
    dynamicState.pDynamicStates = dynamicStates.ptr;


    // This is how you do it dynamic (resizable window)
    /*
    VkDynamicState[] dynamicStates = [
        VK_DYNAMIC_STATE_VIEWPORT,
        VK_DYNAMIC_STATE_SCISSOR
    ];

    VkPipelineDynamicStateCreateInfo dynamicState;
    dynamicState.sType = VK_STRUCTURE_TYPE_PIPELINE_DYNAMIC_STATE_CREATE_INFO;
    dynamicState.dynamicStateCount = dynamicStates.length;
    dynamicState.pDynamicStates = dynamicStates.ptr;

    VkPipelineViewportStateCreateInfo viewportState;
    viewportState.sType = VK_STRUCTURE_TYPE_PIPELINE_VIEWPORT_STATE_CREATE_INFO;
    viewportState.viewportCount = 1;
    viewportState.scissorCount = 1;
    */

    // Create vertex input

    VkPipelineVertexInputStateCreateInfo vertexInputInfo;
    vertexInputInfo.sType = VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO;
    vertexInputInfo.vertexBindingDescriptionCount = 0;
    vertexInputInfo.pVertexBindingDescriptions = VK_NULL_HANDLE; // Optional
    vertexInputInfo.vertexAttributeDescriptionCount = 0;
    vertexInputInfo.pVertexAttributeDescriptions = VK_NULL_HANDLE; // Optional

    // Create vertex input assembly
    /**
    Documentation notes:

    VK_PRIMITIVE_TOPOLOGY_POINT_LIST: points from vertices
    VK_PRIMITIVE_TOPOLOGY_LINE_LIST: line from every 2 vertices without reuse
    VK_PRIMITIVE_TOPOLOGY_LINE_STRIP: the end vertex of every line is used as start vertex for the next line
    VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST: triangle from every 3 vertices without reuse
    VK_PRIMITIVE_TOPOLOGY_TRIANGLE_STRIP: the second and third vertex of every triangle are used as first two vertices of the next triangle

    That looks real familiar doesn't it?
    */

    VkPipelineInputAssemblyStateCreateInfo inputAssembly;
    inputAssembly.sType = VK_STRUCTURE_TYPE_PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO;
    inputAssembly.topology = VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST;
    inputAssembly.primitiveRestartEnable = VK_FALSE;

    // Create viewport

    VkViewport viewport;
    viewport.x = 0.0f;
    viewport.y = 0.0f;
    viewport.width = cast(float) swapChainExtent.width;
    viewport.height = cast(float) swapChainExtent.height;
    viewport.minDepth = 0.0f;
    viewport.maxDepth = 1.0f;

    // Scissor the entire framebuffer

    VkRect2D scissor;
    scissor.offset = VkOffset2D(0, 0);
    scissor.extent = swapChainExtent;

    // Create viewport state

    VkPipelineViewportStateCreateInfo viewportState;
    viewportState.sType = VK_STRUCTURE_TYPE_PIPELINE_VIEWPORT_STATE_CREATE_INFO;
    viewportState.viewportCount = 1;
    viewportState.pViewports = &viewport;
    viewportState.scissorCount = 1;
    viewportState.pScissors = &scissor;

    // Create rasterizer

    VkPipelineRasterizationStateCreateInfo rasterizer;
    rasterizer.sType = VK_STRUCTURE_TYPE_PIPELINE_RASTERIZATION_STATE_CREATE_INFO;
    rasterizer.depthClampEnable = VK_FALSE;
    rasterizer.rasterizerDiscardEnable = VK_FALSE;
    /**
    Note: This could be cool to modify.

    VK_POLYGON_MODE_FILL: fill the area of the polygon with fragments
    VK_POLYGON_MODE_LINE: polygon edges are drawn as lines
    VK_POLYGON_MODE_POINT: polygon vertices are drawn as points

    Using any mode other than fill requires enabling a GPU feature.
    */

    rasterizer.polygonMode = VK_POLYGON_MODE_FILL;
    // The maximum line width that is supported depends on the hardware and any line thicker than 1.0f requires you to enable the wideLines GPU feature.
    rasterizer.lineWidth = 1.0f;

    rasterizer.cullMode = VK_CULL_MODE_BACK_BIT;
    rasterizer.frontFace = VK_FRONT_FACE_CLOCKWISE;

    rasterizer.depthBiasEnable = VK_FALSE;
    rasterizer.depthBiasConstantFactor = 0.0f; // Optional
    rasterizer.depthBiasClamp = 0.0f; // Optional
    rasterizer.depthBiasSlopeFactor = 0.0f; // Optional


    // Create multisampler - AntiAliasing

    // This renders to a higher resolution then downscales - less expensive
    VkPipelineMultisampleStateCreateInfo multisampling;
    multisampling.sType = VK_STRUCTURE_TYPE_PIPELINE_MULTISAMPLE_STATE_CREATE_INFO;
    multisampling.sampleShadingEnable = VK_FALSE;
    multisampling.rasterizationSamples = VK_SAMPLE_COUNT_1_BIT;
    multisampling.minSampleShading = 1.0f; // Optional
    multisampling.pSampleMask = VK_NULL_HANDLE; // Optional
    multisampling.alphaToCoverageEnable = VK_FALSE; // Optional
    multisampling.alphaToOneEnable = VK_FALSE; // Optional


    // Create color blend state - multiple choices here - see tutorial for other choices
    VkPipelineColorBlendAttachmentState colorBlendAttachment;
    colorBlendAttachment.colorWriteMask = VK_COLOR_COMPONENT_R_BIT | VK_COLOR_COMPONENT_G_BIT | VK_COLOR_COMPONENT_B_BIT | VK_COLOR_COMPONENT_A_BIT;
    colorBlendAttachment.blendEnable = VK_FALSE;
    colorBlendAttachment.srcColorBlendFactor = VK_BLEND_FACTOR_ONE; // Optional
    colorBlendAttachment.dstColorBlendFactor = VK_BLEND_FACTOR_ZERO; // Optional
    colorBlendAttachment.colorBlendOp = VK_BLEND_OP_ADD; // Optional
    colorBlendAttachment.srcAlphaBlendFactor = VK_BLEND_FACTOR_ONE; // Optional
    colorBlendAttachment.dstAlphaBlendFactor = VK_BLEND_FACTOR_ZERO; // Optional
    colorBlendAttachment.alphaBlendOp = VK_BLEND_OP_ADD; // Optional

    // Create color blending

    VkPipelineColorBlendStateCreateInfo colorBlending;
    colorBlending.sType = VK_STRUCTURE_TYPE_PIPELINE_COLOR_BLEND_STATE_CREATE_INFO;
    colorBlending.logicOpEnable = VK_FALSE;
    colorBlending.logicOp = VK_LOGIC_OP_COPY; // Optional
    colorBlending.attachmentCount = 1;
    colorBlending.pAttachments = &colorBlendAttachment;
    colorBlending.blendConstants[0] = 0.0f; // Optional
    colorBlending.blendConstants[1] = 0.0f; // Optional
    colorBlending.blendConstants[2] = 0.0f; // Optional
    colorBlending.blendConstants[3] = 0.0f; // Optional

    // Now we have the actual pipeline layout, create it

    VkPipelineLayoutCreateInfo pipelineLayoutInfo;
    pipelineLayoutInfo.sType = VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO;
    pipelineLayoutInfo.setLayoutCount = 0; // Optional
    pipelineLayoutInfo.pSetLayouts = VK_NULL_HANDLE; // Optional
    pipelineLayoutInfo.pushConstantRangeCount = 0; // Optional
    pipelineLayoutInfo.pPushConstantRanges = VK_NULL_HANDLE; // Optional

    if (vkCreatePipelineLayout(device, &pipelineLayoutInfo, VK_NULL_HANDLE, &pipelineLayout) != VK_SUCCESS) {
        throw new Exception("Vulkan: Failed to create pipeline layout!");
    }

    writeln("Vulkan: Succesfully created pipeline layout!");

    // Create pipeline info

    VkGraphicsPipelineCreateInfo pipelineInfo;
    pipelineInfo.sType = VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_CREATE_INFO;
    pipelineInfo.stageCount = 2;
    pipelineInfo.pStages = shaderStages.ptr;

    pipelineInfo.pVertexInputState = &vertexInputInfo;
    pipelineInfo.pInputAssemblyState = &inputAssembly;
    pipelineInfo.pViewportState = &viewportState;
    pipelineInfo.pRasterizationState = &rasterizer;
    pipelineInfo.pMultisampleState = &multisampling;
    pipelineInfo.pDepthStencilState = VK_NULL_HANDLE; // Optional
    pipelineInfo.pColorBlendState = &colorBlending;
    pipelineInfo.pDynamicState = &dynamicState;

    pipelineInfo.layout = pipelineLayout;

    pipelineInfo.renderPass = renderPass;
    pipelineInfo.subpass = 0;

    pipelineInfo.basePipelineHandle = VK_NULL_HANDLE; // Optional
    pipelineInfo.basePipelineIndex = -1; // Optional

    if (vkCreateGraphicsPipelines(device, VK_NULL_HANDLE, 1, &pipelineInfo, VK_NULL_HANDLE, &graphicsPipeline) != VK_SUCCESS) {
        throw new Exception("Vulkan: Failed to create graphics pipeline!");
    }

    writeln("Vulkan: Successfully created graphics pipeline!");


    vkDestroyShaderModule(device, fragShaderModule, VK_NULL_HANDLE);
    vkDestroyShaderModule(device, vertShaderModule, VK_NULL_HANDLE);

}




//!! ---------------- END GRAPHICS PIPELINE TOOLS -------------------



//** ----------------- BEGIN IMAGE VIEWS TOOLS -----------------

void createImageViews() {

    swapChainImageViews.length = swapChainImages.length;

    for (size_t i = 0; i < swapChainImages.length; i++) {
        VkImageViewCreateInfo createInfo;
        createInfo.sType = VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO;
        createInfo.image = swapChainImages[i];
        createInfo.viewType = VK_IMAGE_VIEW_TYPE_2D;
        createInfo.format = swapChainImageFormat;
        createInfo.components.r = VK_COMPONENT_SWIZZLE_IDENTITY;
        createInfo.components.g = VK_COMPONENT_SWIZZLE_IDENTITY;
        createInfo.components.b = VK_COMPONENT_SWIZZLE_IDENTITY;
        createInfo.components.a = VK_COMPONENT_SWIZZLE_IDENTITY;
        createInfo.subresourceRange.aspectMask = VK_IMAGE_ASPECT_COLOR_BIT;
        createInfo.subresourceRange.baseMipLevel = 0;
        createInfo.subresourceRange.levelCount = 1;
        createInfo.subresourceRange.baseArrayLayer = 0;
        createInfo.subresourceRange.layerCount = 1;

        if (vkCreateImageView(device, &createInfo, VK_NULL_HANDLE, &swapChainImageViews[i]) != VK_SUCCESS) {
            throw new Exception("Vulkan: Failed to create image views!");
        }
    }

    writeln("Vulkan: Successfully created image views!");
}


//!! -------------- END IMAGE VIEWS TOOLS ----------------------



//** --------------- BEGIN SWAP CHAIN TOOLS ---------------------


void createSwapChain() {
    SwapChainSupportDetails swapChainSupport = querySwapChainSupport(physicalDevice);

    VkSurfaceFormatKHR surfaceFormat = chooseSwapSurfaceFormat(swapChainSupport.formats);
    VkPresentModeKHR presentMode = chooseSwapPresentMode(swapChainSupport.presentModes);
    VkExtent2D extent = chooseSwapExtent(swapChainSupport.capabilities);

    uint32_t imageCount = swapChainSupport.capabilities.minImageCount + 1;

    if (swapChainSupport.capabilities.maxImageCount > 0 && imageCount > swapChainSupport.capabilities.maxImageCount) {
        imageCount = swapChainSupport.capabilities.maxImageCount;
    }

    VkSwapchainCreateInfoKHR createInfo;
    createInfo.sType = VK_STRUCTURE_TYPE_SWAPCHAIN_CREATE_INFO_KHR;
    createInfo.surface = surface;
    createInfo.minImageCount = imageCount;
    createInfo.imageFormat = surfaceFormat.format;
    createInfo.imageColorSpace = surfaceFormat.colorSpace;
    createInfo.imageExtent = extent;
    createInfo.imageArrayLayers = 1;
    createInfo.imageUsage = VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT;

    QueueFamilyIndices indices = findQueueFamilies(physicalDevice);
    uint[] queueFamilyIndices = [indices.graphicsFamily.get(), indices.presentFamily.get()];

    if (indices.graphicsFamily != indices.presentFamily) {
        createInfo.imageSharingMode = VK_SHARING_MODE_CONCURRENT;
        createInfo.queueFamilyIndexCount = 2;
        createInfo.pQueueFamilyIndices = queueFamilyIndices.ptr;
    } else {
        createInfo.imageSharingMode = VK_SHARING_MODE_EXCLUSIVE;
        // Optional
        createInfo.queueFamilyIndexCount = 0;
        // Optional
        createInfo.pQueueFamilyIndices = VK_NULL_HANDLE;
    }

    createInfo.preTransform = swapChainSupport.capabilities.currentTransform;
    createInfo.compositeAlpha = VK_COMPOSITE_ALPHA_OPAQUE_BIT_KHR;
    createInfo.presentMode = presentMode;
    createInfo.clipped = VK_TRUE;
    createInfo.oldSwapchain = VK_NULL_HANDLE;

    if (vkCreateSwapchainKHR(device, &createInfo, VK_NULL_HANDLE, &swapChain) != VK_SUCCESS) {
        throw new Exception("Vulkan: Failed to create swap chain!");
    }

    vkGetSwapchainImagesKHR(device, swapChain, &imageCount, VK_NULL_HANDLE);
    swapChainImages.length = imageCount;
    vkGetSwapchainImagesKHR(device, swapChain, &imageCount, swapChainImages.ptr);
    
    swapChainImageFormat = surfaceFormat.format;
    swapChainExtent = extent;

    writeln("Vulkan: Successfully created swap chain!");
}

SwapChainSupportDetails querySwapChainSupport(VkPhysicalDevice device) {


    SwapChainSupportDetails details;

    // Getting the supported formats
    vkGetPhysicalDeviceSurfaceCapabilitiesKHR(device, surface, &details.capabilities);
    uint formatCount = 0;
    vkGetPhysicalDeviceSurfaceFormatsKHR(device, surface, &formatCount, VK_NULL_HANDLE);

    if (formatCount != 0) {
        details.formats.length = formatCount;
        vkGetPhysicalDeviceSurfaceFormatsKHR(device, surface, &formatCount, details.formats.ptr);
    }

    // Getting the supported presentation modes
    uint presentModeCount = 0;
    vkGetPhysicalDeviceSurfacePresentModesKHR(device, surface, &presentModeCount, VK_NULL_HANDLE);

    if (presentModeCount != 0) {
        details.presentModes.length = presentModeCount;
        vkGetPhysicalDeviceSurfacePresentModesKHR(device, surface, &presentModeCount, details.presentModes.ptr);
    }

    return details;
}

VkSurfaceFormatKHR chooseSwapSurfaceFormat(VkSurfaceFormatKHR[] availableFormats) {

    // We're choosing 32 bit pixel color SRGB (8 bit R,G,B,A)
    foreach (VkSurfaceFormatKHR availableFormat; availableFormats) {
        if (availableFormat.format == VK_FORMAT_B8G8R8A8_SRGB && availableFormat.colorSpace == VK_COLOR_SPACE_SRGB_NONLINEAR_KHR) {
            return availableFormat;
        }
    }

    return availableFormats[0];
}

VkPresentModeKHR chooseSwapPresentMode(const VkPresentModeKHR[] availablePresentModes) {
    /**
    Here is what these modes mean:

    VK_PRESENT_MODE_IMMEDIATE_KHR    = vsync 0

    VK_PRESENT_MODE_FIFO_KHR         = vsync 1

    This one is probably the best for pc games
    VK_PRESENT_MODE_FIFO_RELAXED_KHR = Basically, decoupled vsync 0, don't wait

    VK_PRESENT_MODE_MAILBOX_KHR      = vsync 3 - Triple buffered
    */

    // Basically going to try to grab the decoupled mode so it's super nice
    foreach (VkPresentModeKHR availablePresentMode; availablePresentModes) {
        if (availablePresentMode == VK_PRESENT_MODE_MAILBOX_KHR) {
            return availablePresentMode;
        }
    }

    // Defaulting to regular vsync mode
    return VK_PRESENT_MODE_FIFO_KHR;
}

VkExtent2D chooseSwapExtent(VkSurfaceCapabilitiesKHR capabilities) {

    /**
    This is the resolution of swap chain images.

    It is almost always equal to the resolution of the window that we're drawing
    to in pixels.
    */

    if (capabilities.currentExtent.width != uint.max) {
        return capabilities.currentExtent;
    } else {

        int width, height;

        glfwGetFramebufferSize(window, &width, &height);

        VkExtent2D actualExtent = {
            width,
            height
        };

        actualExtent.width  = clamp(actualExtent.width, capabilities.minImageExtent.width, capabilities.maxImageExtent.width);
        actualExtent.height = clamp(actualExtent.height, capabilities.minImageExtent.height, capabilities.maxImageExtent.height);

        return actualExtent;
    }

}

//!! -------------- END SWAP CHAIN TOOLS -------------------------


//** ---------------- BEGIN SURFACE TOOLS ---------------------------


private void createSurface() {

    if (glfwCreateWindowSurface(instance, window, VK_NULL_HANDLE, &surface) != VK_SUCCESS) {
        throw new Exception("Vulkan: Failed to create window surface!");
    }
    writeln("Vulkan: Successfully created surface!");
}



//!! --------------- END SURFACE TOOLS --------------------------



//** ---------------------- BEGIN LOGICAL DEVICE -------------------


void createLogicalDevice() {

    
    QueueFamilyIndices indices = findQueueFamilies(physicalDevice);

    VkDeviceQueueCreateInfo[] queueCreateInfos;
    
    AAset!uint uniqueQueueFamilies;
    uniqueQueueFamilies.add(indices.graphicsFamily.get());
    uniqueQueueFamilies.add(indices.presentFamily.get());

    float queuePriority = 1.0f;

    // iterate the queues
    foreach (uint queueFamily; uniqueQueueFamilies) {

        VkDeviceQueueCreateInfo queueCreateInfo;
        queueCreateInfo.sType = VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO;
        queueCreateInfo.queueFamilyIndex = queueFamily;
        queueCreateInfo.queueCount = 1;
        queueCreateInfo.pQueuePriorities = &queuePriority;

        queueCreateInfos ~= queueCreateInfo;
    }

    // Create info queue
    VkDeviceQueueCreateInfo queueCreateInfo;
    queueCreateInfo.sType = VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO;
    queueCreateInfo.queueFamilyIndex = indices.graphicsFamily.get();
    queueCreateInfo.queueCount = 1;
    queueCreateInfo.pQueuePriorities = &queuePriority;

    // Create Info
    VkDeviceCreateInfo createInfo;
    createInfo.sType = VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO;
    createInfo.queueCreateInfoCount = cast(uint)queueCreateInfos.length;
    createInfo.pQueueCreateInfos = queueCreateInfos.ptr;
    
    createInfo.enabledExtensionCount = cast(uint)deviceExtensions.length;
    createInfo.ppEnabledExtensionNames = convertToCStringArray(deviceExtensions);

    // Physical device features
    VkPhysicalDeviceFeatures deviceFeatures;
    createInfo.pEnabledFeatures = &deviceFeatures;

    // Now enable debugging output
    if (enableValidationLayers) {
        createInfo.enabledLayerCount = cast(uint)validationLayers.length;
        createInfo.ppEnabledLayerNames = convertToCStringArray(validationLayers);
    } else {
        createInfo.enabledLayerCount = 0;
    }

    if (vkCreateDevice(physicalDevice, &createInfo, VK_NULL_HANDLE, &device) != VK_SUCCESS) {
        throw new Exception("Vulkan: Failed to create logical device!");
    }
    
    vkGetDeviceQueue(device, indices.presentFamily.get(), 0, &presentQueue);
}



//!! ------------------------- END LOGICAL DEVICE ----------------------



//** ------------ BEGIN PHYSICAL DEVICE ---------------------

void pickPhysicalDevice() {
    uint deviceCount = 0;
    
    vkEnumeratePhysicalDevices(instance, &deviceCount, VK_NULL_HANDLE);

    if (deviceCount == 0) {
        throw new Exception("Vulkan: Failed to find a GPU with Vulkan support!");
    }

    VkPhysicalDevice[] devices = new VkPhysicalDevice[deviceCount];
    vkEnumeratePhysicalDevices(instance, &deviceCount, devices.ptr);

    foreach (VkPhysicalDevice thisDevice; devices) {
        if (isDeviceSuitable(thisDevice)) {
            physicalDevice = thisDevice;
            break;
        }
    }

    if (physicalDevice == VK_NULL_HANDLE) {
        throw new Exception("Vulkan: Failed to find a suitable GPU!");
    }

}

bool isDeviceSuitable(VkPhysicalDevice device) {

    VkPhysicalDeviceProperties deviceProperties;
    vkGetPhysicalDeviceProperties(device, &deviceProperties);
    
    //! Can use this to check if a device has features
    // VkPhysicalDeviceFeatures deviceFeatures;
    // vkGetPhysicalDeviceFeatures(device, &deviceFeatures);

    // Check if there's a queue that supports graphics commands
    QueueFamilyIndices indices = findQueueFamilies(device);

    bool hasGraphicsCommands = indices.isComplete();

    bool hasExtensionSupport = checkDeviceExtensionSupport(device);

    bool swapChainAdequate = false;

    if (hasExtensionSupport) {
        SwapChainSupportDetails swapChainSupport = querySwapChainSupport(device);
        swapChainAdequate = !swapChainSupport.formats.empty() && !swapChainSupport.presentModes.empty();
    }

    bool fullSupport = hasGraphicsCommands && hasExtensionSupport && swapChainAdequate;

    if (fullSupport) {
        string gpuName = to!string(deviceProperties.deviceName);
        writeln("Vulkan: ", gpuName, " has graphics commands queue!");
        writeln("Vulkan: Selected GPU -> [ ", gpuName, " ]");
    }

    return fullSupport;
}

bool checkDeviceExtensionSupport(VkPhysicalDevice device) {

    // Basically, we're creating a dynamic array of all supported extensions for the current device (GPU)
    uint extensionCount;
    vkEnumerateDeviceExtensionProperties(device, VK_NULL_HANDLE, &extensionCount, VK_NULL_HANDLE);
    VkExtensionProperties[] availableExtensions = new VkExtensionProperties[extensionCount];
    vkEnumerateDeviceExtensionProperties(device, VK_NULL_HANDLE, &extensionCount, availableExtensions.ptr);

    // Creating a set from deviceExtensions like the C++ example
    AAset!string requiredExtensions;
    foreach (string key; deviceExtensions) {
        requiredExtensions.add(key);
    }

    /**
    So basically, we're making sure that all the extensions that we require
    from requiredExtensions are available in availableExtensions.

    This is why it's using a set!
    */
    foreach (VkExtensionProperties extension; availableExtensions) {
        string gottenExtensionName = split(to!string(extension.extensionName), "\0")[0];

        writeln("Vulkan Extension: ", gottenExtensionName);

        requiredExtensions.remove(gottenExtensionName);
    }

    // And if it's empty, we have everything we need!
    return requiredExtensions.empty();
}

QueueFamilyIndices findQueueFamilies(VkPhysicalDevice device) {

    QueueFamilyIndices indices;
    
    uint queueFamilyCount = 0;
    vkGetPhysicalDeviceQueueFamilyProperties(device, &queueFamilyCount, VK_NULL_HANDLE);
    VkQueueFamilyProperties[] queueFamilies = new VkQueueFamilyProperties[queueFamilyCount];
    vkGetPhysicalDeviceQueueFamilyProperties(device, &queueFamilyCount, queueFamilies.ptr);

    // Find a GPU that can intake graphics instructions
    foreach (size_t key, VkQueueFamilyProperties thisQueueFamily; queueFamilies) {
        uint i = cast(uint)key;

        // Enforce selection of GPU that can render to window surface
        VkBool32 presentSupport = false;
        vkGetPhysicalDeviceSurfaceSupportKHR(device, i, surface, &presentSupport);

        if (thisQueueFamily.queueFlags & VK_QUEUE_GRAPHICS_BIT && presentSupport == VK_TRUE) {
            indices.graphicsFamily = i;
            indices.presentFamily = i;
            break;
        }
    }

    return indices;
}

//!! ------------ END PHYSICAL DEVICE -----------------------------


//** ------------ BEGIN DEBUGGER ---------------------------------

void populateDebugMessengerCreateInfo(ref VkDebugUtilsMessengerCreateInfoEXT createInfo) {
    createInfo.sType = VK_STRUCTURE_TYPE_DEBUG_UTILS_MESSENGER_CREATE_INFO_EXT;
    createInfo.messageSeverity = VK_DEBUG_UTILS_MESSAGE_SEVERITY_VERBOSE_BIT_EXT | VK_DEBUG_UTILS_MESSAGE_SEVERITY_WARNING_BIT_EXT | VK_DEBUG_UTILS_MESSAGE_SEVERITY_ERROR_BIT_EXT;
    createInfo.messageType = VK_DEBUG_UTILS_MESSAGE_TYPE_GENERAL_BIT_EXT | VK_DEBUG_UTILS_MESSAGE_TYPE_VALIDATION_BIT_EXT | VK_DEBUG_UTILS_MESSAGE_TYPE_PERFORMANCE_BIT_EXT;
    createInfo.pfnUserCallback = cast(PFN_vkDebugUtilsMessengerCallbackEXT)&debugCallback;
}

void setupDebugMessenger() {
    if (!enableValidationLayers) {
        writeln("Vulkan: Debugger is disabled!");
    }
    writeln("Vulkan: Debugger is enabled!");
    
    VkDebugUtilsMessengerCreateInfoEXT createInfo;
    populateDebugMessengerCreateInfo(createInfo);
    createInfo.sType = VK_STRUCTURE_TYPE_DEBUG_UTILS_MESSENGER_CREATE_INFO_EXT;
    createInfo.messageSeverity = VK_DEBUG_UTILS_MESSAGE_SEVERITY_VERBOSE_BIT_EXT | VK_DEBUG_UTILS_MESSAGE_SEVERITY_WARNING_BIT_EXT | VK_DEBUG_UTILS_MESSAGE_SEVERITY_ERROR_BIT_EXT;
    createInfo.messageType = VK_DEBUG_UTILS_MESSAGE_TYPE_GENERAL_BIT_EXT | VK_DEBUG_UTILS_MESSAGE_TYPE_VALIDATION_BIT_EXT | VK_DEBUG_UTILS_MESSAGE_TYPE_PERFORMANCE_BIT_EXT;
    createInfo.pUserData = VK_NULL_HANDLE; // Optional

    // This is the only way I could find to shovel this into the callback
    createInfo.pfnUserCallback = cast(PFN_vkDebugUtilsMessengerCallbackEXT)&debugCallback;

    if (createDebugUtilsMessengerEXT(instance, &createInfo, VK_NULL_HANDLE, &debugMessenger) != VK_SUCCESS) {
        throw new Exception("Vulkan: Failed to set up debug messenger!");
    }
}

VkResult createDebugUtilsMessengerEXT(VkInstance instance, const VkDebugUtilsMessengerCreateInfoEXT* pCreateInfo, const VkAllocationCallbacks* pAllocator, VkDebugUtilsMessengerEXT* pDebugMessenger) {

    auto func = cast(PFN_vkCreateDebugUtilsMessengerEXT) vkGetInstanceProcAddr(instance, "vkCreateDebugUtilsMessengerEXT");
    if (func != VK_NULL_HANDLE) {
        return func(instance, pCreateInfo, pAllocator, pDebugMessenger);
    } else {
        return VK_ERROR_EXTENSION_NOT_PRESENT;
    }
}

void destroyDebugUtilsMessengerEXT(VkInstance instance, VkDebugUtilsMessengerEXT debugMessenger, const VkAllocationCallbacks* pAllocator) {
    auto func = cast(PFN_vkDestroyDebugUtilsMessengerEXT) vkGetInstanceProcAddr(instance, "vkDestroyDebugUtilsMessengerEXT");
    if (func != VK_NULL_HANDLE) {
        func(instance, debugMessenger, pAllocator);
    }
}

VkBool32 debugCallback(
    VkDebugUtilsMessageSeverityFlagBitsEXT messageSeverity,
    VkDebugUtilsMessageTypeFlagsEXT messageType,
    const VkDebugUtilsMessengerCallbackDataEXT* pCallbackData,
    void* pUserData
) {

    if (messageSeverity >= VK_DEBUG_UTILS_MESSAGE_SEVERITY_WARNING_BIT_EXT) {
        // Message is important enough to show
        writeln("Vulkan Validation Layer: ", to!string(pCallbackData.pMessage));
    }

    return VK_FALSE;
}

//!! --------------------- END DEBUGGER ----------------------------------------


//** --------------------- BEGIN EXTENSIONS & VALIDATION --------------------

string[] getRequiredExtensions() {

    // We're basically crawling through C pointers here to get usable strings

    uint glfwExtensionCount = 0;
    const(char)** glfwExtensions;
    glfwExtensions = glfwGetRequiredInstanceExtensions(&glfwExtensionCount);

    string[] extensions;

    // Decode and append them
    foreach (i; 0..glfwExtensionCount ) {
        const(char)* theArray = glfwExtensions[i];
        extensions ~= to!string(theArray);
    }

    // D auto converts this pointer mess into a string
    if (enableValidationLayers) {
        extensions ~= VK_EXT_DEBUG_UTILS_EXTENSION_NAME;
        writeln(extensions);
    }

    return extensions;
}

// We must convert this into a C style array array - Thanks for the help ADR!
const(char*)* convertToCStringArray(const string[] inputArray) {
    const(char)*[] array = [];
    foreach (string name; inputArray) {
        array ~= name.toStringz;
    }
    return array.ptr;
}

/// This is designed around safety, this will NOT let the program continue without validation
private void checkValidationLayerSupport() {

    // But we can turn it off if we'd like in a release build
    if (!enableValidationLayers) {
        writeln("Vulkan: Validation layers disabled!");
        return;
    }
    writeln("Vulkan: Validation layers enabled!");

    // Attempt to get validation layers
    uint layerCount = 0;
    vkEnumerateInstanceLayerProperties(&layerCount, VK_NULL_HANDLE);
    VkLayerProperties[] availableLayers = new VkLayerProperties[layerCount];
    vkEnumerateInstanceLayerProperties(&layerCount, cast(VkLayerProperties*)availableLayers.ptr);

    if (excessiveDebug) {
        writeln("============================\n" ~
                "VULKAN VALIDATION LAYERS:\n"~
                "============================"
        );
    }
    // Now let's see if it contains the one's we requested in validationLayers
    foreach (string layerName; validationLayers) {
        bool layerFound = false;
        
        foreach (VkLayerProperties layer; availableLayers) {

            string gottenLayerName = split(to!string(layer.layerName), "\0")[0];

            // Yeah that looks like what we want, noice
            if (gottenLayerName == layerName) {
                layerFound = true;
                break;
            }
        }

        if (!layerFound) {

            /**
            Important note on how this differs from the reference:

            In C code it was just blindly telling you that there was one validation missing.

            In this D code we want to know WHICH validation layer is missing!
            */

            throw new Exception(
                "Vulkan: Validation Layer " ~ layerName ~ " was requested but not available!\n" ~
                "Is the Vulkan SDK installed? You can get it here: https://vulkan.lunarg.com/"
            );
        } else {
            if (excessiveDebug) {
                writeln(layerName);
            }
        }
    }
    writeln("Vulkan: Requested Vulkan validation layers are all available!");
}

//!! ------------------------- END EXTENSIONS & VALIDATION ---------------------------------

//** ----------------------- BEGIN INSTANCE TOOLS ------------------------------------


void createVulkanInstance() {
    // App information
    VkApplicationInfo appInfo;
    appInfo.sType = VK_STRUCTURE_TYPE_APPLICATION_INFO;
    appInfo.pApplicationName = "Hello Vulkan";
    appInfo.pEngineName = "No Engine";

    appInfo.applicationVersion = VK_MAKE_API_VERSION(0, 1, 0, 0);
    appInfo.engineVersion      = VK_MAKE_API_VERSION(0, 1, 0, 0);
    
    /**
    This will throw errors if you replace this with:

    VK_API_VERSION_1_0 OR VK_MAKE_API_VERSION( 0, 1, 0, 0 )

    I do not think 1_0 is importing all required things for some reason
    */
    appInfo.apiVersion         = VK_MAKE_API_VERSION(0, 1, 1, 0);

    // Instance creation info
    VkInstanceCreateInfo createInfo;
    createInfo.sType = VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO;
    createInfo.pApplicationInfo = &appInfo;

    // Get all extensions
    string[] extensions = getRequiredExtensions();

    createInfo.enabledExtensionCount = cast(int)extensions.length;
    createInfo.ppEnabledExtensionNames = convertToCStringArray(extensions);

    checkValidationLayerSupport();

    // Now make those validation layers available, or don't
    // Add in debug info as well
    VkDebugUtilsMessengerCreateInfoEXT debugCreateInfo;
    if (enableValidationLayers) {
        createInfo.enabledLayerCount = cast(uint)validationLayers.length;
        createInfo.ppEnabledLayerNames = convertToCStringArray(validationLayers);

        populateDebugMessengerCreateInfo(debugCreateInfo);
        createInfo.pNext = cast(VkDebugUtilsMessengerCreateInfoEXT*) &debugCreateInfo;
    } else {
        createInfo.enabledLayerCount = 0;
        createInfo.pNext = VK_NULL_HANDLE;
    }

    // Make an instance of Vulkan in program
    if (vkCreateInstance(&createInfo, VK_NULL_HANDLE, &instance) != VK_SUCCESS) {
        throw new Exception("Vulkan: Failed to create instance!");
    }

    // We can now load up instance level functions
    loadInstanceLevelFunctions(instance);

    // Check for extension support
    uint extensionCount = 0;
    vkEnumerateInstanceExtensionProperties(VK_NULL_HANDLE, &extensionCount, VK_NULL_HANDLE);

    VkExtensionProperties[] vulkanExtensions = new VkExtensionProperties[extensionCount];
    vkEnumerateInstanceExtensionProperties(VK_NULL_HANDLE, &extensionCount, cast(VkExtensionProperties*)vulkanExtensions.ptr);

    // Output available extensions into the terminal
    if (excessiveDebug) {
        writeln("==================================\n" ~
                "VULKAN AVAILABLE EXTENSIONS:\n" ~
                "==================================");
        foreach (VkExtensionProperties thisExtension; vulkanExtensions) {
            writeln(split(to!string(thisExtension.extensionName), "\0")[0]);
        }
    }
}




//!! ---------------------- END INSTANCE TOOLS --------------------------------------


//! =================================================== END VULKAN TOOLS ==========================================


//* ======== GLFW Tools ========

void destroy() {

    vkDestroyPipeline(device, graphicsPipeline, VK_NULL_HANDLE);
    vkDestroyPipelineLayout(device, pipelineLayout, VK_NULL_HANDLE);
    vkDestroyRenderPass(device, renderPass, VK_NULL_HANDLE);

    foreach (VkImageView imageView; swapChainImageViews) {
        vkDestroyImageView(device, imageView, VK_NULL_HANDLE);
    }
    vkDestroySwapchainKHR(device, swapChain, VK_NULL_HANDLE);
    if (enableValidationLayers) {
        destroyDebugUtilsMessengerEXT(instance, debugMessenger, VK_NULL_HANDLE);
        writeln("Vulkan: Destroyed debugger!");
    }
    vkDestroySurfaceKHR(instance, surface, null);
    vkDestroyDevice(device, VK_NULL_HANDLE);
    vkDestroyInstance(instance, VK_NULL_HANDLE);
    writeln("Vulkan: Instance destroyed successfully!");
    glfwDestroyWindow(window);
    glfwTerminate();
    writeln("GLFW 3.3 destroyed successfully!");
}

// Returns success state 
private bool initializeGLFWComponents() {

    GLFWSupport returnedError;
    
    version(Windows) {
        returnedError = loadGLFW("libs/glfw3.dll");
    } else {
        // Linux,FreeBSD, OpenBSD, Mac OS, haiku, etc
        returnedError = loadGLFW();
    }

    // loadGLFW_Vulkan();

    if(returnedError != glfwSupport) {
        writeln("ERROR IN GLFW!");
        writeln("---------- DIRECT DEBUG ERROR ---------------");
        // Log the direct error info
        // foreach(info; loader.errors) {
        //     logCError(info.error, info.message);
        // }
        writeln("---------------------------------------------");
        writeln("------------ FUZZY SUGGESTION ---------------");
        // Log fuzzy error info with suggestion
        if(returnedError == GLFWSupport.noLibrary) {
            writeln("The GLFW shared library failed to load!\n",
            "Is GLFW installed correctly?\n\n",
            "ABORTING!");
        }
        else if(GLFWSupport.badLibrary) {
            writeln("One or more symbols failed to load.\n",
            "The likely cause is that the shared library is for a lower\n",
            "version than bindbc-glfw was configured to load (via GLFW_31, GLFW_32 etc.\n\n",
            "ABORTING!");
        }
        writeln("-------------------------");
        return false;
    }

    return true;
}



// Window talks directly to GLFW
private bool initializeGLFW(int windowSizeX = -1, int windowSizeY = -1) {

    // Something fails to load
    if (!initializeGLFWComponents()) {
        return false;
    }

    // Something scary fails to load
    if (!glfwInit()) {
        return false;
    }

    glfwWindowHint(GLFW_CLIENT_API, GLFW_NO_API);
    glfwWindowHint(GLFW_RESIZABLE, GLFW_FALSE);

    // Create a window on the primary monitor
    window = glfwCreateWindow(800, 600, "This is the window title", null, null);

    // Something even scarier fails to load
    if (!window || window == null) {
        writeln("WINDOW FAILED TO OPEN!\n",
        "ABORTING!");
        glfwTerminate();
        return false;
    }

    // In the future, get array of monitor pointers with: GLFWmonitor** monitors = glfwGetMonitors(&count);
    // monitor = glfwGetPrimaryMonitor();

    glfwSetKeyCallback(window, &key_callback);
  

    // No error :)
    return true;
}




bool shouldClose() {
    return (glfwWindowShouldClose(window) != 0);
}

void swapBuffers() {
    glfwSwapBuffers(window);
}

Vector2i getSize() {
    return windowSize;
}

double getAspectRatio() {
    return cast(double)windowSize.x / cast(double)windowSize.y;
}

void pollEvents() {
    glfwPollEvents();
    calculateDelta();
    // This causes an issue with low FPS getting the wrong FPS
    // Perhaps make an internal engine ticker that is created as an object or struct
    // Store it on heap, then calculate from there, specific to this
    deltaAccumulator += getDelta();
    fpsCounter += 1;
    // Got a full second, reset counter, set variable
    if (deltaAccumulator >= 1) {
        deltaAccumulator = 0.0;
        FPS = fpsCounter;
        fpsCounter = 0;
    }
}

int getFPS() {
    return FPS;
}

/// Setting storage to false allows you to chain data into a base window title
void setTitle(string newTitle, bool storeNewTitle = true) {
    if (storeNewTitle) {
        title = newTitle;
    }
    glfwSetWindowTitle(window, newTitle.toStringz);
}

string getTitle() {
    return title;
}

nothrow
void close() {
    glfwSetWindowShouldClose(window, true);
}

bool isFullScreen() {
    return fullscreen;
}


// This is a little baby function to allow me to quickly hit escape while rapidly debugging
nothrow static extern (C)
void key_callback(GLFWwindow* window, int key, int scancode, int action, int mods) {
    if (key == GLFW_KEY_ESC) {
        close();
    }

    // if (key == GLFW_KEY_E && action == GLFW_PRESS)
}
bool getKeyPressed(uint input) {
    return true;
}


//! ====== End GLFW Tools ======

double getWidth() {
    return windowSize.x;
}
double getHeight() {
    return windowSize.y;
}

//! ===== End OpenGL Tools =====


// This is a simple tool by ADR to tell if the platform is posix.
bool isPosix() {
    version(Posix) return true;
    else return false;
}