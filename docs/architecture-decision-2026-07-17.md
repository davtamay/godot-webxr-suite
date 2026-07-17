# Architecture Decision (2026-07-17): three addons, one gesture system

David delegated the call and lifted the godot_xr_hands coordination
constraint. Decision:

**End-state = THREE addons:**
- `godot_webxr_kit` - platform & embodiment: sessions, rig, adapters,
  modality, controller models, HAND VISUALIZATION (absorbed from
  godot_xr_hands; XRHandsMount already fronts it).
- `godot_xr_interaction_toolkit` - ALL interaction: interactors (ray,
  direct, poke, socket), THE gesture system (Studio: recognition +
  record-first authoring + agnostic feature vocabulary), locomotion, UI,
  keyboard, affordances.
- `godot_webxr_scene_understanding` - perception.

`godot_xr_hands` dissolves after salvage. Rationale: two recognition
stacks, a namespace collision (XRHandFeatureExtractor), a soft-dependency
bridge crossing an ownership boundary that no longer exists, and
overlapping demos are coordination scar tissue, not architecture. Our
gesture system is canonical: it has the authoring story (recorder, .tres,
strictness), the runtime-agnostic data standard, and the roadmap
(sequences -> microgestures -> learned micro-model).

**Migration (each step shippable + headset-verifiable):**
1. Move hand_visualizer into the kit; XRHandsMount swaps one preload path.
2. Phase D builds sequences/microgestures IN OUR system (their thumb math
   as reference); the microgesture locomotion driver swaps its soft-dep
   constant from their recognizer to ours; menu entry repoints.
3. Remove the superseded recognition stack + demos; reclaim class names.

**Sorting rule for future blocks** (put in the README when written):
providers produce input data (joints, gestures, platform events);
consumers turn input into interaction. Consumers may depend softly
downward; providers never know consumers exist. Poke = consumer (pokes
with controller tips too); recognition = provider layer inside the
toolkit's gesture module until step 3 settles the final home.
