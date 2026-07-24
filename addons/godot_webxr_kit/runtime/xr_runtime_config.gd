@tool
class_name XRRuntimeConfig
extends Resource

## One configuration surface for the shared XR prefab.
##
## Both platform adapters ship in the scene. At runtime the WebXR adapter can
## run only in web exports and the OpenXR adapter can run only in native builds;
## these switches configure their behavior without forking gameplay scenes.

@export_category("Platform adapters")
@export var webxr_enabled := true
@export var openxr_enabled := true

@export_category("WebXR")
## Requiring hands rejects the entire browser session on controller-only
## devices. Keep optional for the broadest WebXR compatibility.
@export var webxr_require_hand_tracking := false

@export_category("Native OpenXR")
## Start native builds in passthrough AR when the runtime supports alpha-blended
## composition. Unsupported desktop runtimes fall back to opaque VR.
@export var openxr_start_in_passthrough := true
## Portable default: let the runtime switch between hands and controllers.
## Enable only for a tested, intentionally mixed Meta input experience.
@export var openxr_simultaneous_hands_and_controllers := false
@export_range(0.5, 10.0, 0.5) var native_headset_present_timeout := 2.5
