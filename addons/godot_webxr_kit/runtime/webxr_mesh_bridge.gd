extends Node3D

## Bridges WebXR mesh-detection (the headset's scene/room mesh) into Godot.
## Injects a JavaScript frame hook at runtime (no custom HTML shell needed)
## that mirrors the lifecycle of the immersive-web mesh-detection sample:
## every session frame, chunks the platform stops reporting are dropped
## immediately, geometry is re-copied only when a chunk's lastChangedTime
## advances, and poses refresh continuously. Godot polls that store and
## renders ALL chunks as ONE merged mesh (a room scan can be 500+ small
## patches on Android XR - per-chunk nodes cost hundreds of draws and lag
## the platform's chunk churn).
##
## Requirements:
## - The session must be requested with the "mesh-detection" feature
##   (webxr_bootstrap.gd adds it as optional).
## - Place this node under your XROrigin3D so mesh poses (which are in the
##   session's reference space) land in the same space as tracked nodes.
##
## Renderer-agnostic: works on the WebGL and WebGPU paths alike.

signal mesh_added(id: int, semantic_label: String)
signal mesh_removed(id: int)

## Chunks are tracked (and collidable) regardless; this only controls the
## translucent visualization. Toggle at runtime with set_visualize().
@export var auto_visualize := false
## Alpha 0.5: translucent enough to read the real wall through it, strong
## enough to stay visible over bright passthrough (0.25 sat below the
## perception threshold on Galaxy XR's display).
@export var mesh_color := Color(0.08, 0.72, 1.0, 0.5)
## Scene-understanding view: per-label tints plus a floating semantic word
## (wall/floor/ceiling/table/...) at each chunk's center. Toggle with
## set_labels().
@export var show_labels := false
@export var generate_collision := false
## The platform store updates every frame; this only paces the JS->Godot
## transfer. Payloads are deltas, so a fast poll stays cheap.
@export var poll_interval := 0.25

## Preloaded so the shader baker can precompile it for web/WebGPU exports.
const MESH_MATERIAL := preload("res://addons/godot_webxr_kit/runtime/depth_mesh_material.tres")
const PUNCH_MATERIAL := preload("res://addons/godot_webxr_kit/runtime/mesh_punch_material.tres")

const LABEL_COLORS := {
	"wall": Color(0.30, 0.65, 1.00),
	"ceiling": Color(0.75, 0.55, 1.00),
	"floor": Color(0.35, 0.90, 0.55),
	"table": Color(1.00, 0.70, 0.25),
	"couch": Color(1.00, 0.45, 0.45),
	"door": Color(0.95, 0.90, 0.35),
	"window": Color(0.40, 0.95, 0.95),
}
const LABEL_COLOR_OTHER := Color(0.80, 0.80, 0.80)

var occlusion_enabled := false

var _webxr: XRInterface
var _poll_accum := 0.0
var _installed := false
# id -> { verts: PackedVector3Array (chunk-local), idx: PackedInt32Array,
#         xform: Transform3D, label: String }
var _chunks := {}
var _bodies := {}
var _label_nodes := {}
var _material: StandardMaterial3D
var _merged: MeshInstance3D
var _render_dirty := false
var _rebuild_cooldown := 0.0

func _ready() -> void:
	if not OS.has_feature("web") or not Engine.has_singleton("JavaScriptBridge"):
		set_process(false)
		return
	_webxr = XRServer.find_interface("WebXR")
	if _webxr:
		_webxr.session_started.connect(_on_session_started)
		_webxr.session_ended.connect(_on_session_ended)
	add_to_group("webxr_mesh_bridge")
	# Duplicate of a baked .tres; the tint is a uniform, so the baked
	# shader hash is kept.
	_material = MESH_MATERIAL.duplicate() as StandardMaterial3D
	_material.albedo_color = mesh_color
	_merged = MeshInstance3D.new()
	_merged.name = "MergedRoomMesh"
	# A scan overlay shouldn't darken the scene, and a room-sized shadow
	# caster multiplies the frame's draw count by the cascade count.
	_merged.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_merged.visible = false
	add_child(_merged)
	_install_js_hook()

func _install_js_hook() -> void:
	if _installed:
		return
	_installed = true
	var js := Engine.get_singleton("JavaScriptBridge")
	js.eval("""
(function () {
	if (window.GodotWebXRMeshBridge) { return; }
	const bridge = { meshes: {}, seq: 0, refType: 'local-floor', _ref: null, _refPending: false, harvest: false };
	window.GodotWebXRMeshBridge = bridge;
	const orig = XRSession.prototype.requestAnimationFrame;
	XRSession.prototype.requestAnimationFrame = function (cb) {
		return orig.call(this, function (t, frame) {
			try {
				bridge.meshProp = (frame.detectedMeshes !== undefined) ? ('set:' + frame.detectedMeshes.size) : 'ABSENT';
				if (!bridge._ref && !bridge._refPending) {
					bridge._refPending = true;
					frame.session.requestReferenceSpace(bridge.refType)
						.then((r) => { bridge._ref = r; })
						.catch(() => { bridge._refPending = false; });
				}
				if (bridge.harvest && frame.detectedMeshes && bridge._ref) {
					const live = new Set();
					frame.detectedMeshes.forEach((mesh) => {
						let id = mesh.__gwmbId;
						if (id === undefined) { id = ++bridge.seq; mesh.__gwmbId = id; }
						let rec = bridge.meshes[id];
						if (!rec) { rec = {}; bridge.meshes[id] = rec; }
						if (rec.changed !== mesh.lastChangedTime) {
							rec.changed = mesh.lastChangedTime;
							rec.vertices = Array.from(mesh.vertices);
							rec.indices = Array.from(mesh.indices);
							rec.label = mesh.semanticLabel || '';
							rec.dirty = true;
						}
						const pose = frame.getPose(mesh.meshSpace, bridge._ref);
						if (pose) {
							const m = pose.transform.matrix;
							const o = rec.matrix;
							// Skip no-op pose updates so polls only carry deltas.
							if (!o || Math.abs(o[12] - m[12]) + Math.abs(o[13] - m[13]) + Math.abs(o[14] - m[14]) + Math.abs(o[0] - m[0]) + Math.abs(o[5] - m[5]) > 5e-3) {
								rec.matrix = Array.from(m);
								rec.moved = true;
							}
						}
						live.add(id);
					});
					// Drop chunks the platform stopped reporting - but with a
					// short grace: Quest's browser lets meshes flicker out of
					// the per-frame set briefly (immediate reaping emptied the
					// whole scan there), while Android XR retires ids for good.
					// 1.5s rides out the flicker without letting Android XR's
					// id churn pile up visible duplicates.
					for (const id in bridge.meshes) {
						const rec2 = bridge.meshes[id];
						if (live.has(Number(id))) {
							rec2.unseenSince = 0;
						} else {
							if (!rec2.unseenSince) { rec2.unseenSince = t; }
							if (t - rec2.unseenSince > 1500) { rec2.gone = true; }
						}
					}
				}
			} catch (e) { /* never break the app's frame loop */ }
			cb(t, frame);
		});
	};
}())
""", true)

func _on_session_started() -> void:
	# Match the hook's reference space to the one Godot's session got, so
	# mesh poses and tracked-node poses share one space.
	var js := Engine.get_singleton("JavaScriptBridge")
	var ref_type: String = _webxr.reference_space_type
	if not ref_type.is_empty():
		js.eval("window.GodotWebXRMeshBridge && (window.GodotWebXRMeshBridge.refType = %s, window.GodotWebXRMeshBridge._ref = null, window.GodotWebXRMeshBridge._refPending = false);" % JSON.stringify(ref_type), true)
	set_process(true)
	# Recreate the visualization material with the session: some browsers
	# (Galaxy XR Chrome's WebGPU binding) don't reliably apply updates made
	# during a session to GPU resources created before it; a fresh material
	# per session keeps the tint dependable.
	_material = MESH_MATERIAL.duplicate() as StandardMaterial3D
	_material.albedo_color = mesh_color
	_apply_render_mode()
	_sync_harvest_gate()

func _on_session_ended() -> void:
	set_process(false)
	# Scene data is session-scoped; drop stale geometry on exit.
	Engine.get_singleton("JavaScriptBridge").eval("window.GodotWebXRMeshBridge && (window.GodotWebXRMeshBridge.meshes = {});", true)
	for id in _chunks.keys():
		_drop_chunk(id)
	_render_dirty = true
	# Forced: processing stops with the session, so a throttled rebuild
	# would never run and the scan would stay painted on the flat page.
	_rebuild_merged(true)

func get_surface_count() -> int:
	return _chunks.size()

func set_visualize(p_enabled: bool) -> void:
	auto_visualize = p_enabled
	if p_enabled:
		occlusion_enabled = false
		_refresh_gpu_geometry()
	_apply_render_mode()

## Scene-understanding view: floating semantic words (independent of the
## mesh visualization; combine with set_visualize for tinted surfaces too).
func set_labels(p_enabled: bool) -> void:
	show_labels = p_enabled
	if p_enabled:
		_refresh_gpu_geometry()
	_apply_render_mode()

## Room-mesh occlusion: the merged mesh draws an alpha punch (depth-tested),
## so passthrough shows wherever the scanned room is closer than virtual
## content. Static geometry only; sensor-depth occlusion supersedes this
## where the browser supports it.
func set_occlusion(p_enabled: bool) -> void:
	occlusion_enabled = p_enabled
	if p_enabled:
		auto_visualize = false
		_refresh_gpu_geometry()
	_apply_render_mode()

## Re-harvest every chunk so geometry is rebuilt with fresh GPU buffers;
## restores the scan on browsers that lost resources created while a
## session was starting up.
func _refresh_gpu_geometry() -> void:
	Engine.get_singleton("JavaScriptBridge").eval("""
(function () {
	const bridge = window.GodotWebXRMeshBridge;
	if (!bridge) { return; }
	for (const id in bridge.meshes) { bridge.meshes[id].changed = -1; }
}())
""", true)

func _apply_render_mode() -> void:
	_sync_harvest_gate()
	_render_dirty = true
	_rebuild_merged(true)

## The frame hook copies geometry only while something consumes it; an idle
## bridge costs (nearly) nothing per frame.
func _sync_harvest_gate() -> void:
	var active := auto_visualize or occlusion_enabled or show_labels or generate_collision
	Engine.get_singleton("JavaScriptBridge").eval(
		"window.GodotWebXRMeshBridge && (window.GodotWebXRMeshBridge.harvest = %s);" % ("true" if active else "false"), true)

func get_status() -> String:
	var js := Engine.get_singleton("JavaScriptBridge")
	var prop_str := str(js.eval("window.GodotWebXRMeshBridge ? String(window.GodotWebXRMeshBridge.meshProp) : 'NO BRIDGE'", true))
	if _chunks.size() > 0:
		var mode := "hidden"
		if occlusion_enabled:
			mode = "occluding"
		elif show_labels:
			mode = "labeled"
		elif auto_visualize:
			mode = "shown"
		return "Room mesh: %d surface(s), %s." % [_chunks.size(), mode]
	if prop_str == "ABSENT":
		return "Room mesh unsupported by this browser."
	if prop_str.begins_with("set:"):
		return "No room scan available yet."
	return "Room mesh: waiting for an immersive session."

func _process(delta: float) -> void:
	_rebuild_cooldown = maxf(0.0, _rebuild_cooldown - delta)
	_poll_accum += delta
	if _poll_accum < poll_interval:
		return
	_poll_accum = 0.0
	_poll_meshes()

func _poll_meshes() -> void:
	if not (auto_visualize or occlusion_enabled or show_labels or generate_collision):
		return
	var js := Engine.get_singleton("JavaScriptBridge")
	var payload = js.eval("""
(function () {
	const bridge = window.GodotWebXRMeshBridge;
	if (!bridge) { return '{}'; }
	const out = {};
	for (const id in bridge.meshes) {
		const rec = bridge.meshes[id];
		if (rec.gone) {
			out[id] = { gone: 1 };
			delete bridge.meshes[id];
			continue;
		}
		if (rec.dirty) {
			out[id] = { m: rec.matrix, l: rec.label, v: rec.vertices, i: rec.indices };
		} else if (rec.moved) {
			out[id] = { m: rec.matrix };
		}
		rec.dirty = false;
		rec.moved = false;
	}
	return JSON.stringify(out);
}())
""", true)
	if typeof(payload) != TYPE_STRING or payload.is_empty() or payload == "{}":
		return
	var parsed = JSON.parse_string(payload)
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	for id_str in parsed.keys():
		var rec: Dictionary = parsed[id_str]
		var id := int(id_str)
		if rec.has("gone"):
			_drop_chunk(id)
			continue
		if rec.has("v"):
			_store_chunk(id, rec)
		elif rec.has("m") and _chunks.has(id):
			_chunks[id]["xform"] = _matrix_to_transform(rec["m"])
			_render_dirty = true
	_rebuild_merged()

func _store_chunk(id: int, rec: Dictionary) -> void:
	var verts: Array = rec["v"]
	var indices: Array = rec["i"]
	var positions := PackedVector3Array()
	positions.resize(verts.size() / 3)
	for i in positions.size():
		positions[i] = Vector3(verts[i * 3], verts[i * 3 + 1], verts[i * 3 + 2])
	var idx := PackedInt32Array()
	idx.resize(indices.size())
	for i in indices.size():
		idx[i] = int(indices[i])

	var is_new := not _chunks.has(id)
	_chunks[id] = {
		"verts": positions,
		"idx": idx,
		"xform": _matrix_to_transform(rec["m"]) if rec.has("m") else (_chunks[id]["xform"] if not is_new else Transform3D.IDENTITY),
		"label": String(rec.get("l", "")),
	}
	_render_dirty = true

	if generate_collision:
		_rebuild_collision(id)
	if is_new:
		mesh_added.emit(id, String(rec.get("l", "")))

func _drop_chunk(id: int) -> void:
	if not _chunks.has(id):
		return
	_chunks.erase(id)
	if _bodies.has(id):
		_bodies[id].queue_free()
		_bodies.erase(id)
	_render_dirty = true
	mesh_removed.emit(id)

func _rebuild_collision(id: int) -> void:
	if _bodies.has(id):
		_bodies[id].queue_free()
	var chunk: Dictionary = _chunks[id]
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var concave := ConcavePolygonShape3D.new()
	var verts: PackedVector3Array = chunk["verts"]
	var idx: PackedInt32Array = chunk["idx"]
	var faces := PackedVector3Array()
	faces.resize(idx.size())
	for i in idx.size():
		faces[i] = verts[idx[i]]
	concave.set_faces(faces)
	shape.shape = concave
	body.add_child(shape)
	add_child(body)
	body.transform = chunk["xform"]
	_bodies[id] = body

## One ArrayMesh for the whole scan: chunk transforms baked into vertices,
## per-label vertex colors carried so the labeled view is a single draw too.
func _rebuild_merged(p_force := false) -> void:
	if not _render_dirty:
		return
	var mesh_on := auto_visualize or occlusion_enabled
	_merged.visible = mesh_on
	if not mesh_on:
		# Free the GPU geometry; an invisible room-sized mesh should cost
		# nothing.
		_merged.mesh = null
	if not show_labels:
		for key in _label_nodes.keys():
			_label_nodes[key].queue_free()
		_label_nodes.clear()
	if not mesh_on and not show_labels:
		_render_dirty = false
		return
	# Rebaking 50k+ vertices is not free; ride out chunk-churn bursts.
	if _rebuild_cooldown > 0.0 and not p_force:
		return
	_render_dirty = false
	_rebuild_cooldown = 1.0

	var seen_labels := {}
	if show_labels:
		for id in _chunks:
			var chunk: Dictionary = _chunks[id]
			var verts: PackedVector3Array = chunk["verts"]
			var label: String = chunk["label"]
			if verts.size() == 0 or label.is_empty():
				continue
			var xf: Transform3D = chunk["xform"]
			var centroid := Vector3.ZERO
			for i in verts.size():
				centroid += verts[i]
			var center: Vector3 = xf * (centroid / verts.size())
			# Cluster words on a coarse grid: one label per ~1.2m cell per
			# semantic type, or a word per chunk floods the view (and the
			# frame) on platforms that stream hundreds of small chunks.
			var cell := "%s:%d:%d:%d" % [label, roundi(center.x / 1.2), roundi(center.y / 1.2), roundi(center.z / 1.2)]
			if not seen_labels.has(cell):
				seen_labels[cell] = true
				_update_label(cell, label, center, LABEL_COLORS.get(label, LABEL_COLOR_OTHER))
		for key in _label_nodes.keys():
			if not seen_labels.has(key):
				_label_nodes[key].queue_free()
				_label_nodes.erase(key)

	if not mesh_on:
		return
	var total_verts := 0
	var total_idx := 0
	for id in _chunks:
		total_verts += (_chunks[id]["verts"] as PackedVector3Array).size()
		total_idx += (_chunks[id]["idx"] as PackedInt32Array).size()
	if total_idx == 0:
		_merged.mesh = null
		return

	var positions := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	positions.resize(total_verts)
	colors.resize(total_verts)
	indices.resize(total_idx)
	var vbase := 0
	var ibase := 0
	for id in _chunks:
		var chunk: Dictionary = _chunks[id]
		var verts: PackedVector3Array = chunk["verts"]
		var idx: PackedInt32Array = chunk["idx"]
		var xf: Transform3D = chunk["xform"]
		var label: String = chunk["label"]
		# Tinted surfaces when the label view runs alongside the mesh view.
		var color: Color = LABEL_COLORS.get(label, LABEL_COLOR_OTHER) if show_labels else Color.WHITE
		for i in verts.size():
			positions[vbase + i] = xf * verts[i]
			colors[vbase + i] = color
		for i in idx.size():
			indices[ibase + i] = idx[i] + vbase
		vbase += verts.size()
		ibase += idx.size()

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = positions
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_merged.mesh = mesh
	_merged.material_override = PUNCH_MATERIAL if occlusion_enabled else _material

func _update_label(key: String, text: String, world_pos: Vector3, color: Color) -> void:
	var label_node: Label3D
	if _label_nodes.has(key):
		label_node = _label_nodes[key]
	else:
		label_node = Label3D.new()
		label_node.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label_node.no_depth_test = false
		label_node.pixel_size = 0.002
		label_node.font_size = 48
		label_node.outline_size = 8
		add_child(label_node)
		_label_nodes[key] = label_node
	label_node.text = text
	label_node.modulate = color
	label_node.position = world_pos

func _matrix_to_transform(m: Array) -> Transform3D:
	# Column-major WebXR matrix -> Transform3D (both are meters, Y-up):
	# matrix columns are the world-space basis axes. Verified against a
	# device-dumped 'floor' patch pose (its local normal must map to world
	# up, and does under this reading).
	return Transform3D(
		Vector3(m[0], m[1], m[2]),
		Vector3(m[4], m[5], m[6]),
		Vector3(m[8], m[9], m[10]),
		Vector3(m[12], m[13], m[14]))
