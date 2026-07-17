@icon("res://addons/godot_xr_interaction_toolkit/icons/xr_highlight_affordance.svg")
class_name XRFeedbackTheme
extends Resource

## One styling resource for the scene-wide interaction feedback: what every
## interactable's hover/select looks, sounds, and feels like. Assign to an
## XRInteractionFeedback node; swap themes to restyle the whole scene. Unity
## announced (but has not shipped) a unified visuals/audio/haptics feedback
## system - this is that idea, themed and scene-wide.

@export_group("Visual")
@export var visual_enabled := true
## Tint colours for the auto-applied highlight (same look as
## XRHighlightAffordance - it IS one, deployed automatically).
@export var hover_color := Color(1.0, 0.9, 0.25)
@export var select_color := Color(0.28, 1.0, 0.55)
@export var activate_color := Color(0.18, 0.92, 1.0)
@export_range(0.0, 4.0, 0.05) var emission_energy := 0.65

@export_group("Audio")
@export var audio_enabled := true
@export var hover_sound: AudioStream = preload("res://addons/godot_xr_interaction_toolkit/runtime/feedback/feedback_hover.wav")
@export var select_sound: AudioStream = preload("res://addons/godot_xr_interaction_toolkit/runtime/feedback/feedback_select.wav")
@export_range(-40.0, 6.0, 0.5) var volume_db := -6.0

@export_group("Haptics")
@export var haptics_enabled := true
## Pulse strength (0-1) and duration (seconds) on hover-enter / select.
@export_range(0.0, 1.0, 0.05) var hover_amplitude := 0.2
@export_range(0.0, 0.5, 0.005) var hover_duration := 0.01
@export_range(0.0, 1.0, 0.05) var select_amplitude := 0.6
@export_range(0.0, 0.5, 0.005) var select_duration := 0.03
