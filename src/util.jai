center_offset :: (container_size: s32, content_size: s32) -> s32
{
    return (container_size - content_size) / 2;
}

move_toward :: (current: float, target: float, max_delta: float) -> float
{
    delta := target - current;
    return current + clamp(delta, -max_delta, max_delta);
}