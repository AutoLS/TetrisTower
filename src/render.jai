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
draw_tetromino_cells :: (tex: Texture2D, type: Tetromino, body: *Rigid_Body, cell_size: float, src: Rectangle, offset: Vector3 = .{}, alpha: u8 = 255)
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

        center := body.position + offset + rotate(body.orientation, Vector3.{ cx, cy, 0 });

        dest   := Rectangle.{ center.x, center.y, cell_size, cell_size };
        origin := Vector2.{ cell_size*0.5, cell_size*0.5 };

        DrawTexturePro(tex, src, dest, origin, angle, .{255, 255, 255, alpha});
    }
}

draw_convex_shape_outline :: (shape: Convex_Shape, offset: Vector3 = .{}, color: Color = WHITE, thickness: float = 2.0)
{
    count := shape.global_vertices.count;
    for i : 0..count-1
    {
        a := shape.global_vertices[i];
        b := shape.global_vertices[(i + 1) % count];
        DrawLineEx(.{offset.x + a.x, offset.y + a.y}, .{offset.x + b.x, offset.y + b.y}, thickness, color);
    }
}

QUEUE_MARGIN_X :: 80; // clears the left wall, which otherwise clips the "NEXT" label
QUEUE_MARGIN_Y :: 20;
QUEUE_BOX_SIZE :: 90;
QUEUE_CELL_SIZE :: 16;

HUD_MARGIN :: 20;

// A piece's cell layout is a fixed constant per Tetromino type, so it's computed once here
// and reused, instead of calling get_tetromino_cells (which does fresh temp allocations) every frame.
tetromino_preview_cells: [7] [..] Vector2;
tetromino_preview_cells_ready: bool;

get_cached_tetromino_cells :: (type: Tetromino) -> [..] Vector2
{
    if !tetromino_preview_cells_ready
    {
        for i : 0..tetromino_preview_cells.count-1
        {
            source := get_tetromino_cells(cast(Tetromino)i);
            cached: [..] Vector2;
            for source array_add(*cached, it);
            tetromino_preview_cells[i] = cached;
        }
        tetromino_preview_cells_ready = true;
    }

    return tetromino_preview_cells[cast(int)type];
}

center_offset :: (container_size: s32, content_size: s32) -> s32
{
    return (container_size - content_size) / 2;
}

draw_piece_queue :: (queue: Piece_Queue)
{
    DrawText(get_c_string("NEXT"), QUEUE_MARGIN_X, QUEUE_MARGIN_Y, 24, BLACK);

    for i : 0..QUEUE_PREVIEW_COUNT-1
    {
        if i >= queue.pieces.count break;

        box_y: s32 = xx (QUEUE_MARGIN_Y + 36 + i * QUEUE_BOX_SIZE);
        DrawRectangleLines(QUEUE_MARGIN_X, box_y, QUEUE_BOX_SIZE, QUEUE_BOX_SIZE, GRAY);

        cells := get_cached_tetromino_cells(queue.pieces[i]);
        bounds := get_cell_bounds(cells);

        offset_x := center_offset(QUEUE_BOX_SIZE, xx (bounds.width * QUEUE_CELL_SIZE));
        offset_y := center_offset(QUEUE_BOX_SIZE, xx (bounds.height * QUEUE_CELL_SIZE));

        for c : cells
        {
            px: s32 = xx (QUEUE_MARGIN_X + offset_x + (cast(int)c.y - bounds.min_c) * QUEUE_CELL_SIZE);
            py: s32 = xx (box_y + offset_y + (cast(int)c.x - bounds.min_r) * QUEUE_CELL_SIZE);
            DrawRectangle(px, py, QUEUE_CELL_SIZE - 2, QUEUE_CELL_SIZE - 2, DARKGRAY);
        }
    }
}

draw_text_right_aligned :: (text: string, y: s32, font_size: s32, color: Color, screen_width: s32)
{
    width := MeasureText(get_c_string(text), font_size);
    DrawText(get_c_string(text), screen_width - width - HUD_MARGIN, y, font_size, color);
}

draw_hud :: (game: *Game)
{
    font_size: s32 = 24;

    hp_text := tprint("HP: %", game.hp);
    draw_text_right_aligned(hp_text, HUD_MARGIN, font_size, BLACK, game.screen_width);

    height_cells := cast(int)(get_tower_top(game) / CELL_SIZE);
    height_text := tprint("Height: %", height_cells);
    draw_text_right_aligned(height_text, HUD_MARGIN + font_size + 6, font_size, BLACK, game.screen_width);

    if is_game_over(game)
    {
        game_over_font_size: s32 = 48;
        msg := "GAME OVER";
        msg_width := MeasureText(get_c_string(msg), game_over_font_size);
        msg_x := center_offset(game.screen_width, msg_width);
        msg_y := center_offset(game.screen_height, game_over_font_size);
        DrawText(get_c_string(msg), msg_x, msg_y, game_over_font_size, RED);
    }
}