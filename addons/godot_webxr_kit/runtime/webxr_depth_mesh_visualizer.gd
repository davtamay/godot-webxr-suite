extends Node3D

## Builds a low-resolution debug surface from the browser WebXR CPU depth bridge.
## Attach under XROrigin3D so bridge points in WebXR reference space render locally.

const GROUP_NAME := "webxr_depth_mesh_visualizer"

@export_range(0.01, 10.0, 0.01, "or_greater") var min_depth_meters := 0.05
@export_range(0.1, 20.0, 0.1, "or_greater") var max_depth_meters := 6.0
@export_range(0.01, 5.0, 0.01, "or_greater") var max_triangle_depth_delta := 0.45
@export var mesh_color := Color(0.08, 0.72, 1.0, 0.36)
@export var bounds_color := Color(1.0, 0.78, 0.12, 1.0)
@export var show_mesh := true
@export var show_bounds := true

var _js_bridge
var _mesh_instance: MeshInstance3D
var _bounds_instance: MeshInstance3D
var _mesh_material: StandardMaterial3D
var _bounds_material: StandardMaterial3D

func _ready() -> void:
    add_to_group(GROUP_NAME)
    if OS.has_feature("web") and Engine.has_singleton("JavaScriptBridge"):
        _js_bridge = Engine.get_singleton("JavaScriptBridge")
    _create_visuals()

func capture_depth_mesh() -> String:
    var snapshot := _latest_depth_snapshot()
    return _build_depth_mesh_from_snapshot(snapshot)

func clear_depth_mesh() -> void:
    if _mesh_instance:
        _mesh_instance.mesh = null
        _mesh_instance.visible = false
    if _bounds_instance:
        _bounds_instance.mesh = null
        _bounds_instance.visible = false

func _latest_depth_snapshot() -> Dictionary:
    if _js_bridge == null:
        return {"error": "Depth mesh needs the WebXR web export."}

    var json_text = _js_bridge.eval("JSON.stringify(window.CompanyWebXRDepthBridge && window.CompanyWebXRDepthBridge.latest || null)", true)
    var parsed = JSON.parse_string(str(json_text))
    if typeof(parsed) != TYPE_DICTIONARY:
        return {"error": "Depth bridge unavailable. Reload the custom WebXR shell."}
    return parsed

func _build_depth_mesh_from_snapshot(snapshot: Dictionary) -> String:
    var samples = snapshot.get("samples", [])
    var sample_width := int(snapshot.get("sampleWidth", 0))
    var sample_height := int(snapshot.get("sampleHeight", 0))
    var error := str(snapshot.get("error", ""))

    if typeof(samples) != TYPE_ARRAY or sample_width <= 1 or sample_height <= 1:
        clear_depth_mesh()
        return "Depth mesh unavailable.\n%s" % (error if not error.is_empty() else "Enter AR and wait for a depth frame.")

    if samples.size() < sample_width * sample_height:
        clear_depth_mesh()
        return "Depth mesh unavailable.\nIncomplete depth sample."

    var points: Array[Vector3] = []
    var depths: Array[float] = []
    var valid: Array[bool] = []
    points.resize(sample_width * sample_height)
    depths.resize(sample_width * sample_height)
    valid.resize(sample_width * sample_height)

    var min_bounds := Vector3(INF, INF, INF)
    var max_bounds := Vector3(-INF, -INF, -INF)
    var valid_count := 0

    for index in range(sample_width * sample_height):
        var sample = samples[index]
        if typeof(sample) != TYPE_DICTIONARY:
            valid[index] = false
            continue

        var depth := float(sample.get("d", 0.0))
        var is_valid := bool(sample.get("valid", false)) and depth >= min_depth_meters and depth <= max_depth_meters
        valid[index] = is_valid
        depths[index] = depth
        if not is_valid:
            continue

        var point := Vector3(
            float(sample.get("x", 0.0)),
            float(sample.get("y", 0.0)),
            float(sample.get("z", 0.0))
        )
        points[index] = point
        min_bounds = Vector3(minf(min_bounds.x, point.x), minf(min_bounds.y, point.y), minf(min_bounds.z, point.z))
        max_bounds = Vector3(maxf(max_bounds.x, point.x), maxf(max_bounds.y, point.y), maxf(max_bounds.z, point.z))
        valid_count += 1

    if valid_count == 0:
        clear_depth_mesh()
        return "Depth mesh: no valid depth samples.\n%s" % (error if not error.is_empty() else "Move in AR and try again.")

    var vertices := PackedVector3Array()
    for y in range(sample_height - 1):
        for x in range(sample_width - 1):
            var i0 := y * sample_width + x
            var i1 := i0 + 1
            var i2 := i0 + sample_width
            var i3 := i2 + 1
            _append_depth_triangle(vertices, points, depths, valid, i0, i1, i2)
            _append_depth_triangle(vertices, points, depths, valid, i1, i3, i2)

    if vertices.is_empty():
        _set_mesh_vertices(PackedVector3Array())
    else:
        _set_mesh_vertices(vertices)
    _set_bounds(min_bounds, max_bounds)

    var triangle_count := vertices.size() / 3
    var size := max_bounds - min_bounds
    return "Depth mesh: %d pts, %d tris\nBounds: %.2f x %.2f x %.2f m\n%s %s" % [
        valid_count,
        triangle_count,
        size.x,
        size.y,
        size.z,
        str(snapshot.get("usage", "unknown")),
        str(snapshot.get("dataFormat", "unknown")),
    ]

func _append_depth_triangle(vertices: PackedVector3Array, points: Array[Vector3], depths: Array[float], valid: Array[bool], a: int, b: int, c: int) -> void:
    if not valid[a] or not valid[b] or not valid[c]:
        return

    var min_depth := minf(depths[a], minf(depths[b], depths[c]))
    var max_depth := maxf(depths[a], maxf(depths[b], depths[c]))
    if max_depth - min_depth > max_triangle_depth_delta:
        return

    vertices.append(points[a])
    vertices.append(points[b])
    vertices.append(points[c])

func _create_visuals() -> void:
    _mesh_material = StandardMaterial3D.new()
    _mesh_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    _mesh_material.albedo_color = mesh_color
    _mesh_material.emission_enabled = true
    _mesh_material.emission = mesh_color
    _mesh_material.emission_energy_multiplier = 0.55
    _mesh_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    _mesh_material.cull_mode = BaseMaterial3D.CULL_DISABLED

    _bounds_material = StandardMaterial3D.new()
    _bounds_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    _bounds_material.albedo_color = bounds_color
    _bounds_material.emission_enabled = true
    _bounds_material.emission = bounds_color
    _bounds_material.emission_energy_multiplier = 1.4

    _mesh_instance = MeshInstance3D.new()
    _mesh_instance.name = "DepthMeshSurface"
    _mesh_instance.visible = false
    _mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    add_child(_mesh_instance)

    _bounds_instance = MeshInstance3D.new()
    _bounds_instance.name = "DepthMeshBounds"
    _bounds_instance.visible = false
    _bounds_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    add_child(_bounds_instance)

func _set_mesh_vertices(vertices: PackedVector3Array) -> void:
    if _mesh_instance == null:
        return
    if vertices.is_empty():
        _mesh_instance.mesh = null
        _mesh_instance.visible = false
        return

    var arrays := []
    arrays.resize(Mesh.ARRAY_MAX)
    arrays[Mesh.ARRAY_VERTEX] = vertices

    var mesh := ArrayMesh.new()
    mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
    _mesh_instance.mesh = mesh
    _mesh_instance.set_surface_override_material(0, _mesh_material)
    _mesh_instance.visible = show_mesh

func _set_bounds(min_bounds: Vector3, max_bounds: Vector3) -> void:
    if _bounds_instance == null:
        return

    var a := Vector3(min_bounds.x, min_bounds.y, min_bounds.z)
    var b := Vector3(max_bounds.x, min_bounds.y, min_bounds.z)
    var c := Vector3(max_bounds.x, max_bounds.y, min_bounds.z)
    var d := Vector3(min_bounds.x, max_bounds.y, min_bounds.z)
    var e := Vector3(min_bounds.x, min_bounds.y, max_bounds.z)
    var f := Vector3(max_bounds.x, min_bounds.y, max_bounds.z)
    var g := Vector3(max_bounds.x, max_bounds.y, max_bounds.z)
    var h := Vector3(min_bounds.x, max_bounds.y, max_bounds.z)

    var vertices := PackedVector3Array([
        a, b, b, c, c, d, d, a,
        e, f, f, g, g, h, h, e,
        a, e, b, f, c, g, d, h,
    ])
    var arrays := []
    arrays.resize(Mesh.ARRAY_MAX)
    arrays[Mesh.ARRAY_VERTEX] = vertices

    var mesh := ArrayMesh.new()
    mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arrays)
    _bounds_instance.mesh = mesh
    _bounds_instance.set_surface_override_material(0, _bounds_material)
    _bounds_instance.visible = show_bounds
