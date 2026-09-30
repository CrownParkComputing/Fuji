//
//  EmuShaders.metal
//
//  One textured quad, aspect-corrected on the CPU and passed in as normalized
//  device coordinates. The vertex positions come from the vertex id, so no
//  vertex buffer is ever allocated.
//

#include <metal_stdlib>
using namespace metal;

// Must stay layout-identical to EmuDrawParams in EmuMetalView.swift.
struct EmuDrawParams {
    float2 center;
    float2 halfSize;
};

struct EmuVertexOut {
    float4 position [[position]];
    float2 uv;
};

vertex EmuVertexOut emuVertex(uint vertexID [[vertex_id]],
                              constant EmuDrawParams &params [[buffer(0)]]) {
    // Triangle strip: bottom-left, bottom-right, top-left, top-right.
    const float2 corners[4] = {
        float2(-1.0, -1.0), float2(1.0, -1.0),
        float2(-1.0,  1.0), float2(1.0,  1.0),
    };
    float2 corner = corners[vertexID];
    EmuVertexOut out;
    out.position = float4(params.center + corner * params.halfSize, 0.0, 1.0);
    // Metal textures are top-down; NDC y is bottom-up.
    out.uv = float2(corner.x * 0.5 + 0.5, 0.5 - corner.y * 0.5);
    return out;
}

fragment float4 emuFragment(EmuVertexOut in [[stage_in]],
                            texture2d<float> frame [[texture(0)]]) {
    // Linear, not nearest: the ST's 320x200 blown up to a phone screen with
    // nearest-neighbour shimmers on anything that scrolls sub-pixel.
    constexpr sampler s(filter::linear, address::clamp_to_edge);
    return frame.sample(s, in.uv);
}
