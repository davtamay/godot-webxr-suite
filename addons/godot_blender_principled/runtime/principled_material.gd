class_name PrincipledMaterial
extends StandardMaterial3D

## Thin Blender-Principled-BSDF-named layer over StandardMaterial3D. Only aliases
## the inputs whose Godot name differs from Blender's; metallic/roughness/normal
## are native (names already match Blender, roughness is NOT inverted).

enum AlphaMode { OPAQUE, BLEND, MASK }

@export_group("Blender Principled")
@export var base_color := Color(0.8, 0.8, 0.8, 1.0): set = _set_base_color
@export_range(0.0, 4.0, 0.01, "or_greater") var normal_strength := 1.0: set = _set_normal_strength
@export var emission_color := Color(0, 0, 0, 1.0): set = _set_emission_color
@export_range(0.0, 100.0, 0.01, "or_greater") var emission_strength := 1.0: set = _set_emission_strength
@export var alpha_mode := AlphaMode.OPAQUE: set = _set_alpha_mode
@export_range(1.0, 3.0, 0.01) var ior := 1.5: set = _set_ior

func _init() -> void:
    # Blender-matching defaults: dielectric, mid roughness, IOR 1.5 specular.
    # Must be _init(), not _ready(): a material is a Resource and never gets _ready().
    # NOTE: GDScript assigns an @export var's declared default straight to its
    # backing field WITHOUT calling the setter, so alias defaults do not reach the
    # native field on their own. Sync base_color -> albedo_color here (the grey
    # default would otherwise render white). The other aliases intentionally leave
    # their native side at Godot's default (e.g. emission/normal stay disabled).
    metallic = 0.0
    roughness = 0.5
    metallic_specular = 0.5
    albedo_color = base_color

func _set_base_color(value: Color) -> void:
    base_color = value
    albedo_color = value

func _set_normal_strength(value: float) -> void:
    normal_strength = value
    normal_enabled = true
    normal_scale = value

func _set_emission_color(value: Color) -> void:
    emission_color = value
    emission_enabled = true
    emission = value

func _set_emission_strength(value: float) -> void:
    emission_strength = value
    emission_energy_multiplier = value

func _set_alpha_mode(value: AlphaMode) -> void:
    alpha_mode = value
    match value:
        AlphaMode.OPAQUE:
            transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
        AlphaMode.BLEND:
            transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
        AlphaMode.MASK:
            transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR

func _set_ior(value: float) -> void:
    ior = value
    # Godot 4's dielectric specular intensity is `metallic_specular` (there is no
    # scalar `specular` like Godot 3). ior 1.5 -> 0.5 (the Godot/Blender default).
    metallic_specular = clampf(pow((value - 1.0) / (value + 1.0), 2.0) / 0.08, 0.0, 1.0)
