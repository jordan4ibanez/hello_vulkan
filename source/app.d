import std.stdio;

import bindbc.glfw;
import erupted.functions;

void main()
{
	writeln("Vulkan goes here!");
    glfwLoad();

    glfwInit();
    glfwWindowHint(GLFW_CLIENT_API, GLFW_NO_API);
    glfwWindowHint(GLFW_RESIZABLE, GLFW_FALSE);
    GLFWwindow* window = glfwCreateWindow(800,600, "Vulkan Window", null, null);


    uint extensionCount = 0;
    // vkEnumerateInstanceExtensionProperties(null, &extensionCount, null);
    

    // VkResult blah = vkEnumerateInstanceExtensionProperties(VK_NULL_HANDLE, VK_NULL_HANDLE, VK_NULL_HANDLE);
    // writeln("Extensions supported: ", extensionCount);

    while(!glfwWindowShouldClose(window)) {



        glfwPollEvents();
    }

    glfwDestroyWindow(window);
    glfwTerminate();
}


void glfwLoad() {
    /*
    This version attempts to load the GLFW shared library using well-known variations of the library name for the host
    system.
    */
    GLFWSupport ret = loadGLFW();
    if(ret != glfwSupport) {

        /*
        Handle error. For most use cases, it's reasonable to use the the error handling API in bindbc-loader to retrieve
        error messages for logging and then abort. If necessary, it's possible to determine the root cause via the return
        value:
        */

        if(ret == GLFWSupport.noLibrary) {
            // The GLFW shared library failed to load
        }
        else if(GLFWSupport.badLibrary) {
            /*
            One or more symbols failed to load. The likely cause is that the shared library is for a lower version than bindbc-glfw was configured to load (via GLFW_31, GLFW_32 etc.)
            */
        }
    }
    /*
    This version attempts to load the GLFW library using a user-supplied file name. Usually, the name and/or path used
    will be platform specific, as in this example which attempts to load `glfw3.dll` from the `libs` subdirectory,
    relative to the executable, only on Windows.
    */
    version(Windows) loadGLFW("libs/glfw3.dll");
}