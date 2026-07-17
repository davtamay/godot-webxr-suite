@icon("res://addons/godot_xr_interaction_toolkit/icons/xr_gesture_recognizer.svg")
class_name XRHandGesture
extends Resource

## One hand gesture as DATA: named normalized features (see
## XRHandFeatureExtractor) with a target and tolerance each. Runtime-agnostic
## by construction - nothing here knows joints or platforms, and unknown
## feature names are ignored by the recognizer, so resources stay compatible
## as the feature vocabulary grows.
##
## Author by hand in the inspector (Unity-style), or record one live with the
## gesture recorder block - it derives targets AND tolerances from how steady
## your hand actually is.

## Name emitted by the recognizer's signals.
@export var gesture_name := ""

## feature -> Vector2(target, tolerance). The gesture matches while EVERY
## listed feature is within tolerance of its target. Features not listed do
## not matter (a "point" doesn't care about your thumb).
## Curl/pinch/spread features are 0..1; palm_up / palm_toward_head are -1..1.
@export var conditions: Dictionary[String, Vector2] = {}

## The pose must hold this long before gesture_started fires (debounce).
@export_range(0.0, 1.0, 0.01) var min_hold_seconds := 0.08

## Extra tolerance while ACTIVE (hysteresis): the gesture releases only after
## drifting this far past its entry tolerance, killing boundary flicker.
@export_range(0.0, 0.5, 0.01) var release_tolerance_bonus := 0.08


func matches(features: Dictionary, active: bool) -> bool:
	if conditions.is_empty() or features.is_empty():
		return false
	for feature in conditions:
		if not features.has(feature):
			return false
		var target_tolerance := conditions[feature]
		var tolerance := target_tolerance.y + (release_tolerance_bonus if active else 0.0)
		if absf((features[feature] as float) - target_tolerance.x) > tolerance:
			return false
	return true
