# Getting Started — WebXR in Godot (the 5-minute path)

Build a WebXR app that runs in the browser and on a headset, using **the same XR
nodes you'd use for OpenXR** — nothing to reinvent.

---

## 1. Install (one time)

You need this fork's **editor** + its **web export templates**.

1. Open the editor.
2. **Editor → Manage Export Templates → Install from File** and pick the web
   templates: `web_release.zip` (threaded) and `web_nothreads_release.zip`
   (single-threaded — hosts anywhere, no special headers).

That's it — no compiler, no toolchain. (See the "Hosting" note at the bottom for
which one to ship.)

## 2. Add the addons to your project

**One command** (copies the addons in, and installs the web templates if you
point it at the fork's `bin/`):

```powershell
.\setup.ps1 -Project C:\path\to\your\project -Engine C:\path\to\fork\bin
```

Or copy the `addons/` folder in by hand. The suite is:

| Addon | What it gives you |
|---|---|
| `godot_webxr_kit` | VR/AR session bootstrap, the XR rig, the WebXR shell |
| `godot_xr_interaction_toolkit` | grab / hover / ray-pointer / socket / UI-raycast |
| `godot_xr_hands` | hand-tracking gestures + gesture locomotion |
| `godot_xr_scene_understanding` | cross-runtime room mesh and depth/occlusion |
| `godot_webxr_scene_understanding` | WebXR compatibility, hit-test, anchors, and light estimation |
| `godot_webgpu` | one-checkbox WebGPU export (optional) |
| `godot_universal_xr_apk` | one arm64 OpenXR APK for Quest 3 and Android XR |

Every node in these is a `class_name` script, so they show up directly in
**Add Node** — no plugin toggling required.

## 3. Run the starter scene

Open **`addons/godot_webxr_kit/samples/webxr_starter.tscn`** and press Play.

It already contains everything: the standard XR rig (`XROrigin3D` + `XRCamera3D`
+ `XRController3D` ×2 + hands + interactors), the **Enter VR / Enter AR** panel,
and a grabbable cube. Export it (step 5) and it runs on your headset as-is.

## 4. Build your own scene — it's just the standard nodes

A WebXR scene is the **exact same graph as an OpenXR scene**:

```
XROrigin3D
 ├─ XRCamera3D                        # the head (current = true)
 ├─ XRController3D (left / right)      # controllers, tracker = "left_hand"/"right_hand"
 ├─ Skeleton3D + XRHandModifier3D      # tracked hands (fed on both platforms)
 └─ (drop in interactors / gesture / scene-understanding nodes for extras)
+ WebXRBootstrap  (+ Enter VR / Enter AR buttons wired to it)
```

Because Godot's `WebXRInterface` and `OpenXRInterface` both fill the *same*
trackers, **this scene runs on a native OpenXR headset and in the browser
unchanged.** Copy the rig from the starter scene and add your content.

## 5. Export for the web

- **GL (default, recommended):** just export the Web preset. Full features,
  including depth sensing. Works on every WebXR browser.
- **WebGPU (optional):** enable the `godot_webgpu` addon, tick **WebGPU** in the
  Web preset. If it prompts, click **Set up WebGPU rendering** (switches the
  renderer to Mobile + restarts). Your app then boots WebGL by default and can
  switch to WebGPU at runtime.

## 6. Serve + open on the headset

WebXR needs **HTTPS** (a secure context). Serve the exported folder over HTTPS
and open the URL in the headset's browser → **Enter VR / Enter AR**.

---

### Hosting note (which template)

- **`Thread Support` OFF → single-threaded:** hosts **anywhere**, no COOP/COEP
  headers, no SharedArrayBuffer. Use this to deploy on any plain static host.
- **`Thread Support` ON → threaded:** needs the host to send COOP/COEP headers.
  A later upgrade for extra CPU headroom; not required.

You flip one checkbox — Godot picks the matching template automatically.
