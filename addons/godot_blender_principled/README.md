# Godot Blender Principled

**An independent Blender→Godot material parity addon for Godot 4.7+ (Compatibility/WebGL2)**

This addon provides a Blender-named thin layer (`PrincipledMaterial`) over Godot's `StandardMaterial3D`, a strict-parity render environment for side-by-side comparison, and a reproduction workflow for validating glTF material imports.

**Status**: Standalone, zero external dependencies. Pure GDScript. No custom shaders. Works with Godot's native glTF importer.

---

## Blender→Godot Material Contract

When exporting glTF from Blender and importing into Godot, material properties follow this contract:

| Blender Source | Godot Target | Colorspace | Notes |
|---|---|---|---|
| Principled BSDF inputs (image textures) | StandardMaterial3D texture slots | **sRGB for color; Non-Color for data** | Bake channel-splits in Blender; no shader math between Image and Principled in glTF. |
| Base Color | `albedo_color` (alias: `base_color`) | sRGB | Via `PrincipledMaterial.base_color`. |
| Metallic | `metallic` | Non-Color (0–1 scalar) | Direct property; Blender name matches Godot. |
| Roughness | `roughness` | Non-Color (0–1 scalar) | Direct property; native Godot naming (NOT inverted). |
| Normal Strength | `normal_scale` (alias: `normal_strength`) | Non-Color | Via `PrincipledMaterial.normal_strength`. Enables `normal_enabled`. |
| Emission | `emission` + `emission_energy_multiplier` | sRGB color + scalar | Split into `emission_color` and `emission_strength` aliases. Godot imports `KHR_materials_emissive_strength` into `emission_energy_multiplier`. |
| IOR | `metallic_specular` | Non-Color | Approximated via Fresnel formula: `metallic_specular = (ior-1)² / (ior+1)² / 0.08`. Use `PrincipledMaterial.ior` (default 1.5). |
| Alpha / Alpha Mode | `transparency` | N/A | **Contract**: `Image.Alpha → Math:Round → Principled.Alpha` → glTF `alphaMode=MASK` → Godot `TRANSPARENCY_ALPHA_SCISSOR`. Opaque exports as `TRANSPARENCY_DISABLED`; Blend as `TRANSPARENCY_ALPHA`. |
| **Dielectric metallicFactor** | `metallic = 0.0` | Non-Color | **Set explicitly to 0 in glTF for dielectrics** (non-metals). glTF spec omits `metallicFactor` at 1.0, but Godot defaults to 1.0; non-metals must be explicit. |
| Transmission | Not supported in Phase 1 | — | Known gap (future). |
| Coat Weight / Sheen / Subsurface | Not supported in Phase 1 | — | Known gaps (future). |

**Key rules**:
1. **No shader math in glTF**: All channel-splitting (e.g., Normal packed into RGB + Roughness in Alpha) must be baked in Blender before export.
2. **Preserve Normal Strength, Mapping.Scale, IOR**: Custom mapping scales and IOR values are embedded in glTF and will be imported correctly.
3. **sRGB vs Non-Color**: Godot's importer respects glTF color space hints (`sRGB` for colors, `Linear` for data).

---

## Godot vs Unity: Key Deltas

Godot's material import path differs from Unity's URP-Lit:

| Aspect | Godot | Unity URP |
|---|---|---|
| glTF import path | Native Godot importer (glTFast-equivalent accuracy) | URP-Lit shader with BRDF conversion |
| Roughness encoding | Direct 0–1 (Blender-native) | Smoothness = 1 − Roughness (repack required) |
| `KHR_materials_emissive_strength` | Imported → `emission_energy_multiplier` | Imported separately; not always exposed |
| Specular model | Godot 4 dielectric specular via `metallic_specular` | URP-Lit standard BRDF (no fine-grained dielectric control) |
| Specular penalty | None; native support | URP-Lit applies standard BRDF tax on specular |
| Normal map strength | Via `normal_scale` | Via material properties |

**Implication**: Godot's native glTF import is the direct, accurate parity path. No BRDF remapping or smoothness inversion required.

---

## Material Parity Reproduction

To validate that a Blender material renders identically in Godot:

1. **Set up a parity scene**:
   - Add a `StrictParityEnvironment` (from `runtime/strict_parity_environment.gd`) to a scene and give it a row of spheres using `PrincipledMaterial`.
   - Load the `MaterialCollection.glb` under **strict-parity lighting** (Linear tonemap, 0.05 ambient, no GI).

2. **Render the Blender original**:
   - In Blender, open the same material collection source.
   - Set viewport shading to **Rendered** mode.
   - Set **Viewport Shading** → **Render Properties** → **Tonemap** to **Standard** (Linear equivalent).
   - Ensure **Global Illumination** is **OFF**.
   - Position the camera to match Godot's view.

3. **Compare side by side, in-engine**:
   - Save your Blender Standard-view render as `blender_reference_standardview.png`
     and drop it next to the GLB, at
     `res://addons/godot_blender_principled/samples/assets/blender_reference_standardview.png`.
   - In the showcase, press **R** to overlay that reference image over the live
     Godot render for a direct A/B at the matched camera. (Without the file, the
     scene runs normally and the on-screen hint tells you where to put it.)
   - Material colors, metallic, roughness, normal detail, emission should match
     1:1 under identical lighting. Per-sphere labels show the `PrincipledMaterial`
     metallic/roughness values.

4. **Toggle the "nice" render** (AgX):
   - Press **SPACE** in the Godot scene to toggle from strict-parity (Linear) to a nice-look environment (AgX tonemap, higher ambient, glow).
   - This confirms the same materials under different lighting; not part of the parity test.

---

## Using `PrincipledMaterial`

`PrincipledMaterial` is a thin subclass of `StandardMaterial3D` that exposes Blender-friendly property names.

### Basic setup

```gdscript
# In a MeshInstance3D script or scene
var mat = PrincipledMaterial.new()
mat.base_color = Color(0.8, 0.3, 0.2)      # Blender: Base Color
mat.metallic = 0.0                          # Blender: Metallic (direct)
mat.roughness = 0.5                         # Blender: Roughness (direct)
mat.normal_strength = 1.0                   # Blender: Normal Strength
mat.emission_color = Color(1.0, 0.5, 0.0)  # Blender: Emission
mat.emission_strength = 1.0                 # Blender: Emission Strength
mat.ior = 1.5                               # Blender: IOR → Fresnel/specular
mat.alpha_mode = PrincipledMaterial.AlphaMode.MASK  # Blender: Alpha Mode

mesh_instance.material_override = mat
```

### Alias mapping (Blender → Godot)

| Godot Property | Blender Name | Backing Field |
|---|---|---|
| `base_color` | Base Color | `albedo_color` |
| `normal_strength` | Normal Strength | `normal_scale` (enables `normal_enabled`) |
| `emission_color` | Emission | `emission` |
| `emission_strength` | Emission Strength | `emission_energy_multiplier` |
| `alpha_mode` | Alpha Mode | `transparency` (enum conversion) |
| `ior` | IOR | `metallic_specular` (Fresnel approximation) |

### Editing in the inspector

1. Assign `PrincipledMaterial` to a mesh.
2. In the inspector, scroll to the **"Blender Principled"** group.
3. Edit any of the Blender-named properties.
4. Godot's native properties (`metallic`, `roughness`, `normal_map`, etc.) update automatically.

---

## Implementation Notes

### Alias behavior

- **`base_color` ↔ `albedo_color`**: When set, syncs bidirectionally.
- **`normal_strength` ↔ `normal_scale`**: Enables `normal_enabled` and scales the normal map.
- **`emission_strength` ↔ `emission_energy_multiplier`**: Multiplies final emission intensity.
- **`ior` ↔ `metallic_specular`**: Fresnel specular intensity computed from IOR (default 1.5 → specular 0.5).
- **`alpha_mode`**: Converts `AlphaMode` enum to Godot's `transparency` states.

### Defaults

- `metallic = 0.0` (dielectric, matching Blender's Principled BSDF default).
- `roughness = 0.5` (mid-gloss, matching Blender).
- `metallic_specular = 0.5` (IOR 1.5 dielectric specular, matching Blender).
- `base_color` synced in `_init()` to ensure the grey default renders, not white.

---

## Known Limitations & Non-Goals

**Out of scope (Phase 1)**:
- **Subsurface scattering**: Requires subsurface-capable renderer; Compatibility/WebGL2 is limited.
- **Transmission / Glass**: Requires specialized transparency modes; future expansion.
- **Coat weight**: Requires multi-layer clearcoat model.
- **Sheen**: Requires anisotropic/sheen-capable BRDF.
- **Global Illumination bit-exactness**: GI is scene-dependent; parity assumes baked lighting from Blender or identical GI config.

**Known approximate**:
- **IOR → specular**: The Fresnel formula (`(ior-1)² / (ior+1)² / 0.08`) is a low-fidelity approximation of Blender's complex specular response. Use for dielectric preview; production specular tuning may require manual adjustment.

**Not a Blender Foundation tool**: This addon is independent, developed for Godot parity testing. It is not affiliated with or endorsed by the Blender Foundation.

---

## Files

- `runtime/principled_material.gd` — `PrincipledMaterial` class (Blender-named alias layer).
- `runtime/strict_parity_environment.gd` — `StrictParityEnvironment` utility (parity + nice-look render modes).
- `samples/assets/MaterialCollection.glb` — glTF material collection (reference from Blender).

---

## License & Attribution

See the project's root LICENSE file.
