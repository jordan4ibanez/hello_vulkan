module window.window;

import std.stdio;
import std.conv;
import std.string;
import bindbc.glfw;
import doml.vector_2i;
import doml.vector_2d;
import doml.vector_3d;
import delta_time;
import erupted;

// This is a special import. We only want to extract the loader from this module.
import loader = bindbc.loader.sharedlib;

// OpenGL fields
private string glVersion;
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


void initialize() {
    if (!initializeGLFW()) {
        throw new Exception("GLFW failed");
    }
    // Initialize Vulkan goes here
}

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

    if(returnedError != glfwSupport) {
        writeln("ERROR IN GLFW!");
        writeln("---------- DIRECT DEBUG ERROR ---------------");
        // Log the direct error info
        foreach(info; loader.errors) {
            logCError(info.error, info.message);
        }
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

    // Minimum version is 4.1 (July 26, 2010)
    glfwWindowHint(GLFW_CONTEXT_VERSION_MAJOR, 4);
    glfwWindowHint(GLFW_CONTEXT_VERSION_MINOR, 1);
    glfwWindowHint(GLFW_OPENGL_PROFILE, GLFW_OPENGL_CORE_PROFILE);

    // Allow driver optimizations
    glfwWindowHint(GLFW_OPENGL_FORWARD_COMPAT, GL_TRUE);

    bool halfScreenAuto = false;

    // Auto start as half screened
    if (windowSizeX == -1 || windowSizeY == -1) {
        halfScreenAuto = true;
        // Literally one pixel so glfw does not crash.
        // Is automatically changed before the player even sees the window.
        // Desktops like KDE will override the height (y) regardless
        windowSizeX = 1;
        windowSizeY = 1;
    }

    // Create a window on the primary monitor
    window = glfwCreateWindow(windowSizeX, windowSizeY, title.toStringz, null, null);

    // Something even scarier fails to load
    if (!window || window == null) {
        writeln("WINDOW FAILED TO OPEN!\n",
        "ABORTING!");
        glfwTerminate();
        return false;
    }

    // In the future, get array of monitor pointers with: GLFWmonitor** monitors = glfwGetMonitors(&count);
    monitor = glfwGetPrimaryMonitor();

    // Using 3.3 regardless so enable raw input
    // This is so windows, kde, & gnome scale identically with cursor input, only the mouse dpi changes this
    // This allows the sensitivity to be controlled in game and behave the same regardless
    glfwSetInputMode(window, GLFW_RAW_MOUSE_MOTION, GLFW_TRUE);


    // Monitor information & full screening & halfscreening

    // Automatically half the monitor size
    if (halfScreenAuto) {
        writeln("automatically half sizing the window");
        setHalfSizeInternal();
    }


    glfwSetFramebufferSizeCallback(window, &myframeBufferSizeCallback);

    // glfwSetKeyCallback(window, &externalKeyCallBack);

    // glfwSetCursorPosCallback(window, &externalcursorPositionCallback);


    // glfwSetWindowRefreshCallback(window, &myRefreshCallback);
    
    glfwMakeContextCurrent(window);

    // The swap interval is ignored before context is current
    // We must set it again, even though it is automated in fullscreen/halfsize
    glfwSwapInterval(vsync);

    glfwGetWindowSize(window,&windowSize.x, &windowSize.y);    

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

void destroy() {
    glfwDestroyWindow(window);
    glfwTerminate();
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