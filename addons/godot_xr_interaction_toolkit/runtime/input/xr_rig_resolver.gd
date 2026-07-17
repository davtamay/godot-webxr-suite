class_name XRRigResolver
extends Object

## Self-wiring for rig references: a block dropped ANYWHERE in a scene finds
## the XR rig by itself - walk up for an XROrigin3D first (drop it under the
## rig and that wins), then scan the scene. This is what makes blocks
## drag-and-drop: NodePath exports become optional overrides, not setup.


static func find_origin(from: Node) -> XROrigin3D:
	var cursor := from
	while cursor != null:
		if cursor is XROrigin3D:
			return cursor
		cursor = cursor.get_parent()
	if not from.is_inside_tree():
		return null
	var root := from.get_tree().current_scene
	if root == null:
		return null
	if root is XROrigin3D:
		return root
	var found := root.find_children("*", "XROrigin3D", true, false)
	return found[0] if not found.is_empty() else null


static func find_camera(from: Node) -> XRCamera3D:
	var origin := find_origin(from)
	if origin == null:
		return null
	var found := origin.find_children("*", "XRCamera3D", true, false)
	return found[0] if not found.is_empty() else null


## The rig's aim controller for a hand (0 = left, 1 = right). Prefers aim/
## default-pose nodes so helper anchors (e.g. grip model anchors) never win.
static func find_controller(from: Node, hand: int) -> XRController3D:
	var origin := find_origin(from)
	if origin == null:
		return null
	var tracker_name: StringName = &"left_hand" if hand == 0 else &"right_hand"
	var fallback: XRController3D = null
	for node in origin.find_children("*", "XRController3D", true, false):
		var controller := node as XRController3D
		if controller.tracker != tracker_name:
			continue
		if controller.pose == &"aim" or controller.pose == &"default":
			return controller
		if fallback == null:
			fallback = controller
	return fallback
