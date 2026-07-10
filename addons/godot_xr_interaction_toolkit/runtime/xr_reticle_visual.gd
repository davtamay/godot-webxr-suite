class_name XRReticleVisual
extends MeshInstance3D

## Hit-point reticle for an XRRayInteractor parent. Visible only when the ray
## hits geometry; grows when the hit is a hoverable interactable.

@export var color := Color(1.0, 0.9, 0.25, 1.0)
@export var hit_radius := 0.02
@export var hover_radius := 0.04

var _ray: Node

func _ready() -> void:
    _ray = get_parent()
    if _ray == null or not _ray.has_method("get_ray_state"):
        _ray = null
        push_warning("%s: parent does not provide get_ray_state()." % name)
    top_level = true
    cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

    var sphere := SphereMesh.new()
    sphere.radius = 1.0
    sphere.height = 2.0
    sphere.radial_segments = 16
    sphere.rings = 8
    mesh = sphere

    var material := StandardMaterial3D.new()
    material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    material.albedo_color = color
    material.emission_enabled = true
    material.emission = color
    material_override = material

func _process(_delta: float) -> void:
    var state: Dictionary = _ray.get_ray_state() if _ray else {}
    var should_show: bool = state.get("valid", false) and state.get("hit", false)
    visible = should_show
    if not should_show:
        return

    var radius := hover_radius if state.get("hovered") != null else hit_radius
    var end: Vector3 = state["end"]
    global_transform = Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * radius), end)
