center_offset :: (container_size: s32, content_size: s32) -> s32
{
    return (container_size - content_size) / 2;
}

left_corner :: (p: Vector2, s: Vector2) -> Vector2
{
    result: Vector2;
    result.x = p.x - (s.x * 0.5);
    result.y = p.y - (s.y * 0.5);

    return result;
}

point_in_rect :: (p: Vector2, rect: Rectangle) -> bool
{
    if p.x < rect.x
    {
        return false;
    }

    if p.x > rect.x + rect.width
    {
        return false;
    }

    if p.y < rect.y 
    {
        return false;
    }

    if p.y > rect.y + rect.height
    {
        return false;
    }

    return true;
}

move_toward :: (current: float, target: float, max_delta: float) -> float
{
    delta := target - current;
    return current + clamp(delta, -max_delta, max_delta);
}