PIECE_MOVE_SPEED :: 300.0;
CELL_SIZE :: 50.0;
PIECE_MASS :: 50.0;
HARD_DROP_BOOST :: 1500.0;
SPAWN_DELAY_FRAMES :: 30;
SPAWN_CLEARANCE :: 300.0;
CAMERA_MAX_FOLLOW_DELTA :: 0.4; // max camera pan speed, units/frame
CAMERA_REACT_HEIGHT_CELLS :: 5; // tower height at which the camera starts reacting
MIN_ZOOM_MAGNITUDE :: 0.5; // furthest the camera will zoom out
ZOOM_MAX_DELTA :: 0.002; // max zoom change per frame
BASE_SPAWN_OFFSET :: 100.0;
STARTING_HP :: 10;
SLOW_MOTION_SPEED_SCALE :: 0.2;
DISCARDED_PIECE_POSITION :: Vector3.{-100000, -100000, 0};
FLOOR_WIDTH_RATIO :: 0.5; 
VOID_Y :: -150.0;

FREEZE_BAND_SIZE :: 10; // cells per freeze band

Game_State :: enum u32
{
    Main_Menu;
    In_Game;
    Paused;
    Gameover;
}

In_Game_Info :: struct
{
    current_piece_index: int = -1;
    current_piece_type: Tetromino;
    rotation_index: int;

    spawn_delay: int;
    spawn_pos: Vector3;

    held_piece_type: Tetromino;
    has_held_piece: bool;

    hp: int = STARTING_HP;
}

//Auto (TODO): Needs more cleanup
Game :: struct 
{
    block_texture: Texture2D;
    block_texture_rects: [#run enum_highest_value(Block_Color_Type)+1] Rectangle;

    screen_width, screen_height: s32;

    in_game_info: In_Game_Info;

    camera: Camera2D;

    queue: Piece_Queue;
    tetris_pieces: [..] Tetris_Piece;

    world: Simulated_World;

    state: Game_State = .Main_Menu;

    //Temp stuff
    floor_index: int;
}

// Resets the spawn point and camera to their starting state; shared by init_game and reset_game.
reset_camera_and_spawn :: (using game: *Game)
{
    in_game_info.spawn_pos = Vector3.{screen_width * 0.5, screen_height - BASE_SPAWN_OFFSET, 0};

    camera.target = .{screen_width * 0.5, 0};
    camera.zoom = -1.0;
}

create_floor :: (using game: *Game) -> int
{
    floor_width := screen_width * FLOOR_WIDTH_RATIO;
    idx := add_body(*world, .{screen_width*0.5, 0, 0}, .{}, .{floor_width, 50, 0}, 0);
    floor := *world.bodies[idx];
    floor.color = GRAY;
    floor.friction = 0.9;
    return idx;
}

init_game :: (sw: s32, sh: s32) -> Game
{
    using game: Game;

    set_physics_gravity(-60);

    screen_width = sw;
    screen_height = sh;

    block_texture = LoadTexture("ast/tetris-Sheet.png");
    for *block_texture_rects
    {
        x := it_index * 16;
        it.* = .{cast(float)x, 0, 16, 16};
    }

    init_piece_queue(*game.queue);
    reset_camera_and_spawn(*game);
    camera.offset = .{xx (screen_width * 0.5), xx screen_height};
    camera.rotation = 0.0;

    floor_index = create_floor(*game);

    return game;
}

reset_game :: (using game: *Game)
{
    array_reset_keeping_memory(*queue.pieces);
    array_reset_keeping_memory(*tetris_pieces);
    array_reset_keeping_memory(*world.bodies);

    init_piece_queue(*queue);

    in_game_info = .{};
    reset_camera_and_spawn(game);

    floor_index = create_floor(game);

    state = .In_Game;
}

// Straight-down projection for the ghost/landing indicator: finds the nearest surface below each shape and returns the smallest drop distance. found_surface is false if nothing is beneath the piece.
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
            // Only a surface actually beneath this shape's bottom edge can support it - an AABB that merely shares its x-range (e.g. from a tilted, settled piece whose bounding box overhangs its real footprint) is not a valid landing candidate.
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

// Highest point of any landed piece (excludes the currently-falling one). With require_settled, also skips pieces not yet marked settled - used only for the camera so landing jitter doesn't leak in.
compute_tower_top :: (using game: *Game, require_settled: bool) -> float
{
    top := 0.0;
    for tetris_pieces
    {
        if it.body_index == in_game_info.current_piece_index continue;
        if require_settled && !it.settled continue;
        top = max(top, get_body_top(*world, it.body_index));
    }
    return top;
}

get_tower_top :: (using game: *Game) -> float
{
    return compute_tower_top(game, false);
}

get_tower_height_cells :: (using game: *Game) -> int
{
    return cast(int)(get_tower_top(game) / CELL_SIZE);
}

get_settled_tower_top :: (using game: *Game) -> float
{
    return compute_tower_top(game, true);
}

is_body_in_void :: (world: *Simulated_World, body_index: int) -> bool
{
    return get_body_top(world, body_index) < VOID_Y;
}

// Any piece that has fallen past VOID_Y costs 1 HP and is dropped from tracking.
check_void_falls :: (using game: *Game)
{
    i := tetris_pieces.count - 1;
    while i >= 0
    {
        piece := tetris_pieces[i];
        if is_body_in_void(*world, piece.body_index)
        {
            if piece.body_index == in_game_info.current_piece_index
                retire_falling_piece(game);
            array_unordered_remove_by_index(*tetris_pieces, i);
            in_game_info.hp = max(in_game_info.hp - 1, 0);
        }
        i -= 1;
    }
}

// Highest fully-completed FREEZE_BAND_SIZE band below height_cells, e.g. height 23 -> 20.
compute_freeze_threshold_cells :: (height_cells: int) -> int
{
    return (height_cells / FREEZE_BAND_SIZE) * FREEZE_BAND_SIZE;
}

REST_SPEED_SQUARED :: 25.0; // (units/sec)^2 threshold for "at rest"

// Freezes landed, at-rest pieces below the current height threshold, and thaws any that are no longer below it. Skips the currently-falling piece so a hard-dropped piece can't dodge the void check.
update_piece_freezing :: (using game: *Game)
{
    threshold_cells := compute_freeze_threshold_cells(get_tower_height_cells(game));
    threshold_y := cast(float)threshold_cells * CELL_SIZE;

    for *tetris_pieces
    {
        if it.body_index == in_game_info.current_piece_index continue;

        body := *world.bodies[it.body_index];
        top := get_body_top(*world, it.body_index);
        at_rest := dot(body.velocity, body.velocity) <= REST_SPEED_SQUARED;
        if at_rest then it.settled = true;

        if at_rest && top <= threshold_y
        {
            it.freezed = true;
            body.inverse_mass = 0;
            body.velocity = .{};
            body.angular_velocity = .{};
        }
        else if body.inverse_mass == 0 && top > threshold_y
        {
            it.freezed = false;
            body.inverse_mass = 1.0 / PIECE_MASS;
        }
    }
}

is_game_over :: (using game: *Game) -> bool
{
    return in_game_info.hp <= 0;
}

retire_falling_piece :: (using game: *Game)
{
    in_game_info.current_piece_index = -1;
    in_game_info.spawn_delay = SPAWN_DELAY_FRAMES;
}

// Creates the physics body for `type` at `position`/`velocity` and makes it the controlled piece. Shared by normal spawn-from-queue and hold/swap.
spawn_piece_at :: (using game: *Game, type: Tetromino, position: Vector3, velocity: Vector3 = .{})
{
    body_index := add_tetromino(*world, type, position, CELL_SIZE, PIECE_MASS);
    piece := *world.bodies[body_index];
    piece.velocity = velocity;
    r := random_get_zero_to_one_open() * 255;
    g := random_get_zero_to_one_open() * 255;
    b := random_get_zero_to_one_open() * 255;
    piece.color = Color.{xx r, xx g, xx b, 255};

    in_game_info.current_piece_index = body_index;
    in_game_info.current_piece_type = type;
    in_game_info.rotation_index = 0;

    tetris_piece: Tetris_Piece;
    tetris_piece.body_index = body_index;
    tetris_piece.type = type;
    tetris_piece.color = xx type;

    array_add(*tetris_pieces, tetris_piece);
}

spawn_current_piece :: (using game: *Game, type: Tetromino)
{
    spawn_piece_at(game, type, in_game_info.spawn_pos);
}

// The Physics module can't delete bodies, so a piece taken out of play is teleported off-map instead and dropped from tetris_pieces so it stops rendering and colliding.
remove_piece_from_play :: (using game: *Game, body_index: int)
{
    body := *world.bodies[body_index];
    body.position = DISCARDED_PIECE_POSITION;
    body.velocity = .{};
    update_body_shapes(body);

    for i : 0..tetris_pieces.count-1
    {
        if tetris_pieces[i].body_index == body_index
        {
            array_unordered_remove_by_index(*tetris_pieces, i);
            return;
        }
    }
}

update_main_menu :: (using game: *Game)
{
    if text_button("Start", .{screen_width*0.5, screen_height*0.5}, 48, BLACK) 
    {
        game.state = .In_Game;
    }
}

update_paused_menu :: (using game: *Game)
{
    draw_text_centered("PAUSED", .{0, -300}, screen_width, screen_height, 50, YELLOW);

    if text_button("Continue", .{screen_width*0.5, screen_height*0.5}, 48, BLACK)
    {
        game.state = .In_Game;
    }

    if text_button("Back to main menu", .{screen_width*0.5, screen_height*0.5 + 98}, 48, BLACK)
    {
        reset_game(game);
        game.state = .Main_Menu;
    }
}

update_game :: (using game: *Game)
{
    using game.in_game_info;

    if is_game_over(game)
    {
        state = .Gameover; return;
    }

    if IsKeyPressed(.KEY_ESCAPE)
    {
        state = .Paused; return;
    }

    if IsKeyDown(.KEY_LEFT_CONTROL) && IsKeyPressed(.KEY_R)
    {
        reset_game(game); return;
    }

    base_spawn_y := screen_height - BASE_SPAWN_OFFSET;

    tower_top := get_tower_top(game);
    spawn_pos.y = max(base_spawn_y, tower_top + SPAWN_CLEARANCE);

    // Camera follows the settled tower height (not the live one) to avoid landing jitter. It zooms out to keep the floor and reaction room in view, then falls back to panning past MIN_ZOOM_MAGNITUDE.
    settled_top := get_settled_tower_top(game);
    required_top := cast(float)screen_height + max(0.0, settled_top - CAMERA_REACT_HEIGHT_CELLS * CELL_SIZE);

    ideal_zoom_magnitude := clamp(cast(float)screen_height / required_top, MIN_ZOOM_MAGNITUDE, 1.0);
    zoom_magnitude := move_toward(-camera.zoom, ideal_zoom_magnitude, ZOOM_MAX_DELTA);
    camera.zoom = -zoom_magnitude;

    ideal_target_y := max(0.0, required_top - cast(float)screen_height / zoom_magnitude);
    camera.target.y = move_toward(camera.target.y, ideal_target_y, CAMERA_MAX_FOLLOW_DELTA);

    if current_piece_index == -1
    {
        if spawn_delay > 0
        {
            spawn_delay -= 1;
        }
        else
        {
            spawn_current_piece(game, dequeue_piece(*queue));
        }
    }

    if current_piece_index != -1
    {
        if IsKeyPressed(.KEY_C)
        {
            old_body_index := current_piece_index;
            old_type := current_piece_type;
            old_position := world.bodies[old_body_index].position;
            old_velocity := world.bodies[old_body_index].velocity;

            remove_piece_from_play(game, old_body_index);

            next_type: Tetromino;
            if has_held_piece then next_type = held_piece_type;
            else { next_type = dequeue_piece(*queue); has_held_piece = true; }
            held_piece_type = old_type;

            // Swap in place, continuing from the old piece's position/velocity.
            spawn_piece_at(game, next_type, old_position, old_velocity);
        }

        piece := *world.bodies[current_piece_index];

        slow_motion := IsKeyDown(.KEY_LEFT_SHIFT);

        direction := 0.0;
        if IsKeyDown(.KEY_LEFT)  then direction += 1;
        if IsKeyDown(.KEY_RIGHT) then direction -= 1;
        move_speed := ifx slow_motion then PIECE_MOVE_SPEED * SLOW_MOTION_SPEED_SCALE else PIECE_MOVE_SPEED;
        piece.velocity.x = direction * move_speed;

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
    update_piece_freezing(game);
}

HOLD_GAP_X :: 40; // horizontal gap between the NEXT column and the HOLD box
HOLD_MARGIN_X :: QUEUE_MARGIN_X + QUEUE_BOX_SIZE + HOLD_GAP_X;
HOLD_MARGIN_Y :: QUEUE_MARGIN_Y; // aligned with the top of the NEXT column

draw_hold_box :: (game: *Game)
{
    box_x: s32 = HOLD_MARGIN_X;

    DrawText(get_c_string("HOLD"), box_x, HOLD_MARGIN_Y, 24, BLACK);

    box_y: s32 = HOLD_MARGIN_Y + LABEL_TO_BOX_GAP;
    if game.in_game_info.has_held_piece
        draw_tetromino_preview_box(game.in_game_info.held_piece_type, box_x, box_y);
    else
        DrawRectangleLines(box_x, box_y, QUEUE_BOX_SIZE, QUEUE_BOX_SIZE, GRAY);
}

draw_hud :: (game: *Game)
{
    font_size: s32 = 24;

    hp_text := tprint("HP: %", game.in_game_info.hp);
    draw_text_right_aligned(hp_text, HUD_MARGIN, font_size, BLACK, game.screen_width);

    height_text := tprint("Height: %", get_tower_height_cells(game));
    draw_text_right_aligned(height_text, HUD_MARGIN + font_size + 6, font_size, BLACK, game.screen_width);

    if game.state == .Gameover
    {
        draw_text_centered("GAME OVER", game.screen_width, game.screen_height, 48, RED);
    }
}

render_game :: (using game: *Game)
{
    using game.in_game_info;
    
    BeginMode2D(camera);

    if current_piece_index != -1
    {
        piece := *world.bodies[current_piece_index];
        offset_y, found_surface := compute_landing_offset(*world, current_piece_index);

        // Skip the ghost entirely if the piece has drifted past the floor with nothing beneath it.
        if found_surface
        {
            ghost_offset := Vector3.{0, offset_y, 0};
            draw_tetromino_cells(block_texture, current_piece_type, piece, 50, block_texture_rects[xx current_piece_type], ghost_offset, 100);
        }
    }

    floor := *world.bodies[floor_index];
    for s : floor.shapes
    {
        draw_convex_shape(s, color=floor.color);
    }

    for tetris_pieces
    {
        if !it.freezed
        {
            draw_tetromino_cells(block_texture, it.type, *world.bodies[it.body_index], CELL_SIZE, block_texture_rects[xx it.color]);
        }
        else
        {
            draw_tetromino_cells(block_texture, it.type, *world.bodies[it.body_index], CELL_SIZE, block_texture_rects[xx Block_Color_Type.Grey]);
        }
    }

    EndMode2D();
}