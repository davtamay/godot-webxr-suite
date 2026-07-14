class_name XRHandPoseSource
extends RefCounted

## Acquisition seam for WebXR, OpenXR, replay files, simulated hands, or a
## future native provider. Recognition code never references a runtime API.

func capture(_hand: int, _timestamp_usec: int, _target: XRHandFrame) -> bool:
    return false
