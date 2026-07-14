class_name XRGestureDefinition
extends Resource

## Serializable authoring model. Conditions are combined with strict ALL/min
## scoring so the weakest requirement is obvious in diagnostics.

@export var gesture_id: StringName = &"gesture"
@export var display_name := "Gesture"
@export_enum("Any:-1", "Left:0", "Right:1") var hand := -1
@export_range(0.0, 1.0, 0.01) var activation_threshold := 0.82
@export_range(0.0, 1.0, 0.01) var release_threshold := 0.62
@export_range(0.0, 2.0, 0.01) var activation_time := 0.06
@export_range(0.0, 2.0, 0.01) var release_time := 0.06
@export_range(0.0, 5.0, 0.01) var cooldown := 0.20
@export_range(0.0, 1.0, 0.01) var minimum_tracking_quality := 0.45
@export var conditions: Array[XRGestureCondition] = []

func evaluate(features: XRHandFeatures) -> float:
    if features == null or not features.valid or features.tracking_quality < minimum_tracking_quality:
        return 0.0
    if conditions.is_empty():
        return 0.0
    var score := 1.0
    for condition in conditions:
        if condition != null and condition.enabled:
            score = minf(score, condition.evaluate(features))
    return score
