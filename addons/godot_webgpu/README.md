# Godot WebGPU (web)

Standalone tooling for shipping a Godot **web** export on the **WebGPU** backend.
No dependencies — drop it into any web project, XR or not. Two pieces:

- a one-checkbox **WebGPU adaptive-build** export toggle, and
- a **`BakeAnchor`** node for declaring runtime-built materials so their shaders
  bake ahead of time.

Requires a custom Godot engine build that has the WebGPU driver + shader baker.
On a stock Godot (no WebGPU driver) the toggle simply produces the usual WebGL
build and `BakeAnchor` is a harmless no-op.

## One-toggle WebGPU export

Enable the addon, then in the **Web export preset** you get:

- **`webgpu/adaptive_build`** — turn it on and the plugin forces everything a
  WebGPU build needs: `shader_baker/enabled` (option override), and at export
  start `rendering_method.web = mobile`, `driver.web = webgpu`, and multiview XR
  shaders disabled. Off = a normal WebGL build, no WebGPU cost.
- **`webgpu/xr_compatible`** (shown only when the above is on) — for immersive
  **WebXR** apps: forces `webxr/uses_webxr` so the loader requests an
  XR-compatible WebGPU adapter (needed for `XRGPUBinding` / entering VR-AR on
  WebGPU). Leave it off for a non-XR web game.

The one thing the toggle **can't** flip is the editor's **base Rendering
Method**: the shader baker only runs when the editor itself uses a
RenderingDevice renderer, and that's fixed at editor startup. So when
`adaptive_build` is on but the base isn't `Mobile`/`Forward+`, the export dialog
shows a warning naming the exact setting to change (one setting + one restart).
After that, export normally.

## Runtime-built materials on WebGPU: declare-and-bake

WebGPU has no in-browser shader translation. Shaders are baked ahead of time at
export (SPIR-V → WGSL) — the same model as Unity's shader variant collections —
so a material whose **shader** is first seen at runtime has nothing baked and
fails on the WebGPU backend (`missing from the baked shader cache`). Engines that
author shaders in WGSL directly (Bevy) sidestep it; engines with their own shader
language (Godot, Unity) precompile. This is the industry-standard tradeoff.

Most runtime material changes need **nothing**: changing *uniforms* (albedo
colour, roughness, energy, swapping a texture) reuses an already-baked shader.
You only act when the **shader itself is new** — a `StandardMaterial3D` whose
feature flags differ from anything an exported scene already renders
(`emission_enabled`, transparency, a different cull/blend mode…), or a
`ShaderMaterial` with code no exported scene already uses.

For those, **declare them** with a `BakeAnchor`:

```gdscript
# 1. Save the material as a .tres with its codegen flags frozen (the flags that
#    change the shader — transparency, emission_enabled, cull mode, etc.).
# 2. Drop a BakeAnchor node into any scene reachable from your main scene and add
#    the .tres to its `materials` array (in the inspector or from code).
# 3. At runtime, load()/duplicate() that .tres — its shader is already baked.
```

`BakeAnchor` references each declared material on tiny hidden meshes so the
exporter's shader baker includes it; the references are invisible and freed at
runtime, so there is zero in-game cost. Harmless no-op on WebGL / non-web.

> Verified: a custom `ShaderMaterial` referenced *only* by a `BakeAnchor`, then
> applied to a mesh at runtime, renders on the WebGPU backend with no
> `missing from the baked shader cache` error.

## Contents

```text
addons/godot_webgpu/
  plugin.cfg / plugin.gd
  webgpu_export_plugin.gd   # the "WebGPU adaptive build" export-preset toggle
  bake_anchor.gd            # BakeAnchor: declare runtime-built materials to bake
```
