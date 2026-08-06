//
//  ToastShaders.metal
//  ToastUI
//
//  Metaball / "gooey" alpha threshold used by the Dynamic Island toast morph.
//  Blurred shapes are re-thresholded so overlapping blobs fuse into one form.
//
//  The layer is re-tinted with a flat colour rather than unpremultiplied, which
//  avoids the bright halo you get from `rgb / alpha` on nearly transparent edges.
//

#include <metal_stdlib>
#include <SwiftUI/SwiftUI.h>
using namespace metal;

[[stitchable]] half4 toastAlphaThreshold(
    float2 position,
    SwiftUI::Layer layer,
    half4 tint
) {
    half4 color = layer.sample(position);
    half threshold = 0.5h;
    half edge = 0.03h;
    half alpha = smoothstep(threshold - edge, threshold + edge, color.a);
    // Premultiplied output — flat tint, no edge fringing.
    return half4(tint.rgb * alpha, alpha);
}
