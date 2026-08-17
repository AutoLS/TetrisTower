Tetromino :: enum u32
{
    I;
    O;
    T;
    S;
    Z;
    J;
    L;
}

get_tetromino_cells :: (type: Tetromino) -> [..] Vector2
{
    cells: [..] Vector2;
    cells.allocator = temp;

    if type ==
    {
        case .I;
            array_add(*cells, .{0, 0}); array_add(*cells, .{0, 1});
            array_add(*cells, .{0, 2}); array_add(*cells, .{0, 3});
        case .O;
            array_add(*cells, .{0, 0}); array_add(*cells, .{0, 1});
            array_add(*cells, .{1, 0}); array_add(*cells, .{1, 1});
        case .T;
            array_add(*cells, .{0, 0}); array_add(*cells, .{0, 1}); array_add(*cells, .{0, 2});
            array_add(*cells, .{1, 1});
        case .S;
            array_add(*cells, .{0, 1}); array_add(*cells, .{0, 2});
            array_add(*cells, .{1, 0}); array_add(*cells, .{1, 1});
        case .Z;
            array_add(*cells, .{0, 0}); array_add(*cells, .{0, 1});
            array_add(*cells, .{1, 1}); array_add(*cells, .{1, 2});
        case .J;
            array_add(*cells, .{0, 0});
            array_add(*cells, .{1, 0}); array_add(*cells, .{1, 1}); array_add(*cells, .{1, 2});
        case .L;
            array_add(*cells, .{0, 2});
            array_add(*cells, .{1, 0}); array_add(*cells, .{1, 1}); array_add(*cells, .{1, 2});
    }

    return cells;
}

is_cell_filled :: (cells: [..] Vector2, r: int, c: int) -> bool
{
    for cell : cells
    {
        if cast(int)cell.x == r && cast(int)cell.y == c return true;
    }
    return false;
}

make_cell_pieces :: (cells: [..] Vector2, cell: float) -> [..] Rect_Piece
{
    pieces: [..] Rect_Piece;
    pieces.allocator = temp;

    min_r := 9999; max_r := -9999; min_c := 9999; max_c := -9999;
    for c : cells
    {
        min_r = min(min_r, cast(int)c.x);
        max_r = max(max_r, cast(int)c.x);
        min_c = min(min_c, cast(int)c.y);
        max_c = max(max_c, cast(int)c.y);
    }
    height := max_r - min_r + 1;
    width  := max_c - min_c + 1;

    for row : min_r .. max_r
    {
        col := min_c;
        while col <= max_c
        {
            if is_cell_filled(cells, row, col)
            {
                end := col;
                while end+1 <= max_c && is_cell_filled(cells, row, end+1) end += 1;
                run_len := end - col + 1;

                cx := (cast(float)(col + end) * 0.5 - cast(float)(width-1) * 0.5);
                cy := cast(float)(height-1) * 0.5 - cast(float)row;

                piece: Rect_Piece;
                piece.scale  = .{cast(float)run_len * cell, cell, 0};
                piece.center = .{cx * cell, cy * cell, 0};
                array_add(*pieces, piece);

                col = end + 1;
            }
            else
            {
                col += 1;
            }
        }
    }

    return pieces;
}

add_tetromino :: (using world: *Simulated_World, type: Tetromino, p: Vector3, cell: float, mass: float, friction: float = 0.5) -> *Rigid_Body
{
    cells := get_tetromino_cells(type);
    pieces := make_cell_pieces(cells, cell);
    body := make_compound_rect_body(pieces, mass);
    body.position = p;
    body.friction = friction;
    update_body_shapes(*body);
    array_add(*bodies, body);
    return *bodies[bodies.count-1];
}
