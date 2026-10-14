#version 460 core
#include <flutter/runtime_effect.glsl>

// Liquid Glass's lens (Plebz, Apple builds only; see lib/theme/liquid_glass.dart).
//
// A backdrop filter: the engine binds the picture behind the pane as
// u_texture and its size as u_size, both in the screen's physical pixels,
// and FlutterFragCoord is in the same space — so the pane says where it is
// (u_rect).
//
// As through a slab of glass with rounded edges: along the rim the picture
// stays sharp and bends inward, its colours parting a little, and the bevel
// catches the light; further in it softens to a frost, its colour lifted.

uniform vec2 u_size;
uniform vec4 u_rect;        // left, top, width, height
uniform float u_radius;     // corner radius
uniform float u_thickness;  // how far in from the rim the bevel reaches
uniform float u_strength;   // how far the picture bends at the rim
uniform float u_dispersion; // how far the colours part, as a share of the bend
uniform float u_frost;      // blur radius once past the bevel

uniform sampler2D u_texture;

out vec4 frag_color;

const int kTaps = 32;

float roundedBox(vec2 p, vec2 halfSize, float r) {
  vec2 q = abs(p) - halfSize + r;
  return min(max(q.x, q.y), 0.0) + length(max(q, 0.0)) - r;
}

vec3 sampleAt(vec2 p) {
  vec2 uv = p / u_size;
#ifdef IMPELLER_TARGET_OPENGLES
  uv.y = 1.0 - uv.y;
#endif
  return texture(u_texture, uv).rgb;
}

// A disc of taps, turned per pixel by interleaved gradient noise so the taps
// do not ghost into copies; at screen density the turn reads as smooth.
vec3 frosted(vec2 c, float radius, vec2 pixel) {
  if (radius < 0.75) return sampleAt(c);
  float turn = 6.2831853 * fract(52.9829189 * fract(dot(pixel, vec2(0.06711056, 0.00583715))));
  vec3 sum = vec3(0.0);
  for (int i = 0; i < kTaps; i++) {
    float f = (float(i) + 0.5) / float(kTaps);
    float a = float(i) * 2.39996323 + turn;
    sum += sampleAt(c + vec2(cos(a), sin(a)) * sqrt(f) * radius);
  }
  return sum / float(kTaps);
}

vec3 saturate(vec3 c, float s) {
  float l = dot(c, vec3(0.2126, 0.7152, 0.0722));
  return clamp(mix(vec3(l), c, s), 0.0, 1.0);
}

void main() {
  vec2 p = FlutterFragCoord().xy;
  vec2 halfSize = u_rect.zw * 0.5;
  vec2 local = p - (u_rect.xy + halfSize);
  float r = min(u_radius, min(halfSize.x, halfSize.y));
  float d = roundedBox(local, halfSize, r);

  // 1 at the rim, 0 once the bevel is crossed.
  float t = clamp(1.0 + d / max(u_thickness, 1.0), 0.0, 1.0);
  float bend = t * t;

  vec2 e = vec2(1.0, 0.0);
  vec2 n = vec2(
    roundedBox(local + e.xy, halfSize, r) - roundedBox(local - e.xy, halfSize, r),
    roundedBox(local + e.yx, halfSize, r) - roundedBox(local - e.yx, halfSize, r)
  );
  n = length(n) > 0.0001 ? normalize(n) : vec2(0.0);

  // Inward: what lies under the bevel is drawn from further in.
  vec2 shift = -n * bend * u_strength;
  // Sharp at the rim, frosted past the bevel.
  float radius = u_frost * smoothstep(0.0, 1.0, 1.0 - t);
  vec3 colour = frosted(p + shift, radius, p);
  if (bend > 0.01) {
    colour.r = mix(colour.r, sampleAt(p + shift * (1.0 + u_dispersion)).r, bend);
    colour.b = mix(colour.b, sampleAt(p + shift * (1.0 - u_dispersion)).b, bend);
  }
  colour = saturate(colour, 1.35);

  // Over bright content a frosted pane darkens a little, as Apple's regular
  // glass adjusts its luminosity, so the words standing on it stay readable;
  // past the bevel only. A rim without frost (a poster's, a bubble's) leaves
  // the picture under it as it is.
  if (u_frost > 0.5) {
    float luma = dot(colour, vec3(0.2126, 0.7152, 0.0722));
    colour *= 1.0 - 0.5 * smoothstep(0.3, 0.9, luma) * (1.0 - t);
  }

  // The bevel catches light: brightest where it faces up and to the left,
  // and a little where it faces down and right, the light coming out.
  float facing = max(dot(n, normalize(vec2(-0.6, -1.0))), 0.0) + 0.45 * max(dot(n, normalize(vec2(0.6, 1.0))), 0.0);
  colour += vec3(0.30) * t * t * t * (0.35 + facing);

  frag_color = vec4(colour, 1.0);
}
