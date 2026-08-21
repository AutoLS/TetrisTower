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

Block_Color_Type :: enum u32
{
    Yellow;
    Green;
    Purple;
    Blue;
    Orange;
    Pink;
    Skyblue;
    Grey;
    Sand;
    Emerald;
    White;
}

Tetris_Piece :: struct
{
    body_index: int;
    type:       Tetromino;
    color:      Block_Color_Type;
    settled: bool; // latches true once observed at rest; never cleared
    freezed: bool;
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

Cell_Bounds :: struct
{
    min_r, max_r, min_c, max_c: int;
    width, height: int;
}

get_cell_bounds :: (cells: [..] Vector2) -> Cell_Bounds
{
    b: Cell_Bounds;
    b.min_r = 9999; b.max_r = -9999; b.min_c = 9999; b.max_c = -9999;
    for c : cells
    {
        b.min_r = min(b.min_r, cast(int)c.x);
        b.max_r = max(b.max_r, cast(int)c.x);
        b.min_c = min(b.min_c, cast(int)c.y);
        b.max_c = max(b.max_c, cast(int)c.y);
    }
    b.height = b.max_r - b.min_r + 1;
    b.width  = b.max_c - b.min_c + 1;
    return b;
}

make_cell_pieces :: (cells: [..] Vector2, cell: float) -> [..] Rect_Piece
{
    pieces: [..] Rect_Piece;
    pieces.allocator = temp;

    bounds := get_cell_bounds(cells);
    min_r := bounds.min_r; max_r := bounds.max_r; min_c := bounds.min_c; max_c := bounds.max_c;
    height := bounds.height; width := bounds.width;

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

QUEUE_PREVIEW_COUNT :: 3;

Piece_Queue :: struct
{
    pieces: [..] Tetromino;
}

refill_bag :: (queue: *Piece_Queue)
{
    bag: [..] Tetromino;
    bag.allocator = temp;

    count := enum_highest_value(Tetromino) + 1;
    for i : 0..count-1 array_add(*bag, cast(Tetromino)i);

    for i : 0..bag.count-2
    {
        j := i + cast(int)(random_get() % cast(u64)(bag.count - i));
        t := bag[i];
        bag[i] = bag[j];
        bag[j] = t;
    }

    for bag array_add(*queue.pieces, it);
}

init_piece_queue :: (queue: *Piece_Queue)
{
    while queue.pieces.count < QUEUE_PREVIEW_COUNT refill_bag(queue);
}

dequeue_piece :: (queue: *Piece_Queue) -> Tetromino
{
    result := queue.pieces[0];
    array_ordered_remove_by_index(*queue.pieces, 0);
    while queue.pieces.count < QUEUE_PREVIEW_COUNT refill_bag(queue);
    return result;
}

add_tetromino :: (using world: *Simulated_World, type: Tetromino, p: Vector3, cell: float, mass: float, friction: float = 0.5) -> int
{
    cells := get_tetromino_cells(type);
    pieces := make_cell_pieces(cells, cell);
    body := make_compound_rect_body(pieces, mass);
    body.position = p;
    body.friction = friction;
    update_body_shapes(*body);
    array_add(*bodies, body);
    return bodies.count-1;
}
