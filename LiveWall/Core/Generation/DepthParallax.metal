#include <CoreImage/CoreImage.h>
using namespace metal;

// Moves a camera through a still image: nearer pixels (depth towards 1) shift and grow more than far ones.
// Each output pixel looks back for where it came from, refined a few times using the depth found there.
extern "C" float4 depthParallax(coreimage::sampler image, coreimage::sampler depth,
                                float2 shift, float depthZoom, float cameraZoom, float2 center, float focus,
                                coreimage::destination dest) {
    float2 p = dest.coord();
    float2 source = p;
    for (int i = 0; i < 3; i++) {
        float d = depth.sample(depth.transform(source)).r - focus;
        source = center + (p - center) / (cameraZoom * (1.0 + depthZoom * d)) - shift * d;
    }
    return image.sample(image.transform(source));
}
