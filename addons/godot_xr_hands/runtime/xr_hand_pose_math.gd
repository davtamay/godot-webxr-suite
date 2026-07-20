class_name XRHandPoseMath
extends RefCounted

## Shared hand-pose math - the single home for turning a SAVED pose (an
## XRHandGesture .tres: a recorded joint snapshot, or curl conditions) into
## per-joint transforms. The Gesture Studio simulator and the grab-point
## Preview Hand both use this so a pose looks identical everywhere.
##
## It is convention-agnostic: the caller passes a BIND as wrist-relative
## Transform3Ds per joint (measured however that caller represents its
## skeleton), and gets wrist-relative posed transforms back. Positions AND
## authored orientations rotate together, so the skin stays coherent.

const FINGER_NAMES := ["thumb", "index", "middle", "ring", "pinky"]
const FINGER_CHAINS := [
	[XRHandTracker.HAND_JOINT_THUMB_METACARPAL, XRHandTracker.HAND_JOINT_THUMB_PHALANX_PROXIMAL, XRHandTracker.HAND_JOINT_THUMB_PHALANX_DISTAL, XRHandTracker.HAND_JOINT_THUMB_TIP],
	[XRHandTracker.HAND_JOINT_INDEX_FINGER_METACARPAL, XRHandTracker.HAND_JOINT_INDEX_FINGER_PHALANX_PROXIMAL, XRHandTracker.HAND_JOINT_INDEX_FINGER_PHALANX_INTERMEDIATE, XRHandTracker.HAND_JOINT_INDEX_FINGER_PHALANX_DISTAL, XRHandTracker.HAND_JOINT_INDEX_FINGER_TIP],
	[XRHandTracker.HAND_JOINT_MIDDLE_FINGER_METACARPAL, XRHandTracker.HAND_JOINT_MIDDLE_FINGER_PHALANX_PROXIMAL, XRHandTracker.HAND_JOINT_MIDDLE_FINGER_PHALANX_INTERMEDIATE, XRHandTracker.HAND_JOINT_MIDDLE_FINGER_PHALANX_DISTAL, XRHandTracker.HAND_JOINT_MIDDLE_FINGER_TIP],
	[XRHandTracker.HAND_JOINT_RING_FINGER_METACARPAL, XRHandTracker.HAND_JOINT_RING_FINGER_PHALANX_PROXIMAL, XRHandTracker.HAND_JOINT_RING_FINGER_PHALANX_INTERMEDIATE, XRHandTracker.HAND_JOINT_RING_FINGER_PHALANX_DISTAL, XRHandTracker.HAND_JOINT_RING_FINGER_TIP],
	[XRHandTracker.HAND_JOINT_PINKY_FINGER_METACARPAL, XRHandTracker.HAND_JOINT_PINKY_FINGER_PHALANX_PROXIMAL, XRHandTracker.HAND_JOINT_PINKY_FINGER_PHALANX_INTERMEDIATE, XRHandTracker.HAND_JOINT_PINKY_FINGER_PHALANX_DISTAL, XRHandTracker.HAND_JOINT_PINKY_FINGER_TIP],
]

const PRESET_DIR := "res://addons/godot_xr_hands/runtime/gesture_studio/presets"
const USER_DIR := "user://gestures"


## Every saved pose (XRHandGesture .tres) from the shipped presets and the
## user's recordings: [{name, resource}].
static func list_poses() -> Array:
	var out: Array = []
	for dir_path in [PRESET_DIR, USER_DIR]:
		var dir := DirAccess.open(dir_path)
		if dir == null:
			continue
		for file in dir.get_files():
			if not file.ends_with(".tres"):
				continue
			var res := load(dir_path.path_join(file))
			if res == null:
				continue
			var pose_name: String = res.get("gesture_name") if res.get("gesture_name") else file.get_basename()
			out.append({"name": pose_name, "resource": res})
	return out


## Per-finger curl HINGE axes measured from the bind (palm_normal x bone; the
## thumb is opposition, across the palm), chirality-corrected by the thumb side.
static func measure_curl_axes(bind: Array) -> Array:
	var index_o: Vector3 = (bind[XRHandTracker.HAND_JOINT_INDEX_FINGER_METACARPAL] as Transform3D).origin
	var pinky_o: Vector3 = (bind[XRHandTracker.HAND_JOINT_PINKY_FINGER_METACARPAL] as Transform3D).origin
	var thumb_o: Vector3 = (bind[XRHandTracker.HAND_JOINT_THUMB_METACARPAL] as Transform3D).origin
	var normal := index_o.cross(pinky_o).normalized()
	if normal.dot(thumb_o - (index_o + pinky_o) * 0.5) > 0.0:
		normal = -normal
	var axes: Array = []
	for f in FINGER_CHAINS.size():
		var chain: Array = FINGER_CHAINS[f]
		var mc: Vector3 = (bind[chain[0]] as Transform3D).origin
		var proximal: Vector3 = (bind[chain[1]] as Transform3D).origin
		var bone := (proximal - mc).normalized()
		if f == 0:
			axes.append(bone.cross((pinky_o - mc).normalized()).normalized())
		else:
			axes.append(normal.cross(bone).normalized())
	return axes


## Turn a saved pose into wrist-relative joint transforms. Recorded snapshots go
## through reframe+retarget; condition-only presets synthesize an FK curl.
static func pose_joints(bind: Array, curl_axes: Array, gesture: Object, hand := 1) -> Array:
	var snapshot: PackedVector3Array = gesture.get("joint_snapshot") if gesture.get("joint_snapshot") is PackedVector3Array else PackedVector3Array()
	if snapshot.size() >= XRHandTracker.HAND_JOINT_MAX:
		var recorded: Variant = gesture.get("recorded_hand")
		var native: int = recorded if recorded is int and recorded >= 0 else 1
		var positions := snapshot if hand == native else mirrored(snapshot)
		return rel_from_recorded(bind, positions)
	return fk_pose(bind, curl_axes, curls_from_conditions(gesture.get("conditions")))


static func curls_from_conditions(conditions: Variant) -> Dictionary:
	var curls := {}
	if conditions is Dictionary:
		for f in FINGER_NAMES:
			var key := "curl_%s" % f
			if (conditions as Dictionary).has(key):
				curls[f] = ((conditions as Dictionary)[key] as Vector2).x
	return curls


## Same-axis FK: each finger's bends rotate around its bind hinge axis with an
## accumulating angle, positions and orientations together. `curls` is per-finger
## 0..1 (missing = 0.15 relaxed, matching the studio's open hand).
static func fk_pose(bind: Array, curl_axes: Array, curls: Dictionary) -> Array:
	var out := bind.duplicate()
	for f in FINGER_CHAINS.size():
		var chain: Array = FINGER_CHAINS[f]
		var curl: float = curls.get(FINGER_NAMES[f], 0.15)
		var total := curl * (1.7 if f == 0 else 3.6)
		var per_joint := total / maxf(chain.size() - 2, 1.0)
		var axis: Vector3 = curl_axes[f]
		var angle := 0.0
		for i in range(1, chain.size()):
			angle += per_joint
			var rotation := Basis(axis, angle)
			var previous_out: Transform3D = out[chain[i - 1]]
			var bind_step: Vector3 = (bind[chain[i]] as Transform3D).origin - (bind[chain[i - 1]] as Transform3D).origin
			out[chain[i]] = Transform3D(rotation * (bind[chain[i]] as Transform3D).basis,
					previous_out.origin + Basis(axis, angle - per_joint) * bind_step)
	return out


## Recorded snapshots are POSITIONS only, in the recorder's wrist frame; align
## both wrist frames the SAME way (removing the free chirality sign), reframe the
## positions, then RETARGET each authored bind frame onto the recorded bone
## direction so recorded and FK poses share one convention.
static func rel_from_recorded(bind: Array, positions: PackedVector3Array) -> Array:
	var f_rec := measure_wrist_frame(func(j): return positions[j])
	var f_bind := measure_wrist_frame(func(j): return (bind[j] as Transform3D).origin)
	var convert := f_bind * f_rec.inverse()
	var wrist_pos := positions[XRHandTracker.HAND_JOINT_WRIST]
	var reframed := PackedVector3Array()
	reframed.resize(positions.size())
	for joint in positions.size():
		reframed[joint] = convert * (positions[joint] - wrist_pos)
	var rel: Array = []
	rel.resize(positions.size())
	for joint in positions.size():
		rel[joint] = Transform3D((bind[joint] as Transform3D).basis, reframed[joint])
	for chain in FINGER_CHAINS:
		for i in range(chain.size() - 1):
			var joint: int = chain[i]
			var bind_bone: Vector3 = ((bind[chain[i + 1]] as Transform3D).origin - (bind[joint] as Transform3D).origin)
			var rec_bone: Vector3 = reframed[chain[i + 1]] - reframed[joint]
			rel[joint] = Transform3D(rotation_between(bind_bone, rec_bone) * (bind[joint] as Transform3D).basis, reframed[joint])
		var tip: int = chain[chain.size() - 1]
		var parent: int = chain[chain.size() - 2]
		rel[tip] = Transform3D((rel[parent] as Transform3D).basis, reframed[tip])
	return rel


static func rotation_between(from_dir: Vector3, to_dir: Vector3) -> Basis:
	var a := from_dir.normalized()
	var b := to_dir.normalized()
	if a.length_squared() < 0.000001 or b.length_squared() < 0.000001:
		return Basis.IDENTITY
	var dot := clampf(a.dot(b), -1.0, 1.0)
	if dot > 0.9999:
		return Basis.IDENTITY
	var axis := a.cross(b)
	if axis.length_squared() < 0.000001:
		axis = a.cross(Vector3.UP)
		if axis.length_squared() < 0.000001:
			axis = a.cross(Vector3.RIGHT)
	return Basis(axis.normalized(), acos(dot))


## Wrist frame from joint positions, measured identically for recorded and bind
## data (fingers = middle-metacarpal dir, palm normal = index x pinky with the
## thumb-side correction). The shared correction removes the free chirality sign.
static func measure_wrist_frame(get_pos: Callable) -> Basis:
	var wrist: Vector3 = get_pos.call(XRHandTracker.HAND_JOINT_WRIST)
	var index: Vector3 = get_pos.call(XRHandTracker.HAND_JOINT_INDEX_FINGER_METACARPAL)
	var pinky: Vector3 = get_pos.call(XRHandTracker.HAND_JOINT_PINKY_FINGER_METACARPAL)
	var thumb: Vector3 = get_pos.call(XRHandTracker.HAND_JOINT_THUMB_METACARPAL)
	var normal := (index - wrist).cross(pinky - wrist).normalized()
	if normal.dot(thumb - (index + pinky) * 0.5) > 0.0:
		normal = -normal
	var fingers: Vector3 = (get_pos.call(XRHandTracker.HAND_JOINT_MIDDLE_FINGER_METACARPAL) - wrist).normalized()
	return basis_from_bone(fingers, normal)


static func basis_from_bone(y_dir: Vector3, reference_normal: Vector3) -> Basis:
	if y_dir.length_squared() < 0.000001:
		return Basis.IDENTITY
	var x_axis := reference_normal.cross(y_dir)
	if x_axis.length_squared() < 0.000001:
		x_axis = y_dir.cross(Vector3.UP)
		if x_axis.length_squared() < 0.000001:
			x_axis = Vector3.RIGHT
	x_axis = x_axis.normalized()
	var z_axis := x_axis.cross(y_dir).normalized()
	return Basis(x_axis, y_dir, z_axis)


static func mirrored(snapshot: PackedVector3Array) -> PackedVector3Array:
	var flipped := PackedVector3Array()
	flipped.resize(snapshot.size())
	for i in snapshot.size():
		var p := snapshot[i]
		flipped[i] = Vector3(-p.x, p.y, p.z)
	return flipped
