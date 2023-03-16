#version 450

layout(location = 0) out vec3 fragColor;


vec2 positions[9] = vec2[](
    // Top
    vec2( 0.0, -1.0),
    vec2( 0.5,  0.0),
    vec2(-0.5,  0.0),

    //Bottom left
    vec2(-0.5,  0.0),
    vec2( 0.0,  1.0),
    vec2(-1.0,  1.0),

    //Bottom Right
    vec2( 0.5,  0.0),
    vec2( 1.0,  1.0),
    vec2( 0.0,  1.0)

);

const vec3 gold = vec3(255.0 / 255.0, 215 / 255.0, 0);
const vec3 sun  = vec3(253.0 / 255.0, 216.0 / 255.0, 53.0 / 255.0);

vec3 colors[9] = vec3[](
        sun,
    gold, gold,
        sun,
    gold, gold,
        sun,
    gold, gold
    // vec3(1.0, 0.0, 0.0),
    // vec3(0.0, 1.0, 0.0),
    // vec3(0.0, 0.0, 1.0),

    // vec3(1.0, 1.0, 0.0),
    // vec3(0.0, 1.0, 0.0),
    // vec3(1.0, 0.0, 1.0),

    // vec3(1.0, 0.0, 0.0),
    // vec3(0.0, 1.0, 0.0),
    // vec3(0.0, 0.0, 1.0)
);

void main() {
    gl_Position = vec4(positions[gl_VertexIndex], 0.0, 1.0);
    fragColor = colors[gl_VertexIndex];
}