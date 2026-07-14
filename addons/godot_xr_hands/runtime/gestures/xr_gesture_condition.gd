class_name XRGestureCondition
extends Resource

## Authoring-facing condition. Runtime compilation can replace Resource graph
## traversal later without changing gesture assets.

@export var enabled := true

func evaluate(_features: XRHandFeatures) -> float:
    return 0.0
