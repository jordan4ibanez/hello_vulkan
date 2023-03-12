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

//! I wrote it how the C++ tutorial runs but we want this to ALWAYS check
// debug {
    private bool enableValidationLayers  = true;
// } else {
    // private bool enableValidationLayers  = false;
// }

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
    uint glfwExtensionCount = 0;
    const(char)** glfwExtensions;
    glfwExtensions = glfwGetRequiredInstanceExtensions(&glfwExtensionCount);
    createInfo.enabledExtensionCount = glfwExtensionCount;
    createInfo.ppEnabledExtensionNames = glfwExtensions;
    createInfo.enabledLayerCount = 0;

    // Make an instance of Vulkan in program
    if (vkCreateInstance(&createInfo, VK_NULL_HANDLE, &instance) != VK_SUCCESS) {
        throw new Exception("Vulkan: Failed to create instance!");
    }

    // We can now load up instance level functions
    loadInstanceLevelFunctions(instance);

    // Check for extension support
    uint extensionCount = 0;
    vkEnumerateInstanceExtensionProperties(VK_NULL_HANDLE, &extensionCount, VK_NULL_HANDLE);
    VkExtensionProperties[] extensions = new VkExtensionProperties[extensionCount];
    vkEnumerateInstanceExtensionProperties(VK_NULL_HANDLE, &extensionCount, cast(VkExtensionProperties*)&extensions[0]);

    // Output available extensions into the terminal
    if (false) {
        writeln("VULKAN AVAILABLE EXTENSIONS:" ~
                "==================================");
        foreach (VkExtensionProperties thisExtension; extensions) {
            writeln(split(to!string(thisExtension.extensionName), "\0")[0]);
        }
    }
}

private bool checkValidationLayerSupport() {

    uint layerCount = 0;
    vkEnumerateInstanceLayerProperties(&layerCount, VK_NULL_HANDLE);
    VkLayerProperties[] availableLayers = new VkLayerProperties[layerCount];
    vkEnumerateInstanceLayerProperties(&layerCount, &availableLayers);

    



    
    return false;
}

void destroy() {
    vkDestroyInstance(instance, VK_NULL_HANDLE);
    writeln("Vulkan instance destroyed successfully!");
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