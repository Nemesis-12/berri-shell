#version 440

// berri theme-switch wallpaper transition (28a). One fragment shader covers
// all five picked transitions (A/B/C2/D/F); WallpaperLayer.qml picks the
// mode per switch and drives `progress` 0..1 linearly over the transition
// duration. Geometry mirrors berri-mocks/scratchpad/mock-ui.html's
// transitionPaletteSweep/transitionDiagonalWipe/transitionPixelDissolveEven/
// transitionInkBleed/transitionRadarSweep, done in device pixels so it holds
// up across monitors with different scale.
//
// Rebuild after editing this file:
//   /usr/lib/qt6/bin/qsb --glsl "100 es,120,150" --hlsl 50 --msl 12 \
//     -o shaders/transition.frag.qsb shaders/transition.frag

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float progress;
    int modeIndex;
    float seed;
    vec2 resolutionPx;
    vec4 oldColor;
    vec4 newColor;
    int oldHasImage;
    int newHasImage;
    vec4 paletteColor0;
    vec4 paletteColor1;
    vec4 paletteColor2;
    vec4 paletteColor3;
    vec4 paletteColor4;
    vec4 paletteColor5;
};

layout(binding = 1) uniform sampler2D oldSource;
layout(binding = 2) uniform sampler2D newSource;

const float PI = 3.14159265359;

float easeInOutCubic(float t) {
    return t < 0.5 ? 4.0 * t * t * t : 1.0 - pow(-2.0 * t + 2.0, 3.0) / 2.0;
}

vec4 oldAt(vec2 uv) {
    vec4 tex = textureLod(oldSource, uv, 0.0);
    return oldHasImage == 1 ? tex : oldColor;
}

vec4 newAt(vec2 uv) {
    vec4 tex = textureLod(newSource, uv, 0.0);
    return newHasImage == 1 ? tex : newColor;
}

// Cheap 2D hash, used only for C2's per-block reveal order (stands in for
// the demo's Fisher-Yates shuffle; with hundreds of 16px blocks per screen
// the two read the same to the eye).
float hash21(vec2 p) {
    p = fract(p * vec2(123.34, 456.21) + seed);
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

vec4 paletteColorFor(int i) {
    if (i == 0) return paletteColor0;
    if (i == 1) return paletteColor1;
    if (i == 2) return paletteColor2;
    if (i == 3) return paletteColor3;
    if (i == 4) return paletteColor4;
    return paletteColor5;
}

void main() {
    vec2 uv = qt_TexCoord0;
    vec2 px = uv * resolutionPx;
    float t = clamp(progress, 0.0, 1.0);
    vec4 result;

    if (modeIndex == 0) {
        // A: six equal columns of the new palette rise from the bottom
        // edge with a small left-to-right stagger, revealing the new
        // wallpaper underneath each as it passes.
        float colCount = 6.0;
        float colW = resolutionPx.x / colCount;
        int col = int(clamp(floor(px.x / colW), 0.0, colCount - 1.0));
        // Stagger is a fraction of the whole transition (about 5.5%), so it scales with the duration.
        float stagger = 60.0 / 1100.0;
        float colDur = 1.0 - stagger * (colCount - 1.0);
        float raw = clamp((t - float(col) * stagger) / colDur, 0.0, 1.0);
        float e = easeInOutCubic(raw);
        float colTop = 1.0 - e * 2.0;
        float colBottom = colTop + 1.0;
        float bandTop = clamp(colTop, 0.0, 1.0);
        float bandBottom = clamp(colBottom, 0.0, 1.0);
        float revealY = clamp(colBottom, 0.0, 1.0);
        if (bandBottom > bandTop && uv.y >= bandTop && uv.y <= bandBottom) {
            result = paletteColorFor(col);
        } else if (uv.y >= revealY) {
            result = newAt(uv);
        } else {
            result = oldAt(uv);
        }

    } else if (modeIndex == 1) {
        // B: diagonal wipe, left to right. No accent line on the edge.
        float angle = radians(20.0);
        float skew = resolutionPx.y * tan(angle);
        float e = easeInOutCubic(t);
        float topX = -skew + e * (resolutionPx.x + 2.0 * skew);
        float diagX = topX - skew * uv.y;
        result = (px.x <= diagX) ? newAt(uv) : oldAt(uv);

    } else if (modeIndex == 2) {
        // C2: equal 16px blocks flip old -> new in random order.
        float P = easeInOutCubic(t);
        vec2 cell = floor(px / 16.0);
        float rank = hash21(cell);
        result = (rank <= P) ? newAt(uv) : oldAt(uv);

    } else if (modeIndex == 3) {
        // D: organic ink bleed spreading from the notch (bottom center).
        float e = easeInOutCubic(t);
        float maxR = length(resolutionPx);
        float R = e * maxR * 1.05;
        vec2 center = vec2(resolutionPx.x * 0.5, resolutionPx.y);
        vec2 d = px - center;
        float dist = length(d);
        float ang = atan(d.y, d.x);
        float r = R + sin(3.0 * ang + t * 4.0) * R * 0.12 + sin(7.0 * ang - t * 6.0) * R * 0.06;
        result = (dist <= r) ? newAt(uv) : oldAt(uv);

    } else {
        // F: radar sweep pivoting at the bottom center, 180 degrees,
        // covering the whole screen. No accent line on the edge.
        float e = easeInOutCubic(t);
        vec2 center = vec2(resolutionPx.x * 0.5, resolutionPx.y);
        vec2 d = px - center;
        float ang = atan(d.y, d.x);
        float wrapped = mod(ang, 2.0 * PI);
        if (wrapped < PI) wrapped += 2.0 * PI;
        float endAngle = PI + e * PI;
        result = (wrapped <= endAngle) ? newAt(uv) : oldAt(uv);
    }

    fragColor = result * qt_Opacity;
}
