# Architecture Decision (2026-07-17, rev. 2): Unity-parity packages, one gesture system

David delegated the call, then caught a flaw in rev. 1 (dissolving
godot_xr_hands): Unity separates XR Hands from XRI for reasons that DO
apply here - chiefly OPTIONALITY (controller-only projects skip hands
entirely and the toolkit still works) and provider-side gesture
recognition (Unity's hand shapes/poses live in XR Hands, not XRI).
One Unity reason does NOT apply: platform abstraction - Godot core
already ships XRHandTracker across OpenXR/WebXR.

**End-state = FOUR addons, Unity-parity roles:**
- `godot_webxr_kit` - platform & embodiment: sessions, rig, adapters,
  modality, controller models.
- `godot_xr_hands` - THE hands provider, rebuilt as ours: hand
  visualization (already lives here) + OUR gesture system (extractor,
  XRHandGesture resources, recognizer, recorder, ghost hand, presets,
  Gesture Studio demo - MOVED from the toolkit) + future sequences /
  microgestures / learned micro-model.
- `godot_xr_interaction_toolkit` - pure consumer: interactors (ray,
  direct, poke, socket), locomotion, UI, keyboard, affordances. Its
  microgesture-locomotion driver soft-depends on the hands addon
  (inert without - controller sticks still drive the same visuals).
- `godot_webxr_scene_understanding` - perception.

**Unchanged from rev. 1:** ONE gesture system (ours - it has the
authoring story, the runtime-agnostic data standard, and the roadmap);
Sol's recognition stack and its superseded demos retire; namespace
collisions (XRHandFeatureExtractor) end. Sol coordination is over -
godot_xr_hands is ours to rebuild.

**Migration (each step shippable + headset-verifiable):**
1. Move toolkit/runtime/gestures/* (+ studio demo, presets, dock
   entries) into godot_xr_hands; update preload paths; launcher entry
   repoints. Visualizer stays put (it is already home).
2. Phase D builds sequences/microgestures in the hands addon; the
   locomotion driver swaps its soft-dep constant to our recognizer;
   Micro-Gestures menu entry repoints.
3. Remove the superseded old recognition stack + demos; our extractor
   reclaims the XRHandFeatureExtractor class name.

**Sorting rules (put in the README):** providers produce input data
(joints, gestures) - that is godot_xr_hands; consumers turn input into
interaction - that is the toolkit; consumers depend softly downward,
providers never know consumers exist. Rig-default is for PASSIVE
capabilities only; continuous recognizers with side effects are opt-in.
