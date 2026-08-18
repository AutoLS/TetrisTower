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

QUEUE_MARGIN_X :: 80; // clears the left wall, which otherwise clips the "NEXT" label
QUEUE_MARGIN_Y :: 20;
QUEUE_BOX_SIZE :: 90;
QUEUE_CELL_SIZE :: 16;

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

draw_game_over :: (screen_width: s32, screen_height: s32)
{
    text := "GAME OVER";
    font_size: s32 = 48;
    text_width := MeasureText(get_c_string(text), font_size);
    x := center_offset(screen_width, text_width);
    y := center_offset(screen_height, font_size);
    DrawText(get_c_string(text), x, y, font_size, RED);
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