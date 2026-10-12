#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

// Empty/background pixels remain transparent over the page's pure white fill.
static half4 messageInk(half4 color) {
    if (color.a > 0.0h) {
        half3 rgb = color.rgb / color.a;
        if (min(rgb.r, min(rgb.g, rgb.b)) > 0.78h) { return half4(0.0h); }
    }
    return color;
}

[[ stitchable ]] half4 headerBlurHorizontal(float2 position, SwiftUI::Layer layer, float contentTop) {
    float y = position.y + contentTop;
    if (y >= 14.0) { return layer.sample(position); }
    float amount = 1.0 - smoothstep(-24.0, 14.0, y);
    half4 color = half4(0.0h);
    float weights = 0.0;
    for (int i = -16; i <= 16; ++i) {
        float weight = exp(-float(i * i) / 72.0);
        color += messageInk(layer.sample(position + float2(float(i) * 0.5 * amount, 0))) * half(weight);
        weights += weight;
    }
    return color / half(weights);
}

[[ stitchable ]] half4 headerBlurVertical(float2 position, SwiftUI::Layer layer, float contentTop) {
    float y = position.y + contentTop;
    if (y >= 14.0) { return layer.sample(position); }
    float amount = 1.0 - smoothstep(-24.0, 14.0, y);
    half4 color = half4(0.0h);
    float weights = 0.0;
    for (int i = -16; i <= 16; ++i) {
        float weight = exp(-float(i * i) / 72.0);
        color += layer.sample(position + float2(0, float(i) * 0.5 * amount)) * half(weight);
        weights += weight;
    }
    return (color / half(weights)) * half(smoothstep(-120.0, 0.0, y));
}
