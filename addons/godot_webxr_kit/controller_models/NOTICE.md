# Controller model assets

The .glb models in these folders come from the WebXR Input Profiles
registry (https://github.com/immersive-web/webxr-input-profiles),
package @webxr-input-profiles/assets, MIT License (see LICENSE.md).
Profiles bundled: oculus-touch-v3 (Quest 2/3 family), samsung-galaxyxr,
generic-trigger-squeeze-thumbstick (fallback). Add more by dropping
<profile-id>/left.glb + right.glb folders here - XRInputModalityManager
resolves them by the profile ids the runtime reports.
