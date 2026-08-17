draw_convex_shape :: (shape: Convex_Shape, offset: Vector3 = .{}, color: Color = WHITE) 
{
    for 0..(shape.global_vertices.count - 3) 
    {
        DrawTriangle(v1=Vector2.{ offset.x + shape.global_vertices[0].x,      (offset.y + shape.global_vertices[0].y) },
                     v2=Vector2.{ offset.x + shape.global_vertices[it + 2].x, (offset.y + shape.global_vertices[it + 2].y) },
                     v3=Vector2.{ offset.x + shape.global_vertices[it + 1].x, (offset.y + shape.global_vertices[it + 1].y) },
                     color);
    }
}