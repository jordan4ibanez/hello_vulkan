module vulkan.vulkan;

// Window acts as a static class
import Window = window.window;

import std.stdio;
import std.conv;
import std.string;
import std.array;
import std.typecons;
import std.algorithm.comparison: clamp;
import std.process: execute;
import std.file;


import aaset;

import erupted;
import erupted.types;
import erupted.vulkan_lib_loader;
import erupted.platform_extensions;
import bindbc.glfw;

mixin(bindGLFW_Vulkan);

// Vulkan fields

private immutable int MAX_FRAMES_IN_FLIGHT = 2;

private uint currentFrame = 0;

private VkInstance instance;
private VkDebugUtilsMessengerEXT debugMessenger;
private VkPhysicalDevice physicalDevice = VK_NULL_HANDLE;
private VkDevice device;
private VkQueue graphicsQueue;
private VkSurfaceKHR surface;
private VkQueue presentQueue;
private VkSwapchainKHR swapChain;
private VkImage[] swapChainImages;
private VkFormat swapChainImageFormat;
private VkExtent2D swapChainExtent;
private VkImageView[] swapChainImageViews;
private VkRenderPass renderPass;
private VkPipelineLayout pipelineLayout;
private VkPipeline graphicsPipeline;
private VkFramebuffer[] swapChainFramebuffers;
private VkCommandPool commandPool;
private VkCommandBuffer[] commandBuffers;
//! Note: Semaphore is a fancy word for signal aka a flag
private VkSemaphore[] imageAvailableSemaphores;
private VkSemaphore[] renderFinishedSemaphores;
private VkFence[] inFlightFences;

// For Vulkan debugging
private bool enableValidationLayers  = true;
// For EXCESSIVE debugging
private bool excessiveDebug = false;

private const string[] validationLayers = [
    "VK_LAYER_KHRONOS_validation"
];

private const string[] deviceExtensions = [
    VK_KHR_SWAPCHAIN_EXTENSION_NAME
];



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

private struct SwapChainSupportDetails {
    VkSurfaceCapabilitiesKHR capabilities;
    VkSurfaceFormatKHR[] formats;
    VkPresentModeKHR[] presentModes;
}

//!! -------------- END VULKAN STRUCTS -------

//** ---------------- BEGIN VULKAN INIT --------------------------------------------

void initialize() {

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

    loadDeviceLevelFunctions(device);

    createSwapChain();

    createImageViews();

    createRenderPass();

    // This literally just runs an executable to turn glsl into spir-v
    executeHackJobShaderCompile();

    createGraphicsPipeline();

    createFramebuffers();

    createCommandPool();

    createCommandBuffers();

    createSyncObjects();
}

//!! ---------------- END VULKAN INIT -------------------------------

//** ---------------- BEGIN DRAW TOOLS ---------------------------

//! This is a specific debug tool for checking different portions of the code
private bool f() {
    writeln("freeze!");
    return true;
}

void drawFrame() {
    
    

    vkWaitForFences(device, 1, &inFlightFences[currentFrame], VK_TRUE, ulong.max);
    vkResetFences(device, 1, &inFlightFences[currentFrame]);

    uint imageIndex;
    vkAcquireNextImageKHR(device, swapChain, ulong.max, imageAvailableSemaphores[currentFrame], VK_NULL_HANDLE, &imageIndex);

    vkResetCommandBuffer(commandBuffers[currentFrame], 0);

    recordCommandBuffer(commandBuffers[currentFrame], imageIndex);

    VkSubmitInfo submitInfo;
    submitInfo.sType = VK_STRUCTURE_TYPE_SUBMIT_INFO;

    VkSemaphore[] waitSemaphores = [imageAvailableSemaphores[currentFrame]];

    VkPipelineStageFlags[] waitStages = [VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT];

    submitInfo.waitSemaphoreCount = 1;
    submitInfo.pWaitSemaphores = waitSemaphores.ptr;
    submitInfo.pWaitDstStageMask = waitStages.ptr;
    submitInfo.commandBufferCount = 1;
    submitInfo.pCommandBuffers = &commandBuffers[currentFrame];

    VkSemaphore[] signalSemaphores = [renderFinishedSemaphores[currentFrame]];

    submitInfo.signalSemaphoreCount = 1;
    submitInfo.pSignalSemaphores = signalSemaphores.ptr;

    if (vkQueueSubmit(graphicsQueue, 1, &submitInfo, inFlightFences[currentFrame]) != VK_SUCCESS) {
        throw new Exception("Vulkan: Failed to submit draw command buffer!");
    }

    VkSubpassDependency dependency;
    dependency.srcSubpass = VK_SUBPASS_EXTERNAL;
    dependency.dstSubpass = 0;

    dependency.srcStageMask = VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT;
    dependency.srcAccessMask = 0;

    dependency.dstStageMask = VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT;
    dependency.dstAccessMask = VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT;

    // renderPassInfo.dependencyCount = 1;
    // renderPassInfo.pDependencies = &dependency;

    VkPresentInfoKHR presentInfo;
    presentInfo.sType = VK_STRUCTURE_TYPE_PRESENT_INFO_KHR;

    presentInfo.waitSemaphoreCount = 1;
    presentInfo.pWaitSemaphores = signalSemaphores.ptr;

    VkSwapchainKHR[] swapChains = [swapChain];
    presentInfo.swapchainCount = 1;
    presentInfo.pSwapchains = swapChains.ptr;
    presentInfo.pImageIndices = &imageIndex;
    presentInfo.pResults = VK_NULL_HANDLE; // Optional

    vkQueuePresentKHR(presentQueue, &presentInfo);

    writeln("Vulkan: Rendered into buffer ", currentFrame);

    currentFrame = (currentFrame + 1) % MAX_FRAMES_IN_FLIGHT;
}


//!! ---------------- END DRAW TOOLS -----------------------------

//** ---------------- BEGIN SYNC TOOLS --------------------------

private void createSyncObjects() {

    imageAvailableSemaphores.length = MAX_FRAMES_IN_FLIGHT;
    renderFinishedSemaphores.length = MAX_FRAMES_IN_FLIGHT;
    inFlightFences.length           = MAX_FRAMES_IN_FLIGHT;

    VkSemaphoreCreateInfo semaphoreInfo;
    semaphoreInfo.sType = VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO;

    VkFenceCreateInfo fenceInfo;
    fenceInfo.sType = VK_STRUCTURE_TYPE_FENCE_CREATE_INFO;
    fenceInfo.flags = VK_FENCE_CREATE_SIGNALED_BIT;

    foreach (i; 0..MAX_FRAMES_IN_FLIGHT) {
        if (vkCreateSemaphore(device, &semaphoreInfo, VK_NULL_HANDLE, &imageAvailableSemaphores[i]) != VK_SUCCESS ||
            vkCreateSemaphore(device, &semaphoreInfo, VK_NULL_HANDLE, &renderFinishedSemaphores[i]) != VK_SUCCESS ||
            vkCreateFence(device, &fenceInfo, VK_NULL_HANDLE, &inFlightFences[i]) != VK_SUCCESS) {
            throw new Exception("Vulkan: Failed to create semaphores!");
        }
    }

    writeln("Vulkan: Successfully created semaphores!");

}


//!! ------------------ END SYNC TOOLS --------------------------

//** ---------------- BEGIN COMMAND TOOLS -----------------------


private void recordCommandBuffer(VkCommandBuffer commandBuffer, uint32_t imageIndex) {
    /**

    Notes on the flags parameter:

    VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT: The command buffer will be rerecorded right after executing it once.
    VK_COMMAND_BUFFER_USAGE_RENDER_PASS_CONTINUE_BIT: This is a secondary command buffer that will be entirely within a single render pass.
    VK_COMMAND_BUFFER_USAGE_SIMULTANEOUS_USE_BIT: The command buffer can be resubmitted while it is also already pending execution.

    */
    VkCommandBufferBeginInfo beginInfo;

    beginInfo.sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO;
    beginInfo.flags = VK_COMMAND_BUFFER_USAGE_SIMULTANEOUS_USE_BIT;

    // beginInfo.sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO;
    // beginInfo.flags = 0; // Optional
    beginInfo.pInheritanceInfo = VK_NULL_HANDLE; // Optional

    if (vkBeginCommandBuffer(commandBuffer, &beginInfo) != VK_SUCCESS) {
        throw new Exception("Vulkan: Failed to begin recording command buffer!");
    }

    // Begin render pass

    VkRenderPassBeginInfo renderPassInfo;
    renderPassInfo.sType = VK_STRUCTURE_TYPE_RENDER_PASS_BEGIN_INFO;
    renderPassInfo.renderPass = renderPass;
    renderPassInfo.framebuffer = swapChainFramebuffers[imageIndex];

    renderPassInfo.renderArea.offset = VkOffset2D(0, 0);
    renderPassInfo.renderArea.extent = swapChainExtent;

    // Clear color :)
    
    VkClearValue clearColor;
    clearColor.color = VkClearColorValue([0,0,0,1]);
    renderPassInfo.clearValueCount = 1;
    renderPassInfo.pClearValues = &clearColor;
    
    /**

    Note for third parameter:

    VK_SUBPASS_CONTENTS_INLINE: The render pass commands will be embedded in the primary command buffer itself and no secondary command buffers will be executed.
    VK_SUBPASS_CONTENTS_SECONDARY_COMMAND_BUFFERS: The render pass commands will be executed from secondary command buffers.

    */

    vkCmdBeginRenderPass(commandBuffer, &renderPassInfo, VK_SUBPASS_CONTENTS_INLINE);

    vkCmdBindPipeline(commandBuffer, VK_PIPELINE_BIND_POINT_GRAPHICS, graphicsPipeline);

    VkViewport viewport;
    viewport.x = 0.0f;
    viewport.y = 0.0f;
    viewport.width = cast(float)swapChainExtent.width;
    viewport.height = cast(float)swapChainExtent.height;
    viewport.minDepth = 0.0f;
    viewport.maxDepth = 1.0f;
    vkCmdSetViewport(commandBuffer, 0, 1, &viewport);

    VkRect2D scissor;
    scissor.offset = VkOffset2D(0, 0);
    scissor.extent = swapChainExtent;
    vkCmdSetScissor(commandBuffer, 0, 1, &scissor);

    /**
    Notes for this function:

    vertexCount: Even though we don't have a vertex buffer, we technically still have 3 vertices to draw.
    instanceCount: Used for instanced rendering, use 1 if you're not doing that.
    firstVertex: Used as an offset into the vertex buffer, defines the lowest value of gl_VertexIndex.
    firstInstance: Used as an offset for instanced rendering, defines the lowest value of gl_InstanceIndex.


    //! Temporarily changed to 9 :)

    */
    vkCmdDraw(commandBuffer, 9, 1, 0, 0);

    vkCmdEndRenderPass(commandBuffer);

    if (vkEndCommandBuffer(commandBuffer) != VK_SUCCESS) {
        throw new Exception("Vulkan: Failed to record command buffer!");
    }

    // writeln("Successfully recorded command buffer!");

}


private void createCommandBuffers() {

    commandBuffers.length = MAX_FRAMES_IN_FLIGHT;

    /**

    Notes for the level parameter:

    VK_COMMAND_BUFFER_LEVEL_PRIMARY: Can be submitted to a queue for execution, but cannot be called from other command buffers.
    VK_COMMAND_BUFFER_LEVEL_SECONDARY: Cannot be submitted directly, but can be called from primary command buffers.

    */

    VkCommandBufferAllocateInfo allocInfo;
    allocInfo.sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO;
    allocInfo.commandPool = commandPool;
    allocInfo.level = VK_COMMAND_BUFFER_LEVEL_PRIMARY;
    allocInfo.commandBufferCount = cast(uint)commandBuffers.length;

    if (vkAllocateCommandBuffers(device, &allocInfo, commandBuffers.ptr) != VK_SUCCESS) {
        throw new Exception("Vulkan: Failed to allocate command buffers!");
    }

    writeln("Vulkan: Successfully allocated command buffers!");

}


private void createCommandPool() {

    QueueFamilyIndices queueFamilyIndices = findQueueFamilies(physicalDevice);

    /**

    Note for command pool flags:

    VK_COMMAND_POOL_CREATE_TRANSIENT_BIT: Hint that command buffers are rerecorded with new commands very often (may change memory allocation behavior)
    VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT: Allow command buffers to be rerecorded individually, without this flag they all have to be reset together

    */

    VkCommandPoolCreateInfo poolInfo;
    poolInfo.sType = VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO;
    poolInfo.flags = VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT;
    poolInfo.queueFamilyIndex = queueFamilyIndices.graphicsFamily.get();

    if (vkCreateCommandPool(device, &poolInfo, VK_NULL_HANDLE, &commandPool) != VK_SUCCESS) {
        throw new Exception("Vulkan: Failed to create command pool!");
    }

    writeln("Vulkan: Successfully created command pool!");


}

//!! --------------- END COMMAND POOL TOOLS -----------------------

//** ----------------- BEGIN FRAMEBUFFER TOOLS --------------------


private void createFramebuffers() {

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

private void createRenderPass() {

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
private void executeHackJobShaderCompile() {

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

private VkShaderModule createShaderModule(char[] code) {
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


private char[] readFile(string fileLocation) {

    if (!exists(fileLocation)) {
        throw new Exception("Vulkan: File " ~ fileLocation ~ " does not exist!");
    }

    return cast(char[])read(fileLocation);
}


//!! --------------- END SHADER TOOLS ----------------------------


//** ----------------- BEGIN GRAPHICS PIPELINE TOOLS ------------------

private void createGraphicsPipeline() {
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

private void createImageViews() {

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


private void createSwapChain() {
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

private SwapChainSupportDetails querySwapChainSupport(VkPhysicalDevice device) {


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

private VkSurfaceFormatKHR chooseSwapSurfaceFormat(VkSurfaceFormatKHR[] availableFormats) {

    // We're choosing 32 bit pixel color SRGB (8 bit R,G,B,A)
    foreach (VkSurfaceFormatKHR availableFormat; availableFormats) {
        if (availableFormat.format == VK_FORMAT_B8G8R8A8_SRGB && availableFormat.colorSpace == VK_COLOR_SPACE_SRGB_NONLINEAR_KHR) {
            return availableFormat;
        }
    }

    return availableFormats[0];
}

private VkPresentModeKHR chooseSwapPresentMode(const VkPresentModeKHR[] availablePresentModes) {

    writeln(availablePresentModes);
    /**
    Here is what these modes mean:
    
    // 1 and 0 are on and off

    VK_PRESENT_MODE_IMMEDIATE_KHR    = vsync 0

    VK_PRESENT_MODE_FIFO_KHR         = vsync 1

    This one is probably the best for pc games
    This also makes it so your engine FPS calculation is INACCURATE to the rendered FPS
    Your engine can keep working while your window tries to vsync
    VK_PRESENT_MODE_FIFO_RELAXED_KHR = decoupled vsync 0, don't wait

    // This one doesn't work right on Linux
    // This also doesn't work right for nvidia on linux
    // This also is affected by the driver so it might not work right in either linux or windows
    // I wouldn't use this
    VK_PRESENT_MODE_MAILBOX_KHR      = vsync 3 - Triple buffered
    */


    // We're just going to prefer Vsync mode, it's simple
    VkPresentModeKHR prefered = VK_PRESENT_MODE_FIFO_RELAXED_KHR;

    // Basically going to try to grab the decoupled mode so it's super nice
    foreach (VkPresentModeKHR availablePresentMode; availablePresentModes) {
        if (availablePresentMode == prefered) {
            return availablePresentMode;
        }
    }

    // Defaulting to regular vsync mode
    return VK_PRESENT_MODE_FIFO_KHR;
}

private VkExtent2D chooseSwapExtent(VkSurfaceCapabilitiesKHR capabilities) {

    /**
    This is the resolution of swap chain images.

    It is almost always equal to the resolution of the window that we're drawing
    to in pixels.
    */

    if (capabilities.currentExtent.width != uint.max) {
        return capabilities.currentExtent;
    } else {

        int width, height;

        glfwGetFramebufferSize(Window.getWindowInstance(), &width, &height);

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

    if (glfwCreateWindowSurface(instance, Window.getWindowInstance(), VK_NULL_HANDLE, &surface) != VK_SUCCESS) {
        throw new Exception("Vulkan: Failed to create window surface!");
    }
    writeln("Vulkan: Successfully created surface!");
}



//!! --------------- END SURFACE TOOLS --------------------------



//** ---------------------- BEGIN LOGICAL DEVICE -------------------


private void createLogicalDevice() {

    
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

    vkGetDeviceQueue(device, indices.graphicsFamily.get(), 0, &graphicsQueue);
}



//!! ------------------------- END LOGICAL DEVICE ----------------------



//** ------------ BEGIN PHYSICAL DEVICE ---------------------

private void pickPhysicalDevice() {
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

private bool isDeviceSuitable(VkPhysicalDevice device) {

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

private bool checkDeviceExtensionSupport(VkPhysicalDevice device) {

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

private QueueFamilyIndices findQueueFamilies(VkPhysicalDevice device) {

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

private void populateDebugMessengerCreateInfo(ref VkDebugUtilsMessengerCreateInfoEXT createInfo) {
    createInfo.sType = VK_STRUCTURE_TYPE_DEBUG_UTILS_MESSENGER_CREATE_INFO_EXT;
    createInfo.messageSeverity = VK_DEBUG_UTILS_MESSAGE_SEVERITY_VERBOSE_BIT_EXT | VK_DEBUG_UTILS_MESSAGE_SEVERITY_WARNING_BIT_EXT | VK_DEBUG_UTILS_MESSAGE_SEVERITY_ERROR_BIT_EXT;
    createInfo.messageType = VK_DEBUG_UTILS_MESSAGE_TYPE_GENERAL_BIT_EXT | VK_DEBUG_UTILS_MESSAGE_TYPE_VALIDATION_BIT_EXT | VK_DEBUG_UTILS_MESSAGE_TYPE_PERFORMANCE_BIT_EXT;
    createInfo.pfnUserCallback = cast(PFN_vkDebugUtilsMessengerCallbackEXT)&debugCallback;
}

private void setupDebugMessenger() {
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

private VkResult createDebugUtilsMessengerEXT(VkInstance instance, const VkDebugUtilsMessengerCreateInfoEXT* pCreateInfo, const VkAllocationCallbacks* pAllocator, VkDebugUtilsMessengerEXT* pDebugMessenger) {

    auto func = cast(PFN_vkCreateDebugUtilsMessengerEXT) vkGetInstanceProcAddr(instance, "vkCreateDebugUtilsMessengerEXT");
    if (func != VK_NULL_HANDLE) {
        return func(instance, pCreateInfo, pAllocator, pDebugMessenger);
    } else {
        return VK_ERROR_EXTENSION_NOT_PRESENT;
    }
}

private void destroyDebugUtilsMessengerEXT(VkInstance instance, VkDebugUtilsMessengerEXT debugMessenger, const VkAllocationCallbacks* pAllocator) {
    auto func = cast(PFN_vkDestroyDebugUtilsMessengerEXT) vkGetInstanceProcAddr(instance, "vkDestroyDebugUtilsMessengerEXT");
    if (func != VK_NULL_HANDLE) {
        func(instance, debugMessenger, pAllocator);
    }
}

private VkBool32 debugCallback(
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

private string[] getRequiredExtensions() {

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
private const(char*)* convertToCStringArray(const string[] inputArray) {
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


private void createVulkanInstance() {
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



void destroy() {
    foreach (i; 0..MAX_FRAMES_IN_FLIGHT) {
        vkDestroySemaphore(device, imageAvailableSemaphores[i], VK_NULL_HANDLE);
        vkDestroySemaphore(device, renderFinishedSemaphores[i], VK_NULL_HANDLE);
        vkDestroyFence(device, inFlightFences[i], VK_NULL_HANDLE);
    }

    vkDestroyCommandPool(device, commandPool, VK_NULL_HANDLE);

    foreach (VkFramebuffer framebuffer; swapChainFramebuffers) {
        vkDestroyFramebuffer(device, framebuffer, VK_NULL_HANDLE);
    }

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
}