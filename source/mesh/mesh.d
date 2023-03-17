module mesh.mesh;

import std.stdio;

import erupted;
import erupted.types;
import erupted.vulkan_lib_loader;
import erupted.platform_extensions;

import doml.vector_2d;
import doml.vector_3d;
import doml.vector_4d;
import doml.vector_4i;

//Mesh struct container
struct Vertex {
    Vector3d position;
    Vector3d color;
}

/// An Vulkan mesh. Utilizes builder pattern.
class Mesh {


    /// Creates the Vulkan context for assembling this Vulkan Mesh Object.
    this() {
        

    }

    private static VkVertexInputBindingDescription getBindingDescription() {
        VkVertexInputBindingDescription bindingDescription;

        bindingDescription.binding = 0;
        bindingDescription.stride = Vertex.sizeof;
        bindingDescription.inputRate = VK_VERTEX_INPUT_RATE_VERTEX;


        return bindingDescription;
    }

    /// Adds vertex position data in Vector3 format within a linear double[].
    Mesh addVertices3d(const double[] vertices) {
        return this.verticesFunc(vertices, 3);
    }

    // The actual mechanism for addVertices
    private Mesh verticesFunc(const double[] vertices, uint size) {


        return this;
    }

    /// Adds texture coordinate data in Vector2 format within a linear double[].
    Mesh addTextureCoordinates(const double[] textureCoordinates) {

        return this;
    }


    /// Unbinds the Vulkan Array Buffer and Vertex Array Object in GPU memory
    Mesh finalize() {

        return this;
    }


    void cleanUp() {


    }

    /// shaderName is the shader you want to render with
    void render(string shaderName) {


    }


}

