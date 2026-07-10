class_name StrictParityEnvironment
extends RefCounted

## Builds render environments for Blender<->Godot material comparison.
## parity_environment() mirrors the user's validated "Strict Parity" method
## (Blender Standard view transform, 0.05 flat ambient, GI off) so material
## differences are real, not lighting differences.

static func parity_environment() -> Environment:
    var env := Environment.new()
    env.background_mode = Environment.BG_COLOR
    env.background_color = Color(0.05, 0.05, 0.05)
    env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
    env.ambient_light_color = Color(0.05, 0.05, 0.05)
    env.ambient_light_energy = 1.0
    env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
    env.ssao_enabled = false
    env.ssil_enabled = false
    env.sdfgi_enabled = false
    env.glow_enabled = false
    return env

static func nice_environment() -> Environment:
    var env := Environment.new()
    env.background_mode = Environment.BG_COLOR
    env.background_color = Color(0.35, 0.37, 0.4)
    env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
    env.ambient_light_color = Color(0.2, 0.2, 0.2)
    env.ambient_light_energy = 1.0
    env.tonemap_mode = Environment.TONE_MAPPER_AGX
    env.glow_enabled = true
    return env
