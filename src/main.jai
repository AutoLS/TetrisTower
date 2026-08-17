#import "Physics";
#import "raylib";
#import "Basic";
#import "Math";
#import "Random";

#load "tetris.jai";
#load "render.jai";

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
    
    floor := add_body(*world, .{screen_width/2.0, 0, 0}, .{}, .{xx screen_width, 50, 0}, 0);
    floor.color = GRAY;
    floor.friction = 0.9;

    wall1 := add_body(*world, .{0, screen_height/2.0, 0}, .{}, .{50, xx screen_height, 0}, 0);
    wall2 := add_body(*world, .{xx screen_width, screen_height/2.0, 0}, .{}, .{50, xx screen_height, 0}, 0);

    SetTargetFPS(120);

    while !WindowShouldClose()
    {
        if IsMouseButtonPressed(.MOUSE_BUTTON_LEFT)
        {
            p := GetMousePosition();
            p.x = (screen_width - p.x);
            p.y = (screen_height - p.y);

            piece_type := random_get_zero_to_one_open() * (enum_highest_value(Tetromino)+1);
            
            piece := add_tetromino(*world, cast(Tetromino)piece_type, .{p.x, p.y, 0}, 50, 50);
            r := random_get_zero_to_one_open() * 255;
            g := random_get_zero_to_one_open() * 255;
            b := random_get_zero_to_one_open() * 255;
            piece.color = Color.{xx r, xx g, xx b, 255};

            rotate_body(piece, .{0, 0, 1}, random_get_within_range(0, 180));
        }

        simulate_world(*world);

        BeginDrawing();
        ClearBackground(RAYWHITE);

        flip_y := MatrixScale(1.0, -1.0, 1.0);
        rlSetMatrixModelview(flip_y);

        BeginMode2D(camera);

        for world.bodies 
        {
            for s : it.shapes
            {
                draw_convex_shape(s, color=it.color);
            }
        }
            
        EndMode2D();

        EndDrawing();
    }
}