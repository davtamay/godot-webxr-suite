extends Node3D

## Bridges WebXR mesh-detection (the headset's scene/room mesh, e.g. Quest
## Space Setup geometry) into Godot. Injects a JavaScript frame hook at
## runtime (no custom HTML shell required) that harvests
## XRFrame.detectedMeshes, then polls it and maintains one MeshInstance3D
## (and optional collision body) per detected mesh under this node.
##
## Requirements:
## - The session must be requested with the "mesh-detection" feature
##   (webxr_bootstrap.gd adds it as optional).
## - Place this node under your XROrigin3D so mesh poses (which are in the
##   session's reference space) land in the same space as tracked nodes.
##
## Renderer-agnostic: works on the WebGL and WebGPU paths alike.

signal mesh_added(id: int, instance: MeshInstance3D, semantic_label: String)
signal mesh_updated(id: int, instance: MeshInstance3D)

@export var auto_visualize := true
@export var generate_collision := false
@export var poll_interval := 0.75

## Preloaded so the shader baker can precompile it for web/WebGPU exports.
const MESH_MATERIAL := preload("res://addons/godot_webxr_kit/runtime/depth_mesh_material.tres")

var _webxr: XRInterface
var _poll_accum := 0.0
var _installed := false
var _instances := {}

func _ready() -> void:
	if not OS.has_feature("web") or not Engine.has_singleton("JavaScriptBridge"):
		set_process(false)
		return
	_webxr = XRServer.find_interface("WebXR")
	if _webxr:
		_webxr.session_started.connect(_on_session_started)
		_webxr.session_ended.connect(_on_session_ended)
	_install_js_hook()

func _install_js_hook() -> void:
	if _installed:
		return
	_installed = true
	var js := Engine.get_singleton("JavaScriptBridge")
	js.eval("""
(function () {
	if (window.GodotWebXRMeshBridge) { return; }
	const bridge = { meshes: {}, seq: 0, refType: 'local-floor', _ref: null, _refPending: false };
	window.GodotWebXRMeshBridge = bridge;
	const orig = XRSession.prototype.requestAnimationFrame;
	XRSession.prototype.requestAnimationFrame = function (cb) {
		return orig.call(this, function (t, frame) {
			try {
				if (!bridge._ref && !bridge._refPending) {
					bridge._refPending = true;
					frame.session.requestReferenceSpace(bridge.refType)
						.then((r) => { bridge._ref = r; })
						.catch(() => { bridge._refPending = false; });
				}
				if (frame.detectedMeshes && bridge._ref) {
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
						if (pose) { rec.matrix = Array.from(pose.transform.matrix); }
						rec.seen = t;
					});
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

func _on_session_ended() -> void:
	set_process(false)

func _process(delta: float) -> void:
	_poll_accum += delta
	if _poll_accum < poll_interval:
		return
	_poll_accum = 0.0
	_poll_meshes()

func _poll_meshes() -> void:
	var js := Engine.get_singleton("JavaScriptBridge")
	var payload = js.eval("""
(function () {
	const bridge = window.GodotWebXRMeshBridge;
	if (!bridge) { return '{}'; }
	const out = {};
	for (const id in bridge.meshes) {
		const rec = bridge.meshes[id];
		out[id] = rec.dirty
			? { m: rec.matrix, l: rec.label, v: rec.vertices, i: rec.indices }
			: { m: rec.matrix };
		rec.dirty = false;
	}
	return JSON.stringify(out);
}())
""", true)
	if typeof(payload) != TYPE_STRING or payload.is_empty():
		return
	var parsed = JSON.parse_string(payload)
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	for id_str in parsed.keys():
		var rec: Dictionary = parsed[id_str]
		var id := int(id_str)
		if rec.has("v"):
			_build_mesh(id, rec)
		if rec.has("m") and _instances.has(id):
			_instances[id].transform = _matrix_to_transform(rec["m"])

func _build_mesh(id: int, rec: Dictionary) -> void:
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

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = positions
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

	var is_new := not _instances.has(id)
	var instance: MeshInstance3D
	if is_new:
		instance = MeshInstance3D.new()
		instance.name = "DetectedMesh%d" % id
		instance.visible = auto_visualize
		instance.material_override = MESH_MATERIAL
		add_child(instance)
		_instances[id] = instance
	else:
		instance = _instances[id]
		for child in instance.get_children():
			child.queue_free()
	instance.mesh = mesh

	if generate_collision:
		var body := StaticBody3D.new()
		var shape := CollisionShape3D.new()
		var concave := ConcavePolygonShape3D.new()
		concave.set_faces(_faces_from_indexed(positions, idx))
		shape.shape = concave
		body.add_child(shape)
		instance.add_child(body)

	if is_new:
		mesh_added.emit(id, instance, String(rec.get("l", "")))
	else:
		mesh_updated.emit(id, instance)

func _faces_from_indexed(positions: PackedVector3Array, idx: PackedInt32Array) -> PackedVector3Array:
	var faces := PackedVector3Array()
	faces.resize(idx.size())
	for i in idx.size():
		faces[i] = positions[idx[i]]
	return faces

func _matrix_to_transform(m: Array) -> Transform3D:
	# Column-major WebXR matrix -> Transform3D (both are meters, Y-up).
	return Transform3D(
		Vector3(m[0], m[1], m[2]),
		Vector3(m[4], m[5], m[6]),
		Vector3(m[8], m[9], m[10]),
		Vector3(m[12], m[13], m[14]))
