class_name XRFeatureRangeCondition
extends XRGestureCondition

## Scores 1 inside the authored range and fades to 0 over falloff outside it.

@export var feature: XRHandFeatures.Feature = XRHandFeatures.Feature.PINCH_DISTANCE
@export var minimum := 0.0
@export var maximum := 1.0
@export_range(0.0001, 2.0, 0.001) var falloff := 0.1

func evaluate(features: XRHandFeatures) -> float:
    if not enabled or features == null or not features.valid:
        return 0.0
    var value := features.get_feature(feature)
    if value >= minimum and value <= maximum:
        return 1.0
    var distance := minimum - value if value < minimum else value - maximum
    return 1.0 - clampf(distance / maxf(falloff, 0.0001), 0.0, 1.0)
