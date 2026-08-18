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

// Auto: This is kinda expensive since we have to render each individual cell.. We can optimize it by rendering merged shapes but then we have to modify the textures and that's kinda pain in the ass...
draw_tetromino_cells :: (tex: Texture2D, type: Tetromino, body: *Rigid_Body, cell_size: float, src: Rectangle)
{
    cells := get_tetromino_cells(type);
    angle := quat_to_z_angle(body.orientation);

    min_r := 9999; max_r := -9999; min_c := 9999; max_c := -9999;
    for c : cells
    {
        min_r = min(min_r, cast(int)c.x); max_r = max(max_r, cast(int)c.x);
        min_c = min(min_c, cast(int)c.y); max_c = max(max_c, cast(int)c.y);
    }
    w := cast(float)(max_c - min_c + 1);
    h := cast(float)(max_r - min_r + 1);

    com_x := 0.0; com_y := 0.0;
    for c : cells
    {
        col := cast(int)c.y; row := cast(int)c.x;
        com_x += cast(float)(col - min_c) + 0.5 - w*0.5;
        com_y += cast(float)(max_r - row) + 0.5 - h*0.5;
    }
    com_x /= cast(float)cells.count;
    com_y /= cast(float)cells.count;

    for c : cells
    {
        col := cast(int)c.y; row := cast(int)c.x;

        cx := (cast(float)(col - min_c) + 0.5 - w*0.5 - com_x) * cell_size;
        cy := (cast(float)(max_r - row) + 0.5 - h*0.5 - com_y) * cell_size;

        center := body.position + rotate(body.orientation, Vector3.{ cx, cy, 0 });

        dest   := Rectangle.{ center.x, center.y, cell_size, cell_size };
        origin := Vector2.{ cell_size*0.5, cell_size*0.5 };

        DrawTexturePro(tex, src, dest, origin, angle, WHITE);
    }
}
