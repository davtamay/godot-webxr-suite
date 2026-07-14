@tool
extends EditorPlugin

## Runtime scripts use class_name and work with the editor plugin disabled.
## The gesture pipeline depends only on engine XRHandTracker data plus the
## toolkit resolver; the visualizer's browser bridge remains optional.
