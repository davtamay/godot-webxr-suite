class_name XRGestureStateMachine
extends RefCounted

## Temporal hysteresis shared by static and future dynamic recognizers.

enum State { INACTIVE, CANDIDATE, ACTIVE, RELEASING, COOLDOWN }
enum Transition { NONE, STARTED, PERFORMED, ENDED }

var state: State = State.INACTIVE
var score := 0.0
var state_time := 0.0

func reset() -> void:
    state = State.INACTIVE
    score = 0.0
    state_time = 0.0

func update(next_score: float, delta: float, definition: XRGestureDefinition) -> Transition:
    score = clampf(next_score, 0.0, 1.0)
    state_time += maxf(delta, 0.0)

    match state:
        State.INACTIVE:
            if score >= definition.activation_threshold:
                _enter(State.CANDIDATE)
                return Transition.STARTED
        State.CANDIDATE:
            if score < definition.release_threshold:
                _enter(State.INACTIVE)
                return Transition.ENDED
            if state_time >= definition.activation_time:
                _enter(State.ACTIVE)
                return Transition.PERFORMED
        State.ACTIVE:
            if score < definition.release_threshold:
                _enter(State.RELEASING)
        State.RELEASING:
            if score >= definition.activation_threshold:
                _enter(State.ACTIVE)
            elif state_time >= definition.release_time:
                _enter(State.COOLDOWN)
                return Transition.ENDED
        State.COOLDOWN:
            if state_time >= definition.cooldown and score < definition.release_threshold:
                _enter(State.INACTIVE)
    return Transition.NONE

func is_active() -> bool:
    return state == State.CANDIDATE or state == State.ACTIVE or state == State.RELEASING

func _enter(next_state: State) -> void:
    state = next_state
    state_time = 0.0
