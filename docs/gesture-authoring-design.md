# Gesture Authoring — Design (2026-07-16)

Toolkit-native hand-gesture system: recognize, author-by-recording, and drive
actions (locomotion first). Consumes ONLY engine `XRHandTracker` joints, so it
works on WebXR and OpenXR, on any device with hand tracking, with no addon or
platform dependencies.

## The data standard (agnostic by construction)

Everything speaks one vocabulary: **named, normalized hand features**, computed
by one extractor from raw joints:

| feature | meaning | range |
|---|---|---|
| `curl_thumb` .. `curl_pinky` | full-finger curl (0 = straight, 1 = fist) | 0..1 |
| `pinch_index` .. `pinch_pinky` | fingertip closeness to the thumb tip (1 = touching) | 0..1 |
| `spread_index_middle` .. `spread_ring_pinky` | angle between neighbours | 0..1 |
| `palm_up` | palm normal vs world up | -1..1 |
| `palm_toward_head` | palm normal vs the camera | -1..1 |

- A **gesture** (`XRHandGesture`, a `.tres` Resource) is just
  `{feature_name: (target, tolerance)}` + a hold time. New features extend the
  vocabulary without changing the format; unknown features are ignored, so
  resources stay forward/backward compatible.
- Palm orientation is computed **geometrically** (cross product of palm→index
  and palm→ring, chirality-corrected per hand) — no dependence on any
  runtime's joint axis conventions. Author once; both hands match.

## Prior art and the enhancements over it

- Unity XR Hands: per-finger curl/pinch/spread assets + debugger, but numbers
  are typed by hand, per-hand tuning, platform-SDK-bound.
- Meta ISDK: curl/flexion/abduction recognizers + Sequences (temporal) + a
  buried pose recorder; platform-SDK-bound.
- Ours: (1) portable by construction (engine joints); (2) **record-first
  authoring** — hold the pose, the recorder derives targets AND tolerances
  from your natural jitter; (3) hysteresis on every threshold + hold-time
  debounce (reliability); (4) auto-mirrored hands; (5) live per-feature debug
  HUD from day one.

## Blocks

1. `XRHandFeatureExtractor` (static) — joints → the feature dictionary. The
   single math home; recognizer, recorder, and debug HUD all consume it.
2. `XRHandGesture` (Resource) — the data standard above.
3. `XRGestureRecognizer` (Node block) — gestures in, `gesture_started/ended
   (name, hand)` out; hysteresis (tolerance widens while active), hold time,
   per-hand; optional debug HUD; preset library (point, fist, open palm,
   thumbs up).
4. `XRGestureRecorder` (Node block, Phase B) — countdown, sample window,
   derive a gesture resource, save.
5. `XRGestureLocomotionDriver` (Phase C) — maps gestures to XRLocomotion's
   intent API (point-to-aim teleport by default; mapping is data).
6. Sequences (Phase D) — temporal chaining of poses = swipes/microgestures.

## Phases

- **A (now):** extractor + resource + recognizer + presets + debug HUD,
  verified on-headset in the demo scene.
- **B:** the recorder (the authoring headline).
- **C:** XRLocomotion intent API + gesture→locomotion driver.
- **D:** sequences.

## PARKED (2026-07-17, resume marker)

Phases D/E parked by David to prioritize the poke interactor. When resuming:

- **Phase D - sequences/microgestures**: add `thumb_along_index` /
  `thumb_across_index` + contact features; sequence gestures as data (stages:
  conditions + motion delta + time window); record-first derivation from the
  captured time series. Target DELIBERATE swipes/taps (Meta's trained runtime
  model keeps the subtle at-rest microgestures - input ceiling: signals the
  joint estimator never resolves cannot be recovered downstream).
- **Phase E - learned micro-model (the catch-up path)**: the recorder already
  produces labeled feature time series; a tiny temporal classifier trained on
  recorded examples (per-user or shipped) closes much of the temporal-
  signature gap vs hand thresholds, runs trivially per frame, and inherits
  every upstream tracker improvement. Native microgesture events (Link has
  XR_META_hand_tracking_microgestures; vendors plugin does not wrap it yet)
  plug in as a premium provider through the same signal vocabulary.
