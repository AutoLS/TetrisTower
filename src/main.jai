#import "Physics";
#import "raylib";
#import "Basic";
#import "Math";
#import "Random";

#load "util.jai";
#load "tetris.jai";
#load "render.jai";
#load "game.jai";

main :: ()
{
    random_seed(cast,force(Some_Big_Time_Value)current_time_consensus());

    sw: s32 = 1280;
    sh: s32 = 900;

    InitWindow(sw, sh, "Tetris Tower");
    defer CloseWindow();

    using game := init_game(sw, sh);
    SetExitKey(.KEY_NULL);

    SetTargetFPS(120);

    while !WindowShouldClose()
    {
        reset_temporary_storage();
        if game.state ==
        {
            case .In_Game; update_game(*game);
            case .Paused;
            {
                if IsKeyPressed(.KEY_ESCAPE) state = .In_Game;
            }
            case .Gameover; 
            {
                if IsKeyPressed(.KEY_SPACE) || IsKeyPressed(.KEY_ENTER)
                {
                    reset_game(*game);
                }
            }
        }

        BeginDrawing();
        ClearBackground(RAYWHITE);

        flip_y := MatrixScale(1.0, -1.0, 1.0);
        rlSetMatrixModelview(flip_y);

        render_game(*game);

        draw_piece_queue(queue);
        draw_hold_box(*game);
        draw_hud(*game);

        EndDrawing();
    }

    UnloadTexture(block_texture);
}