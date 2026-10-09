#version 300 es
precision highp float;

in vec2 v_uv;
out vec4 outColor;

uniform float u_time;
uniform vec2 u_resolution;
uniform sampler2D u_tex;
uniform int u_mode;
uniform vec2 u_center;
uniform vec2 u_radius;
uniform int u_animate;
uniform float u_angle;
uniform float u_glow;
uniform float u_wisp;

#define PI  3.141592654
#define TAU (2.0*PI)
#define TIME (u_time*0.1)
#define LESS(a,b,c) mix(a,b,step(0.,c))
#define SABS(x,k)    LESS((.5/k)*x*x+k*.5,abs(x),abs(x)-k)

const float twirly = 0.5;

vec2 toPolar(vec2 p) { return vec2(length(p), atan(p.y, p.x)); }
vec2 toRect(vec2 p) { return p.x*vec2(cos(p.y), sin(p.y)); }
vec2 mod2(inout vec2 p, vec2 size) {
  vec2 c = floor((p + size*0.5)/size);
  p = mod(p + size*0.5,size) - size*0.5;
  return c;
}

void rot(inout vec2 p, float a) {
  float c = cos(a);
  float s = sin(a);
  p = vec2(c*p.x + s*p.y, -s*p.x + c*p.y);
}

vec2 twirl(vec2 p, float a) {
  vec2 pp = toPolar(p);
  float speed = (1.0 / (pp.x + 0.1)) * 1.5;
  pp.y -= a * speed;
  return toRect(pp);
}

float rand(vec2 co){
  return fract(sin(dot(co.xy ,vec2(12.9898,78.233))) * 43758.5453);
}

float noise1(vec2 p) {
  p *= tanh(0.1*length(p));
  float tm = TIME;
  float a = cos(p.x);
  float b = cos(p.y);
  float c = cos(p.x*sqrt(3.5)+tm);
  float d = cos(p.y*sqrt(1.5)+tm);
  return a*b*c*d;
}

vec3 stars(vec2 p) {
  vec2 pp = toPolar(p);
  pp.x /= (1.0+length(pp.x))*0.5;
  vec2 cp = toRect(pp);

  float sz = 0.04; // Increased grid size to reduce number of stars
  vec3 s = vec3(10000.0);
    
  for (int i = 0; i < 3; ++i) {  
    rot(cp, 0.5);
    vec2 ip = cp;
    vec2 n = mod2(ip, vec2(sz));
    float r = rand(n);
    vec2 o = -1.0 + 2.0*vec2(r, fract(r*1000.0));
    s.x = min(s.x, length(ip-0.25*sz*o));
    s.yz = n*0.1;
  }
  return s;
}

// --- Simplex Noise 2D for other modes ---
vec3 mod289(vec3 x) { return x - floor(x * (1.0 / 289.0)) * 289.0; }
vec2 mod289(vec2 x) { return x - floor(x * (1.0 / 289.0)) * 289.0; }
vec3 permute(vec3 x) { return mod289(((x*34.0)+1.0)*x); }
float snoise(vec2 v) {
    const vec4 C = vec4(0.211324865405187, 0.366025403784439, -0.577350269189626, 0.024390243902439);
    vec2 i  = floor(v + dot(v, C.yy) );
    vec2 x0 = v -   i + dot(i, C.xx);
    vec2 i1; i1 = (x0.x > x0.y) ? vec2(1.0, 0.0) : vec2(0.0, 1.0);
    vec4 x12 = x0.xyxy + C.xxzz; x12.xy -= i1;
    i = mod289(i);
    vec3 p = permute( permute( i.y + vec3(0.0, i1.y, 1.0 )) + i.x + vec3(0.0, i1.x, 1.0 ));
    vec3 m = max(0.5 - vec3(dot(x0,x0), dot(x12.xy,x12.xy), dot(x12.zw,x12.zw)), 0.0);
    m = m*m; m = m*m;
    vec3 x = 2.0 * fract(p * C.www) - 1.0;
    vec3 h = abs(x) - 0.5;
    vec3 ox = floor(x + 0.5);
    vec3 a0 = x - ox;
    m *= 1.79284291400159 - 0.85373472095314 * ( a0*a0 + h*h );
    vec3 g; g.x  = a0.x  * x0.x  + h.x  * x0.y; g.yz = a0.yz * x12.xz + h.yz * x12.yw;
    return 130.0 * dot(m, g);
}

vec2 g_center;
vec2 g_ellipseRadius;
float g_angle;
float g_aspect;

vec4 getBaseImage(vec2 p_norm) {
    vec2 sampleP = p_norm * g_ellipseRadius;
    rot(sampleP, g_angle);
    sampleP += g_center;
    vec2 sampleUv = sampleP;
    sampleUv.x /= g_aspect;
    sampleUv = sampleUv * 0.5 + 0.5;
    // Sample the texture at full resolution (LOD 0) to prevent any WebGL mipmap blurring from rotations/parallax
    return textureLod(u_tex, sampleUv, 0.0);
}

// Compute pure procedural dust field (ignoring image luminance)
float getDustDensity(vec2 p) {
  float s = 0.0;
  float a = 1.0;
  float f = 25.0;
  float d = 0.0;
  for (int i = 0; i < 11; ++i) { 
    vec2 pp = toPolar(p);
    pp.y += pp.x * twirly + TIME*(0.025*float(i));
    vec2 tp = toRect(pp) * f;
    s += a * noise1(tp);
    a *= sqrt(0.45);
    f *= sqrt(2.0);
    d += a;
  }
  return SABS((-0.25+ s/d), 0.5);
}

void main() {
    vec2 uv = v_uv;
    vec2 p = uv * 2.0 - 1.0; 
    float aspect = u_resolution.x / u_resolution.y;
    p.x *= aspect;
    vec4 finalColor = vec4(0.0);

    if (u_mode == 0) {
        vec4 originalColor = texture(u_tex, uv);
        finalColor = originalColor;

        if (u_animate == 1) {
            vec2 center = u_center * 2.0 - 1.0;
            center.x *= aspect;

            vec2 diff = p - center;
            rot(diff, -u_angle);
            vec2 ellipseRadius = max(u_radius, vec2(0.05));
            
            vec2 normP = diff / ellipseRadius;
            float originalDist = length(normP);
            
            g_center = center;
            g_ellipseRadius = ellipseRadius;
            g_angle = u_angle;
            g_aspect = aspect;
            
            // 2. Calculate a macroscopic 3D Depth (Paraboloid) for Parallax
            float PR = 2.0; 
            float pr2 = dot(normP, normP);
            float depthZ = max(0.0, 1.0 - pr2 / (PR * PR));
            
            // Tangential (orbital) wispy smoke offset for the dust
            vec2 tangent = vec2(-normP.y, normP.x); 
            float smokeNoise = snoise(normP * 3.0 - vec2(TIME * 0.5));
            vec2 dustP = normP + tangent * smokeNoise * 0.1 * smoothstep(1.5, 0.0, length(normP));
            
            float dust = getDustDensity(dustP); 
            
            // Wobble grows from the center (0) to the mid-edges, then fades out before the boundary (1.0) 
            // Reduced maximum amplitude per user request (0.012)
            float wobbleIntensity = smoothstep(0.0, 0.6, originalDist) * smoothstep(1.0, 0.7, originalDist) * 0.012;
            vec2 wobble = vec2(snoise(normP * 2.0 + TIME * 0.2), snoise(normP * 2.0 - TIME * 0.2)) * wobbleIntensity;
            
            // Sample exactly without WebGL mipmap blurring
            vec4 naturalImage = getBaseImage(normP + wobble);
            float currentLum = dot(naturalImage.rgb, vec3(0.299, 0.587, 0.114));
            
            // 3. Modulate the natural image into soft, seamless flowing smoke
            float maxColor = max(naturalImage.r, max(naturalImage.g, naturalImage.b));
            float minColor = min(naturalImage.r, min(naturalImage.g, naturalImage.b));
            
            // Switch back to saturation instead of absolute difference.
            // This ensures that even very dark pixels (e.g., dark red space dust) still get smoke if they are colorful.
            float saturation = (maxColor > 0.0) ? (maxColor - minColor) / maxColor : 0.0;
            float softColorMask = smoothstep(0.0, 0.5, saturation);
            
            // User request: isolate the VERY bright parts of the image (luminous gasses)
            // By shifting the smoothstep to (0.4, 0.9), the smoke basically vanishes on dark/mid-tones 
            // and aggressively multiplies on the brightest gasses so they look like they're actively smoking.
            float lumModifier = mix(0.05, 4.0, smoothstep(0.4, 0.9, currentLum));
            
            // To create literal thin wisps of smoke (like cigarette smoke) rather than chunky fluid blobs,
            // we use a ridge-noise technique. Taking the absolute value of noise and inverting it creates
            // sharp, organic, intersecting tendrils.
            // Sped up the TIME multipliers significantly so the tendrils smolder and dance actively.
            float wisp1 = 1.0 - abs(snoise(normP * 10.0 + TIME * 0.3));
            float wisp2 = 1.0 - abs(snoise(normP * 16.0 - TIME * 0.45));
            float wispySmoke = pow(wisp1 * wisp2, 6.0); // High power makes the tendrils extremely thin
            
            // Brought the fade slightly closer to the core so the bright inner gasses can smoke, 
            // while still protecting the absolute center.
            float smokeFade = smoothstep(0.15, 0.5, originalDist);
            float smokeDensity = wispySmoke * softColorMask * smokeFade * lumModifier;
            
            // For the smoke color: if we just use naturalImage.rgb on dark pixels, the smoke will be invisible.
            // So for dark pixels, we extract the pure color (hue) to ensure the smoke pops.
            vec3 pixelHue = (maxColor > 0.0) ? (naturalImage.rgb / maxColor) : vec3(1.0);
            vec3 smokeColor = mix(naturalImage.rgb, pixelHue, smoothstep(0.3, 0.0, currentLum));
            
            // The smoke is an additive layer
            // User can now manually control this via the Wisp Brightness slider (u_wisp)
            vec3 smokeLayer = smokeColor * smokeDensity * (0.125 * u_wisp); 
            
            // We let u_glow control how much the absolute center is dimmed
            float centerVisibility = mix(clamp(u_glow, 0.0, 1.0), 1.0, smoothstep(0.0, 0.5, originalDist));
            
            // The base image stays completely intact, we just add the flowing smoke layer on top
            vec3 galaxyColor = (naturalImage.rgb + smokeLayer) * centerVisibility;
            
            // 4. Very subtle Volumetric 3D Lighting (to give the dust physical depth)
            float eps = 0.005;
            float hL = getDustDensity(dustP - vec2(eps, 0.0));
            float hR = getDustDensity(dustP + vec2(eps, 0.0));
            float hD = getDustDensity(dustP - vec2(0.0, eps));
            float hU = getDustDensity(dustP + vec2(0.0, eps));
            vec3 normal = normalize(vec3(hL - hR, 0.2, hD - hU)); // Safe normal to prevent edgeGlow explosion
            
            vec3 p3 = vec3(normP.x, dust, normP.y);
            vec3 lp1 = vec3(-0.5, 0.5, 0.0);
            vec3 ld1 = normalize(lp1 - p3);
            vec3 lp2 = vec3(0.5, 0.5, 0.0);
            vec3 ld2 = normalize(lp2 - p3);
            
            float diff1 = max(dot(ld1, normal), 0.0);
            float diff2 = max(dot(ld2, normal), 0.0);
            
            // Gentle directional light reflection (lowered to prevent color washout)
            galaxyColor += naturalImage.rgb * 0.05 * (diff1 + diff2);
            
            // Subtle edge highlight on dust ridges (lowered to prevent color washout)
            float tl = tanh(originalDist);
            float edgeGlow = pow(clamp(dust, 0.001, 0.999), normal.y * 2.5 * tl);
            galaxyColor += naturalImage.rgb * edgeGlow * 0.15;
            
            // 5. Procedural Stars (Rigidly orbiting)
            vec2 starP = normP;
            rot(starP, TIME * 0.2); // Match the galaxy rotation speed exactly 
            vec3 s = stars(starP);
            float sr = rand(s.yz);
            
            // User requested smaller, sharper stars, and a bit less of them.
            // Reduced radius, tightened the core epsilon, and raised the sparsity threshold.
            float si = 0.0008; // Smaller radius
            float sparseMask = step(0.85, sr); // Only ~15% of the grid cells will actually render a star
            
            // Stars are colored by the photo underneath them, with a very gentle, slow pulsation
            float pulsate = 0.8 + 0.2 * sin(TIME * 2.0 + sr * 100.0);
            
            // Less stars as you approach the center
            float starCenterMask = smoothstep(0.15, 0.4, originalDist);
            
            // Render the stars (increased exponent to 2.5 for a sharper edge falloff)
            vec3 scol = sr * sparseMask * pulsate * starCenterMask * 2.0 * tanh(pow(si / (s.x + 0.00002), 2.5)) * naturalImage.rgb * 0.8;
            galaxyColor += clamp(scol, 0.0, 1.0);
            
            // 5.5 Extra Brightness Glow & Rotating Core
            // Allow the glow to cover the core exactly, rather than being a ring
            float brightnessGlow = pow(currentLum, 3.0) * smoothstep(1.5, 0.0, originalDist) * u_glow;
            galaxyColor += naturalImage.rgb * brightnessGlow;
            
            // Parabola-like 3D dome covering the galaxy
            float coreRadius = 2.0; // Extend the core effect outwards significantly
            
            // The core appears where it is close to the center AND where the original pixels are bright
            // Using a softer falloff to extend far into the galaxy
            float coreIntensity = exp(-pow(originalDist / (coreRadius * 0.8), 1.5)) * smoothstep(0.4, 0.9, currentLum);
            
            if (coreIntensity > 0.001) {
                // Only rotate the core *effect*, not the image itself, to avoid tearing/warping the photo
                vec2 coreUV = normP;
                rot(coreUV, TIME * 1.5); 
                
                vec4 coreImage = naturalImage;
                
                // "A bit less than a standard parabola" 
                // We construct a flattened 3D dome/paraboloid that protrudes from the center
                float R = coreRadius;
                float height = 1.5; 
                // Parabola: z = height * (1 - r^2 / R^2)
                // Gradient: dz/dx = -2 * height / R^2 * x
                float slope = -2.0 * height / (R * R);
                vec2 grad = slope * normP;
                vec3 coreNormal = normalize(vec3(-grad.x, -grad.y, 1.0));
                
                // 3D Lighting with slowly orbiting light to emphasize the 3D shape
                vec3 lightDir = normalize(vec3(sin(TIME * 2.0), cos(TIME * 2.0), 1.5));
                float nDotL = max(dot(coreNormal, lightDir), 0.0);
                
                // To make the center almost transparent but extend the glow outwards along the parabola,
                // we use a Fresnel/rim-light approach. The center (facing camera) gets less light, 
                // and the curved slopes catch more light.
                float facingRatio = dot(coreNormal, vec3(0.0, 0.0, 1.0)); // 1.0 at center, decreases on slopes
                float rimLight = 1.0 - facingRatio; // 0.0 at center, grows outwards
                
                // Restored nDotL so the exact center still receives 3D light and doesn't look flat 2D
                float coreLight = (nDotL * 0.2) + (rimLight * 2.5);
                
                // Procedural noise for turbulence in the core
                float coreNoise = snoise(coreUV * 8.0 - vec2(0.0, TIME * 2.0));
                
                // We use u_glow to control the core emissive intensity, 
                // but clamp it at a minimum of 0.2 so the 3D rim light never completely vanishes.
                float glowMultiplier = max(0.2, u_glow);
                galaxyColor += coreImage.rgb * coreIntensity * coreLight * (1.0 + coreNoise * 0.5) * glowMultiplier;
            }
            
            // Seamless Masking
            vec3 finalComposite = clamp(galaxyColor, 0.0, 1.0);
            float alphaMask = smoothstep(1.0, 0.85, originalDist);
            
            // Keep the rest of the image outside the animation visible as requested
            vec4 originalBackground = texture(u_tex, uv);
            finalColor = mix(originalBackground, vec4(finalComposite, 1.0), alphaMask);
        }
        
    } else if (u_mode == 1) {
        vec4 texColor = texture(u_tex, uv);
        float lum = dot(texColor.rgb, vec3(0.299, 0.587, 0.114));
        float n1 = snoise(p * 2.0 + u_time * 0.1);
        float n2 = snoise(p * 2.0 - u_time * 0.15 + vec2(10.0));
        vec2 offset = vec2(n1, n2) * 0.04 * lum;
        offset.x /= aspect;
        vec4 displacedColor = texture(u_tex, uv + offset);
        displacedColor.rgb += texColor.rgb * n1 * lum * 0.4;
        finalColor = vec4(displacedColor.rgb, 1.0);
        
    } else if (u_mode == 2) {
        float radius = length(p);
        if (radius > 1.0) {
            finalColor = vec4(0.0, 0.0, 0.0, 1.0);
        } else {
            float z = sqrt(1.0 - radius * radius);
            float lon = atan(p.x, z);
            float lat = asin(p.y);
            lon += u_time * 0.15;
            vec2 sphereUv = vec2(
                lon / (3.14159265) + 0.5, 
                lat / (3.14159265 * 0.5) * 0.5 + 0.5
            );
            vec4 texColor = texture(u_tex, sphereUv);
            vec3 normal = normalize(vec3(p.x, p.y, z));
            vec3 lightDir = normalize(vec3(1.0, 0.5, 1.0));
            float diff = max(dot(normal, lightDir), 0.0);
            float rim = smoothstep(0.0, 0.4, z);
            finalColor = vec4(texColor.rgb * (diff * 0.8 + 0.2) * rim, 1.0);
        }
    }

    outColor = finalColor;
}
