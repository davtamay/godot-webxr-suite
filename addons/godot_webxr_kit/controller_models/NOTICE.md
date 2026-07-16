# Controller model assets

Only the generic fallback model ships in the addon (MIT, from the WebXR
Input Profiles registry - see LICENSE.md). Device-specific models
(oculus-touch-v3, samsung-galaxyxr, ...) are FETCHED AT RUNTIME from the
registry CDN by XRInputModalityManager, cached in user://, and their
materials remapped onto a pre-baked template so they render on WebGPU
exports. Self-host by pointing model_repository_url at your own copy of
@webxr-input-profiles/assets/dist/profiles.
