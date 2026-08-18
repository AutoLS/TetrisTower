PIECE_MOVE_SPEED :: 300.0;
CELL_SIZE :: 50.0;
PIECE_MASS :: 50.0;
HARD_DROP_BOOST :: 1500.0;
SPAWN_DELAY_FRAMES :: 30;
SPAWN_CLEARANCE :: 150.0;
CAMERA_FOLLOW_SPEED :: 0.1;
BASE_SPAWN_OFFSET :: 150.0;
STARTING_HP :: 10;
FLOOR_WIDTH_RATIO :: 0.5; // floor spans the middle half of the screen - a quarter is chopped off each side
// Floor bottom sits at y = -25 (floor is 50 tall, centered on y = 0), so this gives roughly
// a 2.5-cell buffer of free-fall before a piece counts as lost to the void - enough that a
// piece resting right at the floor's edge doesn't false-trigger, but still reacts quickly.
VOID_Y :: -150.0;

//Auto (TODO): Needs more cleanup
Game :: struct 
{
    block_texture: Texture2D;
    block_texture_rects: [#run enum_highest_value(Block_Color_Type)+1] Rectangle;

    screen_width, screen_height: s32;

    current_piece_index: int = -1;
    current_piece_type: Tetromino;
    rotation_index: int;

    spawn_delay: int;
    spawn_pos: Vector3;

    hp: int = STARTING_HP;

    camera: Camera2D;

    queue: Piece_Queue;
    tetris_pieces: [..] Tetris_Piece;

    world: Simulated_World;

    //Temp stuff
    floor_index: int;
}

init_game :: (sw: s32, sh: s32) -> Game
{
    using game: Game;

    screen_width = sw;
    screen_height = sh;
    
    block_texture = LoadTexture("ast/tetris-Sheet.png");
    for *block_texture_rects
    {
        x := it_index * 16;
        it.* = .{cast(float)x, 0, 16, 16};
    }
    
    init_piece_queue(*game.queue);
    spawn_pos = Vector3.{screen_width / 2.0, screen_height - BASE_SPAWN_OFFSET, 0};
    
    camera.target = .{};
    camera.offset = .{xx screen_width, xx screen_height};
    camera.rotation = 0.0;
    camera.zoom = -1.0;

    floor_width := screen_width * FLOOR_WIDTH_RATIO;
    floor_index = add_body(*world, .{screen_width/2.0, 0, 0}, .{}, .{floor_width, 50, 0}, 0);
    floor := *world.bodies[floor_index];
    floor.color = GRAY;
    floor.friction = 0.9;

    return game;
}

// Simple per-shape straight-down projection used for the ghost/landing indicator: for each of
// the falling piece's shapes, find the highest surface directly below it (by x-overlap, among
// every other body) and return the smallest resulting drop distance across all shapes - i.e. the
// first point of contact, same idea as a classic hard-drop preview. This ignores how real physics
// would actually settle the piece (tipping, sliding, deflection) by design. Returns null if no
// shape has any surface beneath it at all (e.g. the piece has drifted past the floor's edge and
// is headed for the void) - callers must not draw a landing indicator in that case.
compute_landing_offset :: (world: *Simulated_World, piece_index: int) -> float, bool
{
    piece := world.bodies[piece_index];

    other_aabbs: [..] AABB;
    other_aabbs.allocator = temp;

    for body_index : 0..world.bodies.count-1
    {
        if body_index == piece_index continue;

        for other : world.bodies[body_index].shapes
            array_add(*other_aabbs, get_aabb(other));
    }

    best_offset := -FLOAT32_MAX;
    found_surface := false;

    for s : piece.shapes
    {
        s_aabb := get_aabb(s);
        surface_y := -FLOAT32_MAX;

        for o_aabb : other_aabbs
        {
            // Only a surface actually beneath this shape's bottom edge can support it - an AABB
            // that merely shares its x-range (e.g. from a tilted, settled piece whose bounding
            // box overhangs its real footprint) is not a valid landing candidate.
            if o_aabb.max.y <= s_aabb.min.y && s_aabb.min.x <= o_aabb.max.x && s_aabb.max.x >= o_aabb.min.x
            {
                surface_y = max(surface_y, o_aabb.max.y);
                found_surface = true;
            }
        }

        drop := surface_y - s_aabb.min.y;
        best_offset = max(best_offset, drop);
    }

    return best_offset, found_surface;
}

get_body_top :: (world: *Simulated_World, body_index: int) -> float
{
    top := -FLOAT32_MAX;
    for s : world.bodies[body_index].shapes
        top = max(top, get_aabb(s).max.y);
    return top;
}

// Highest point reached by any settled piece (the currently-falling piece is excluded so the
// spawn point/camera don't jump the instant a new piece appears at spawn height - only once it
// actually lands does it count towards the tower). Falls back to 0 (floor level) when empty.
get_tower_top :: (using game: *Game) -> float
{
    top := 0.0;
    for tetris_pieces
    {
        if it.body_index == current_piece_index continue;
        top = max(top, get_body_top(*world, it.body_index));
    }
    return top;
}

is_body_in_void :: (world: *Simulated_World, body_index: int) -> bool
{
    return get_body_top(world, body_index) < VOID_Y;
}

// Any tracked piece (falling or already landed) that has dropped past VOID_Y costs 1 HP and is
// dropped from tracking - it no longer renders or counts towards tower height. Walking backwards
// keeps in-place removal from `tetris_pieces` safe.
check_void_falls :: (using game: *Game)
{
    i := tetris_pieces.count - 1;
    while i >= 0
    {
        piece := tetris_pieces[i];
        if is_body_in_void(*world, piece.body_index)
        {
            if piece.body_index == current_piece_index
                retire_falling_piece(game);
            array_unordered_remove_by_index(*tetris_pieces, i);
            hp = max(hp - 1, 0);
        }
        i -= 1;
    }
}

is_game_over :: (using game: *Game) -> bool
{
    return hp <= 0;
}

retire_falling_piece :: (using game: *Game)
{
    current_piece_index = -1;
    spawn_delay = SPAWN_DELAY_FRAMES;
}

update_game :: (using game: *Game)
{
    if is_game_over(game) return;

    base_spawn_y := screen_height - BASE_SPAWN_OFFSET;

    tower_top := get_tower_top(game);
    spawn_pos.y = max(base_spawn_y, tower_top + SPAWN_CLEARANCE);

    scroll := spawn_pos.y - base_spawn_y;
    camera.target.y = lerp(camera.target.y, scroll, CAMERA_FOLLOW_SPEED);

    if current_piece_index == -1
    {
        if spawn_delay > 0
        {
            spawn_delay -= 1;
        }
        else
        {
            piece_type := dequeue_piece(*queue);

            body_index := add_tetromino(*world, piece_type, spawn_pos, CELL_SIZE, PIECE_MASS);
            piece := *world.bodies[body_index];
            r := random_get_zero_to_one_open() * 255;
            g := random_get_zero_to_one_open() * 255;
            b := random_get_zero_to_one_open() * 255;
            piece.color = Color.{xx r, xx g, xx b, 255};

            current_piece_index = body_index;
            current_piece_type = piece_type;
            rotation_index = 0;

            array_add(*tetris_pieces, .{body_index, piece_type, xx piece_type});
        }
    }

    if current_piece_index != -1
    {
        piece := *world.bodies[current_piece_index];

        direction := 0.0;
        if IsKeyDown(.KEY_LEFT)  then direction += 1;
        if IsKeyDown(.KEY_RIGHT) then direction -= 1;
        piece.velocity.x = direction * PIECE_MOVE_SPEED;

        delta := 0;
        if IsKeyPressed(.KEY_UP) || IsKeyPressed(.KEY_X)
        {
            delta = 1;
        }
        else if IsKeyPressed(.KEY_Z)
        {
            delta = 3;
        }

        if delta != 0
        {
            rotation_index = (rotation_index + delta) % 4;
            rotate_body(piece, .{0, 0, 1}, radians(xx (rotation_index * 90)));
        }

        if IsKeyPressed(.KEY_SPACE)
        {
            piece.velocity.y -= HARD_DROP_BOOST;
            retire_falling_piece(game);
        }
    }

    simulate_world(*world);

    if current_piece_index != -1
    {
        for r : world.collision_resolutions
        {
            if r.a_index == current_piece_index || r.b_index == current_piece_index
            {
                if r.contacts.count == 0 continue;

                retire_falling_piece(game);
                break;
            }
        }
    }

    check_void_falls(game);
}

render_game :: (using game: *Game)
{
    BeginMode2D(camera);

    if current_piece_index != -1
    {
        piece := *world.bodies[current_piece_index];
        offset_y, found_surface := compute_landing_offset(*world, current_piece_index);

        // The piece may have drifted past the (now narrower) floor's edge with nothing else
        // beneath it - there's no landing spot to preview, so skip the ghost entirely rather
        // than drawing it at the degenerate offset compute_landing_offset would otherwise return.
        if found_surface
        {
            ghost_offset := Vector3.{0, offset_y, 0};
            draw_tetromino_cells(block_texture, current_piece_type, piece, 50, block_texture_rects[xx current_piece_type], ghost_offset, 100);
        }
    }

    for world.bodies
    {
        if it.inverse_mass != 0 continue;

        for s : it.shapes
        {
            draw_convex_shape(s, color=it.color);
        }
    }

    for tetris_pieces
    {
        draw_tetromino_cells(block_texture, it.type, *world.bodies[it.body_index], CELL_SIZE, block_texture_rects[xx it.color]);
    }

    EndMode2D();
}