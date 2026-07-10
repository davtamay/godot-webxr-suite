class_name XRInteractionLayerMask
extends RefCounted

## Interaction-layer arbitration, deliberately decoupled from physics layers
## (mirrors Unity XRITK's Interaction Layer Mask vs physics layers split).

static func overlaps(layers_a: int, layers_b: int) -> bool:
    return (layers_a & layers_b) != 0
