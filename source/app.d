import std.stdio;

import bindbc.glfw;
import erupted.functions;
import window = window.window;

/** C++ reference code

class HelloTriangleApplication {
    void run() {
        initVulkan();
        mainLoop();
        cleanup();
    }

    void initVulkan() {}
    void mainLoop() {}
    void cleanup() {}
};

calls run(); in main();
*/

void main() {
    window.initialize();

    while (!window.shouldClose()) {
        window.pollEvents();
    }
    
    window.destroy();
}