class_name XRInteractorLineVisual
extends MeshInstance3D

## Straight-line beam for an XRRayInteractor parent. Draws in world space
## (top_level), so the interactor's transform never bends the visual.

@export var color := Color(0.7, 0.88, 1.0, 0.85)

var _ray: Node
var _line_mesh := ImmediateMesh.new()

func _ready() -> void:
    _ray = get_parent()
    if _ray == null or not _ray.has_method("get_ray_state"):
        _ray = null
        push_warning("%s: parent does not provide get_ray_state()." % name)
    mesh = _line_mesh
    top_level = true
    cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

    var material := StandardMaterial3D.new()
    material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    material.albedo_color = color
    material.emission_enabled = true
    material.emission = color
    material_override = material

func _process(_delta: float) -> void:
    _line_mesh.clear_surfaces()
    var state: Dictionary = _ray.get_ray_state() if _ray else {}
    if not state.get("valid", false):
        visible = false
        return

    var from_point: Vector3 = state["origin"]
    var to_point: Vector3 = state["end"]
    if from_point.distance_squared_to(to_point) < 0.000001:
        visible = false
        return

    visible = true
    global_transform = Transform3D.IDENTITY
    _line_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
    _line_mesh.surface_add_vertex(from_point)
    _line_mesh.surface_add_vertex(to_point)
    _line_mesh.surface_end()
