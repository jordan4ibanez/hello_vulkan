module window.window;

import std.stdio;
import std.conv;
import std.string;
import std.array;
import doml.vector_2i;
import doml.vector_2d;
import doml.vector_3d;
import delta_time;
import erupted;
import erupted.vulkan_lib_loader;

// This is a special import. We only want to extract the loader from this module.
import loader = bindbc.loader.sharedlib;
import bindbc.glfw;

private Vector3d clearColor;

// GLFW fields
private string title;
private Vector2i windowSize;

private  GLFWwindow* window = null;
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
mixin(bindGLFW_Vulkan);
private VkInstance instance;
VkDebugUtilsMessengerEXT debugMessenger;
VkPhysicalDevice physicalDevice = VK_NULL_HANDLE;

//! I wrote it how the C++ tutorial runs but we want this to ALWAYS check
// debug {
    private bool enableValidationLayers  = true;
// } else {
    // private bool enableValidationLayers  = false;
// }

const string[] validationLayers = [
    "VK_LAYER_KHRONOS_validation"
];

// Just the initializer for the module
void initialize() {
    if (!initializeGLFW()) {
        throw new Exception("GLFW failed");
    }
    initializeVulkan();
}

//* =================================================== VULKAN TOOLS ========================================

private void initializeVulkan() {

    // Attempt to load the BindBC Vulkan library
    if (!loadGLFW_Vulkan()) {
        throw new Exception("Vulkan: Failed to load BindBC Vulkan library!");
    }

    // Attempt to load up Erupted global level functions
    if (!loadGlobalLevelFunctions()) {
        throw new Exception("Vulkan: Failed to load Erupted global level functions!");
    }

    // App information
    VkApplicationInfo appInfo;
    appInfo.sType = VK_STRUCTURE_TYPE_APPLICATION_INFO;
    appInfo.pApplicationName = "Hello dere";
    appInfo.applicationVersion = VK_MAKE_API_VERSION(0, 1, 0, 0);
    appInfo.pEngineName = "No Engine";
    appInfo.engineVersion = VK_MAKE_API_VERSION(0, 1, 0, 0);
    appInfo.apiVersion = VK_API_VERSION_1_0;

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
    if (false) {
        writeln("VULKAN AVAILABLE EXTENSIONS:" ~
                "==================================");
        foreach (VkExtensionProperties thisExtension; vulkanExtensions) {
            writeln(split(to!string(thisExtension.extensionName), "\0")[0]);
        }
    }

    setupDebugMessenger();

    pickPhysicalDevice();
}

void pickPhysicalDevice() {
    uint deviceCount = 0;
    
    vkEnumeratePhysicalDevices(instance, &deviceCount, VK_NULL_HANDLE);

    if (deviceCount == 0) {
        throw new Exception("Vulkan: Failed to find a GPU with Vulkan support!");
    }

    VkPhysicalDevice[] devices = new VkPhysicalDevice[deviceCount];
    // vkEnumeratePhysicalDevices(instance, &deviceCount, &devices);


}

bool isDeviceSuitable(VkPhysicalDevice device) {
    return true;
}

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
    vkEnumerateInstanceLayerProperties(&layerCount, cast(VkLayerProperties*)&availableLayers[0]);

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
        }
    }
    writeln("Vulkan: Requested Vulkan validation layers are all available!");
}

void destroy() {
    if (enableValidationLayers) {
        destroyDebugUtilsMessengerEXT(instance, debugMessenger, VK_NULL_HANDLE);
        writeln("Vulkan: Destroyed debugger!");
    }
    vkDestroyInstance(instance, VK_NULL_HANDLE);
    writeln("Vulkan: Instance destroyed successfully!");
    glfwDestroyWindow(window);
    glfwTerminate();
    writeln("GLFW 3.3 destroyed successfully!");
}









//! =================================================== END VULKAN TOOLS ==========================================

//* ======== GLFW Tools ========

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
    window = glfwCreateWindow(800, 600, "Remember to replace me", null, null);

    // Something even scarier fails to load
    if (!window || window == null) {
        writeln("WINDOW FAILED TO OPEN!\n",
        "ABORTING!");
        glfwTerminate();
        return false;
    }

    // In the future, get array of monitor pointers with: GLFWmonitor** monitors = glfwGetMonitors(&count);
    // monitor = glfwGetPrimaryMonitor();
  

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

void close() {
    glfwSetWindowShouldClose(window, true);
}

bool isFullScreen() {
    return fullscreen;
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