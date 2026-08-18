#import "Physics";
#import "raylib";
#import "Basic";
#import "Math";
#import "Random";

#load "tetris.jai";
#load "render.jai";

// Builds the actual compound shape the piece would spawn as (same helpers add_tetromino
// uses), so this tests the real occupied cells at the real center-of-mass-positioned
// location, instead of an approximate bounding box.
is_spawn_blocked :: (world: *Simulated_World, type: Tetromino, spawn_pos: Vector3, cell_size: float) -> bool
{
    push_allocator(temp);

    cells := get_tetromino_cells(type);
    pieces := make_cell_pieces(cells, cell_size);
    candidate := make_compound_rect_body(pieces, 1);
    candidate.position = spawn_pos;
    update_body_shapes(*candidate);

    for world.bodies
    {
        if it.inverse_mass == 0 continue;

        for candidate_shape : candidate.shapes
        {
            candidate_aabb := get_aabb(candidate_shape);

            for shape : it.shapes
            {
                if aabb_overlap(candidate_aabb, get_aabb(shape)) return true;
            }
        }
    }
    return false;
}

// Simple per-shape straight-down projection used for the ghost/landing indicator: for each of
// the falling piece's shapes, find the highest surface directly below it (by x-overlap, among
// every other body not in `exclude`) and return the smallest resulting drop distance across all
// shapes - i.e. the first point of contact, same idea as a classic hard-drop preview. This
// ignores how real physics would actually settle the piece (tipping, sliding, deflection) by design.
compute_landing_offset :: (world: *Simulated_World, piece_index: int, exclude: [] int) -> float
{
    piece := world.bodies[piece_index];

    other_aabbs: [..] AABB;
    other_aabbs.allocator = temp;

    for body_index : 0..world.bodies.count-1
    {
        if body_index == piece_index || array_find(exclude, body_index) continue;

        for other : world.bodies[body_index].shapes
            array_add(*other_aabbs, get_aabb(other));
    }

    best_offset := -FLOAT32_MAX;

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
                surface_y = max(surface_y, o_aabb.max.y);
        }

        drop := surface_y - s_aabb.min.y;
        best_offset = max(best_offset, drop);
    }

    return best_offset;
}

main :: ()
{
    random_seed(cast,force(Some_Big_Time_Value)current_time_consensus());

    screen_width: s32 = 1280;
    screen_height: s32 = 720;

    InitWindow(screen_width, screen_height, "Tetris Tower");
    defer CloseWindow();

    camera: Camera2D;
    camera.target = .{};
    camera.offset = .{xx screen_width, xx screen_height};
    camera.rotation = 0.0;
    camera.zoom = -1.0;

    world: Simulated_World;

    queue: Piece_Queue;
    init_piece_queue(*queue);

    floor := add_body(*world, .{screen_width/2.0, 0, 0}, .{}, .{xx screen_width, 50, 0}, 0);
    floor.color = GRAY;
    floor.friction = 0.9;

    add_body(*world, .{0, screen_height/2.0, 0}, .{}, .{50, xx screen_height, 0}, 0);
    wall1_index := world.bodies.count - 1;
    add_body(*world, .{xx screen_width, screen_height/2.0, 0}, .{}, .{50, xx screen_height, 0}, 0);
    wall2_index := world.bodies.count - 1;

    current_piece_index := -1;
    rotation_index := 0;
    game_over := false;
    spawn_delay := 0;

    PIECE_MOVE_SPEED :: 300.0;
    CELL_SIZE :: 50.0;
    PIECE_MASS :: 50.0;
    HARD_DROP_BOOST :: 1500.0;
    SPAWN_DELAY_FRAMES :: 30;
    spawn_pos := Vector3.{screen_width / 2.0, screen_height - 150.0, 0};

    SetTargetFPS(120);

    while !WindowShouldClose()
    {
        if current_piece_index == -1 && !game_over
        {
            if spawn_delay > 0
            {
                spawn_delay -= 1;
            }
            else
            {
                if is_spawn_blocked(*world, queue.pieces[0], spawn_pos, CELL_SIZE)
                {
                    game_over = true;
                }
                else
                {
                    piece_type := dequeue_piece(*queue);

                    piece := add_tetromino(*world, piece_type, spawn_pos, CELL_SIZE, PIECE_MASS);
                    r := random_get_zero_to_one_open() * 255;
                    g := random_get_zero_to_one_open() * 255;
                    b := random_get_zero_to_one_open() * 255;
                    piece.color = Color.{xx r, xx g, xx b, 255};

                    current_piece_index = world.bodies.count - 1;
                    rotation_index = 0;
                }
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
                current_piece_index = -1;
                spawn_delay = SPAWN_DELAY_FRAMES;
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

                    other_index := ifx r.a_index == current_piece_index then r.b_index else r.a_index;
                    if other_index == wall1_index || other_index == wall2_index continue;

                    current_piece_index = -1;
                    spawn_delay = SPAWN_DELAY_FRAMES;
                    break;
                }
            }
        }

        BeginDrawing();
        ClearBackground(RAYWHITE);

        flip_y := MatrixScale(1.0, -1.0, 1.0);
        rlSetMatrixModelview(flip_y);

        BeginMode2D(camera);

        if current_piece_index != -1
        {
            piece := *world.bodies[current_piece_index];
            ghost_offset := Vector3.{0, compute_landing_offset(*world, current_piece_index, .[wall1_index, wall2_index]), 0};
            ghost_color := Color.{piece.color.r, piece.color.g, piece.color.b, 200};

            for s : piece.shapes
                draw_convex_shape_outline(s, offset=ghost_offset, color=ghost_color);
        }

        for world.bodies
        {
            for s : it.shapes
            {
                draw_convex_shape(s, color=it.color);
            }
        }
            
        EndMode2D();

        draw_piece_queue(queue);

        if game_over
        {
            draw_game_over(screen_width, screen_height);
        }

        EndDrawing();
    }
}