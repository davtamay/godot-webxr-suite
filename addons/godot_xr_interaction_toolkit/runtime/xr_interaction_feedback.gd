@icon("res://addons/godot_xr_interaction_toolkit/icons/xr_highlight_affordance.svg")
class_name XRInteractionFeedback
extends Node

## Scene-wide interaction feedback - visuals, audio, and haptics for EVERY
## interactable, with zero per-object setup. Unity deprecated its affordance
## system and announced a unified feedback system "in a future version"; this
## is that system, today, and scene-default instead of per-object:
##
## - VISUAL: each interactable automatically gets a highlight (the proven
##   XRHighlightAffordance, deployed at runtime) tinted from the theme.
## - AUDIO: hover tick + select click played AT the object (positional).
## - HAPTICS: pulse on the interacting hand's controller (our signals carry
##   the interactor, so the correct hand buzzes). Bare hands no-op silently.
##
## Authorship: styling lives in ONE XRFeedbackTheme resource - swap it to
## restyle the whole scene. Per-object control: give an object its OWN
## affordance child (Highlight Affordance block) and the system skips it -
## default everywhere, override anywhere. Rig-default: ships in WebXRRig.

const _HIGHLIGHT_SCRIPT := preload("res://addons/godot_xr_interaction_toolkit/runtime/xr_highlight_affordance.gd")
const _DEFAULT_THEME := preload("res://addons/godot_xr_interaction_toolkit/runtime/feedback/default_feedback_theme.tres")

@export var enabled := true
## Styling for all three channels; swap to restyle the scene.
@export var theme: XRFeedbackTheme
## Skip objects that carry their own affordance child (their author already
## chose a look). Off = system feedback stacks on top anyway.
@export var respect_object_affordances := true

var _wired := {}       # interactable -> true (avoid double-wiring)
var _audio := {}       # interactable -> AudioStreamPlayer3D


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	if theme == null:
		theme = _DEFAULT_THEME
	_wire_manager.call_deferred()


func _wire_manager() -> void:
	var manager := get_tree().get_first_node_in_group(XRInteractionManager.GROUP_NAME)
	if manager == null:
		push_warning("XRInteractionFeedback: no XRInteractionManager in the scene.")
		return
	manager.interactable_registered.connect(_on_interactable_registered)
	for interactable in manager.get_interactables():
		_on_interactable_registered(interactable)


func _on_interactable_registered(interactable) -> void:
	if not enabled or interactable == null or _wired.has(interactable):
		return
	# A UI canvas panel forwards hover/click to the 2D buttons on its surface -
	# those highlight themselves. Glowing the whole panel (and ticking on hover)
	# is wrong, so skip the auto-feedback for it entirely.
	if _is_ui_canvas(interactable):
		return
	if respect_object_affordances and _has_own_affordance(interactable):
		return
	_wired[interactable] = true

	if theme.visual_enabled:
		var highlight: Node = _HIGHLIGHT_SCRIPT.new()
		highlight.name = "AutoFeedbackHighlight"
		highlight.hover_color = theme.hover_color
		highlight.select_color = theme.select_color
		highlight.activate_color = theme.activate_color
		highlight.emission_energy = theme.emission_energy
		interactable.add_child(highlight)

	if theme.audio_enabled or theme.haptics_enabled:
		interactable.hover_entered.connect(_on_hover.bind(interactable))
		interactable.select_entered.connect(_on_select.bind(interactable))


## A UI canvas panel (XRUICanvasInteractable, incl. subclasses) whose surface has
## its own interactive controls - no whole-object highlight.
func _is_ui_canvas(interactable: Node) -> bool:
	var script: Script = interactable.get_script()
	while script:
		if script.get_global_name() == &"XRUICanvasInteractable":
			return true
		script = script.get_base_script()
	return false


func _has_own_affordance(interactable: Node) -> bool:
	for child in interactable.get_children():
		var script: Script = child.get_script()
		while script:
			if script.get_global_name() == &"XRHighlightAffordance":
				return true
			script = script.get_base_script()
	return false


func _on_hover(interactor, interactable) -> void:
	if theme.audio_enabled and theme.hover_sound:
		_play(interactable, theme.hover_sound)
	if theme.haptics_enabled:
		_pulse(interactor, theme.hover_amplitude, theme.hover_duration)


func _on_select(interactor, interactable) -> void:
	if theme.audio_enabled and theme.select_sound:
		_play(interactable, theme.select_sound)
	if theme.haptics_enabled:
		_pulse(interactor, theme.select_amplitude, theme.select_duration)


func _play(interactable: Node, stream: AudioStream) -> void:
	var player: AudioStreamPlayer3D = _audio.get(interactable)
	if player == null or not is_instance_valid(player):
		player = AudioStreamPlayer3D.new()
		player.volume_db = theme.volume_db
		player.max_distance = 12.0
		interactable.add_child(player)
		_audio[interactable] = player
	player.stream = stream
	player.play()


## Buzz the controller of the hand that caused the event. Interactors carry a
## hand id; the rig resolver finds that hand's controller. Bare hands (no
## controller live) no-op silently.
func _pulse(interactor, amplitude: float, duration: float) -> void:
	if interactor == null or not ("hand" in interactor):
		return
	var controller := XRRigResolver.find_controller(self, int(interactor.hand))
	if controller and controller.get_is_active():
		controller.trigger_haptic_pulse("haptic", 0.0, amplitude, duration, 0.0)
