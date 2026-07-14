class_name XRMicrogestureSource
extends Node

## Canonical, runtime-independent microgesture event contract.
##
## Providers may classify gestures from normalized joints, native runtime
## events, recordings, simulation, or another input backend. Consumers see
## the same wearer-relative vocabulary and never depend on that provider.

enum Gesture { LEFT, RIGHT, FORWARD, BACKWARD, TAP }

signal gesture_candidate(gesture: Gesture, hand: int, progress: float)
signal gesture_performed(gesture: Gesture, hand: int, confidence: float)

func gesture_name(gesture: int) -> String:
    if gesture < 0 or gesture >= Gesture.size():
        return "unknown"
    return Gesture.keys()[gesture].to_lower()

func reset() -> void:
    pass
