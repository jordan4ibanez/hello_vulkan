import std.stdio;

import bindbc.glfw;
import erupted.functions;
import window = window.window;

void main() {
    window.initialize();

    while (!window.shouldClose()) {
        window.pollEvents();

        window.render();
    }
    
    window.destroy();
}