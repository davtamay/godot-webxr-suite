# WebXR Light Estimation — Findings & Evidence

Recorded from in-headset bring-up of `light_estimation_demo.tscn` on **Quest 3** and
**Samsung Galaxy XR (Android XR)**. Several of these are counter-intuitive and were
gotten wrong before being settled from data — hence this file. Everything below is
backed by a measurement or a citation, not recollection.

---

## 1. Platform support: Quest = NO, Android XR = YES

**Quest 3 Browser does not implement WebXR light estimation.** `requestLightProbe()`
rejects with `NotSupportedError`, and the optional `light-estimation` feature is
dropped from the session's `enabledFeatures`.

Evidence (three independent sources):

1. **Meta's own emulator** — [meta-quest/immersive-web-emulator](https://github.com/meta-quest/immersive-web-emulator)
   explicitly lists **"WebXR Lighting Estimation API ⛔" (not supported)**, while it
   *does* emulate hand input, plane detection, mesh detection, hit-test, anchors, layers.
2. **Meta's WebXR docs** — [Mixed Reality Support in Browser](https://developers.meta.com/horizon/documentation/web/webxr-mixed-reality/)
   enumerate Quest's MR features (passthrough, plane detection, persistent anchors,
   depth sensing, mesh detection, hand tracking, hit-test) and **omit light estimation
   entirely**. It is a specific gap, not a general WebXR weakness.
3. **Our own test, same build, both headsets:**
   - Quest `enabledFeatures` = `local, viewer, hand-tracking, webxr, local-floor`
     → **light-estimation absent** (even though we requested it; hand-tracking, also
     requested optionally, *was* granted).
   - Galaxy XR `enabledFeatures` = `local, viewer, `**`light-estimation`**`, hand-tracking, local-floor`
     → **LIVE**, streaming real direction + SH data.

Light estimation is an **Android XR / ARCore** capability. The bridge requests it
optionally, so the demo lights up automatically if a runtime ever grants it — no code
change needed. Spec: [W3C WebXR Lighting Estimation L1](https://www.w3.org/TR/webxr-lighting-estimation-1/)
(the `NotSupportedError` is exactly what a runtime that omits the feature produces).

---

## 2. Direction convention: `primaryLightDirection` is the TRAVEL direction

Android XR / ARCore report `primaryLightDirection` as **the direction the light
TRAVELS (away from the source)** — NOT the direction toward the source.

**Ground-truth measurement** (not eyeballing an arrow — that flip-flopped): logged
`dot(raw, cameraForward)` while the user looked **straight at the chandelier**. It held
steady at **-0.79** → `raw` points ~opposite the source.

Therefore the source is at **`-raw`**, and the demo does:
- `DirectionalLight3D`: `-Z = raw` (rays travel *from* the source, along `raw`).
- "TO REAL LIGHT" arrow: points to **`-raw`** (at the source).

### ⚠️ Pitfall: do NOT derive direction from the SH L1 via luminance
An earlier attempt computed direction as `normalize(vec3(lum(sh3), lum(sh1), lum(sh2)))`.
It is **sign-unstable**: when that luminance-weighted L1 vector crosses zero (as the
light rotates, or for a bluish light that luminance under-weights), the normalized
result **flips sign**, inverting the arrow **while the user sits perfectly still**.
The log caught it red-handed across one smooth `raw` transition:
`shDir == raw` → `shDir == (0,0,0)` → `shDir == -raw`. The raw `primaryLightDirection`
is stable; **use it directly.**

---

## 3. Transition speed ~0.8s is ARCore, not us (platform floor)

The estimate takes **~0.8s** to respond to a real lighting change. Measured by flipping
a chandelier off/on while sitting still and timestamping the light intensity:

```
ON:  i=0.13 (t=98939) → 0.73 (t=99788)  ≈ 0.78 s
OFF: i=0.45 (t=85483) → 0.32 (t=86246)  ≈ 0.76 s
```

**This is ARCore's own temporal convergence, not our pipeline.** Proof: raising our
smoothing rate from `5.5 → 20/s` (3.6×) produced **zero change** in the perceived drag.
ARCore deliberately ramps the estimate so real lights don't strobe as it re-samples the
room. **~0.8s is the floor; not something we can speed up.**

---

## 4. Rendering approach

- The estimate drives an environment **Sky** (`light_estimation_sky.gdshader`
  reconstructs radiance from the 9 SH coefficients), used for **both ambient and
  reflections**, so every object is lit by + reflects the real room. This replaced an
  earlier per-object SH-emission hack.
- The SH sky must be **scene-defined** (in the `WorldEnvironment`) so its shader
  **bakes** for the WebGPU export. A runtime-created sky shader is "missing from the
  baked shader cache" on WebGPU.
- Sky `process_mode`: INCREMENTAL or HIGH_QUALITY. **REALTIME is broken for custom sky
  shaders** — it forces radiance size 256 and throws a set-2 uniform-format mismatch
  that renders objects **black**. `radiance_size 32` is plenty (order-2 SH is very low
  frequency).

---

## Test setup

Standalone adaptive build (WebGL default + WebGPU via the in-demo renderer toggle),
served over HTTPS with a browser-console tap. All direction/timing numbers above were
captured on **Galaxy XR (Android XR)**, where light estimation is granted.
