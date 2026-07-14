class_name XRHandTeleportTrajectory
extends RefCounted

## Samples a hand-directed projectile curve and returns its first valid floor
## hit. This is input-provider agnostic: callers supply a world-space origin
## and direction derived from any hand source.

static func solve(
    start: Vector3,
    direction: Vector3,
    space_state: PhysicsDirectSpaceState3D,
    floor_height: float,
    speed: float,
    gravity: float,
    maximum_time: float,
    sample_count: int,
    collision_mask: int,
    minimum_surface_up: float
) -> Dictionary:
    var points := PackedVector3Array([start])
    var velocity := direction.normalized() * speed
    var previous := start
    var samples := maxi(sample_count, 4)
    for index in range(1, samples + 1):
        var time := maximum_time * float(index) / float(samples)
        var position := start + velocity * time + Vector3.DOWN * (0.5 * gravity * time * time)
        if space_state != null:
            var query := PhysicsRayQueryParameters3D.create(previous, position, collision_mask)
            query.collide_with_areas = false
            var hit := space_state.intersect_ray(query)
            if not hit.is_empty():
                var hit_position: Vector3 = hit["position"]
                var hit_normal: Vector3 = hit["normal"]
                points.append(hit_position)
                return {
                    "valid": hit_normal.dot(Vector3.UP) >= minimum_surface_up,
                    "target": hit_position + hit_normal * 0.025,
                    "normal": hit_normal,
                    "points": points,
                }
        if previous.y > floor_height and position.y <= floor_height:
            var denominator := position.y - previous.y
            var weight := 0.0 if is_zero_approx(denominator) else (floor_height - previous.y) / denominator
            var floor_hit := previous.lerp(position, clampf(weight, 0.0, 1.0))
            points.append(floor_hit)
            return {
                "valid": true,
                "target": floor_hit + Vector3.UP * 0.025,
                "normal": Vector3.UP,
                "points": points,
            }
        points.append(position)
        previous = position
    return {
        "valid": false,
        "target": points[points.size() - 1],
        "normal": Vector3.UP,
        "points": points,
    }
