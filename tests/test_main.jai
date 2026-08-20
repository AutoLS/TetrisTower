// Headless test suite for the game logic in src/*.jai - no raylib window is ever opened. Game is
// a plain data struct and none of the code exercised here touches LoadTexture/InitWindow/Draw*,
// so it's safe to construct and call directly. Most tests place bodies at exact hand-picked
// positions and call the freeze logic directly, without calling simulate_world() (confirmed
// working headless - see test_frozen_body_immune_to_friction_spin - but avoided elsewhere so each
// test's positions/velocities stay exact and deterministic instead of physics-engine-dependent).

#import "Physics";
#import "raylib";
#import "Basic";
#import "Math";
#import "Random";

#load "../src/util.jai";
#load "../src/tetris.jai";
#load "../src/render.jai";
#load "../src/game.jai";

make_test_game :: () -> Game
{
    game: Game;
    game.screen_width = 1280;
    game.screen_height = 900;
    reset_game(*game);
    return game;
}

// Adds a landed O-piece (a simple 2-cell-tall block, no per-row splitting quirks) whose top edge
// sits at exactly `top_y` (world-space), tracked in tetris_pieces like a normally-landed piece.
add_landed_piece_at_top :: (game: *Game, top_y: float) -> int
{
    center_y := top_y - CELL_SIZE;
    body_index := add_tetromino(*game.world, .O, .{0, center_y, 0}, CELL_SIZE, PIECE_MASS);
    array_add(*game.tetris_pieces, .{body_index, .O, .Yellow, true});
    return body_index;
}

// Adds a landed, 4-cell-tall vertical I-piece (rotated 90 degrees from its default horizontal
// layout) centered at `center_y` - top sits at center_y + 2*CELL_SIZE, bottom at
// center_y - 2*CELL_SIZE. Used for the straddling-the-freeze-line test.
add_vertical_i_piece :: (game: *Game, center_y: float) -> int
{
    body_index := add_tetromino(*game.world, .I, .{0, center_y, 0}, CELL_SIZE, PIECE_MASS);
    rotate_body(*game.world.bodies[body_index], .{0, 0, 1}, radians(90));
    array_add(*game.tetris_pieces, .{body_index, .I, .Skyblue, true});
    return body_index;
}

is_frozen :: (game: *Game, body_index: int) -> bool
{
    return game.world.bodies[body_index].inverse_mass == 0;
}

test_compute_freeze_threshold_cells :: ()
{
    assert(compute_freeze_threshold_cells(0) == 0);
    assert(compute_freeze_threshold_cells(5) == 0);
    assert(compute_freeze_threshold_cells(9) == 0);
    assert(compute_freeze_threshold_cells(10) == 10);
    assert(compute_freeze_threshold_cells(19) == 10);
    assert(compute_freeze_threshold_cells(20) == 20);
    assert(compute_freeze_threshold_cells(23) == 20);
    assert(compute_freeze_threshold_cells(30) == 30);
    assert(compute_freeze_threshold_cells(31) == 30);
    print("test_compute_freeze_threshold_cells ... ok\n");
}

// A single landed piece, at rest, at various heights around the first band boundary - only the
// piece exactly at or below the 10-cell line should freeze.
test_single_piece_freeze_boundary :: ()
{
    Case :: struct { top_cells: int; expect_frozen: bool; }
    cases := Case.[ .{9, false}, .{10, true}, .{11, false} ];

    for c : cases
    {
        game := make_test_game();
        idx := add_landed_piece_at_top(*game, cast(float)c.top_cells * CELL_SIZE);

        update_piece_freezing(*game);

        assert(is_frozen(*game, idx) == c.expect_frozen, tprint("height % cells should be frozen=%", c.top_cells, c.expect_frozen));
    }
    print("test_single_piece_freeze_boundary ... ok\n");
}

test_freeze_at_exact_threshold :: ()
{
    game := make_test_game();
    idx := add_landed_piece_at_top(*game, 10 * CELL_SIZE); // height 10 -> threshold 10 (inclusive)
    game.world.bodies[idx].velocity = .{0, -3, 0}; // small residual settling velocity, still "at rest"
    game.world.bodies[idx].angular_velocity = .{0, 0, 1};

    update_piece_freezing(*game);

    body := game.world.bodies[idx];
    assert(body.inverse_mass == 0, "a piece at rest, exactly at the threshold line, should freeze");
    assert(body.velocity.x == 0 && body.velocity.y == 0 && body.velocity.z == 0, "freezing must zero residual velocity");
    assert(body.angular_velocity.x == 0 && body.angular_velocity.y == 0 && body.angular_velocity.z == 0, "freezing must zero residual angular velocity");
    print("test_freeze_at_exact_threshold ... ok\n");
}

// Regression test: a piece can lose "current" status (hard-drop, or a non-supporting glancing
// collision) while still moving fast - e.g. straight through open space toward the void. It must
// not freeze mid-flight just because its position momentarily crosses the threshold line, or it
// would dodge check_void_falls entirely and hang there forever instead of costing HP.
test_fast_moving_piece_not_frozen_even_below_threshold :: ()
{
    game := make_test_game();
    idx := add_landed_piece_at_top(*game, 10 * CELL_SIZE); // top is exactly at the threshold line
    game.world.bodies[idx].velocity = .{0, -HARD_DROP_BOOST, 0}; // simulates a just-hard-dropped piece

    update_piece_freezing(*game);

    assert(!is_frozen(*game, idx), "a fast-moving piece must not freeze just because it's below the threshold line");
    print("test_fast_moving_piece_not_frozen_even_below_threshold ... ok\n");
}

// Once a fast-moving piece actually slows down (settles, or is genuinely at rest), it becomes
// freeze-eligible on a later frame - the rest requirement delays freezing, it doesn't block it forever.
test_piece_freezes_once_it_slows_down :: ()
{
    game := make_test_game();
    idx := add_landed_piece_at_top(*game, 10 * CELL_SIZE); // top is exactly at the threshold line
    game.world.bodies[idx].velocity = .{0, -HARD_DROP_BOOST, 0};

    update_piece_freezing(*game);
    assert(!is_frozen(*game, idx), "setup: still moving fast, should not freeze yet");

    game.world.bodies[idx].velocity = .{0, -1, 0}; // settled down to a near-rest speed
    update_piece_freezing(*game);

    assert(is_frozen(*game, idx), "a piece should freeze once it slows to near rest, still below the line");
    print("test_piece_freezes_once_it_slows_down ... ok\n");
}

test_band_advancement :: ()
{
    game := make_test_game();

    idx_a := add_landed_piece_at_top(*game, 10 * CELL_SIZE); // height 10 -> threshold 10
    update_piece_freezing(*game);
    assert(is_frozen(*game, idx_a), "setup: piece should freeze under the initial threshold");

    idx_b := add_landed_piece_at_top(*game, 21 * CELL_SIZE); // new tallest -> threshold advances to 20
    idx_c := add_landed_piece_at_top(*game, 16 * CELL_SIZE); // newly under the 20-line, wasn't under the 10-line
    update_piece_freezing(*game);

    assert(is_frozen(*game, idx_a), "a previously frozen piece should remain frozen as the band advances");
    assert(is_frozen(*game, idx_c), "a piece newly covered by the advanced threshold should freeze");
    assert(!is_frozen(*game, idx_b), "the tallest piece, poking above the new threshold, should stay dynamic");
    print("test_band_advancement ... ok\n");
}

test_thaw_when_height_drops :: ()
{
    game := make_test_game();

    idx_a := add_landed_piece_at_top(*game, 9 * CELL_SIZE);  // height 9 on its own
    idx_b := add_landed_piece_at_top(*game, 24 * CELL_SIZE); // tallest -> threshold 20
    update_piece_freezing(*game);
    assert(is_frozen(*game, idx_a), "setup: piece under the 20-line should freeze while the taller piece stands");
    assert(!is_frozen(*game, idx_b), "setup: tallest piece above the line stays dynamic");

    // Simulate height loss: the tallest piece falls into the void and is dropped from tracking,
    // the same way check_void_falls() removes a piece.
    for i : 0..game.tetris_pieces.count-1
    {
        if game.tetris_pieces[i].body_index == idx_b
        {
            array_unordered_remove_by_index(*game.tetris_pieces, i);
            break;
        }
    }

    update_piece_freezing(*game);

    assert(!is_frozen(*game, idx_a), "a piece should thaw once the tower height drops below its band");
    assert(game.world.bodies[idx_a].inverse_mass == 1.0 / PIECE_MASS, "a thawed piece must get its exact original mass back");
    print("test_thaw_when_height_drops ... ok\n");
}

test_straddling_piece_stays_dynamic :: ()
{
    game := make_test_game();

    // Center at 19 cells -> top at 21 cells (height 21 -> threshold 20), bottom at 17 cells.
    // The piece's own height sets the threshold, and its top pokes exactly 1 cell above it while
    // most of the piece sits well below - it must stay fully dynamic either way.
    idx := add_vertical_i_piece(*game, 19 * CELL_SIZE);

    update_piece_freezing(*game);

    assert(!is_frozen(*game, idx), "a piece must be entirely below the line to freeze, not just partially");
    print("test_straddling_piece_stays_dynamic ... ok\n");
}

test_falling_piece_never_frozen :: ()
{
    game := make_test_game();

    tall_idx   := add_landed_piece_at_top(*game, 24 * CELL_SIZE); // tallest -> threshold 20
    landed_idx := add_landed_piece_at_top(*game, 5 * CELL_SIZE);  // comfortably under the line

    falling_idx := add_tetromino(*game.world, .O, .{200, -550, 0}, CELL_SIZE, PIECE_MASS); // top = -500, deep below
    array_add(*game.tetris_pieces, .{falling_idx, .O, .Blue, false});
    game.in_game_info.current_piece_index = falling_idx;

    update_piece_freezing(*game);

    assert(is_frozen(*game, landed_idx), "sanity check: an ordinary landed piece below the line should still freeze");
    assert(!is_frozen(*game, tall_idx), "sanity check: the tallest piece defining the threshold pokes above it and stays dynamic");
    assert(!is_frozen(*game, falling_idx), "the currently falling piece must never be frozen, even if its position alone would qualify");
    print("test_falling_piece_never_frozen ... ok\n");
}

test_two_frozen_pieces_touching :: ()
{
    game := make_test_game();

    bottom_idx := add_landed_piece_at_top(*game, 9 * CELL_SIZE);  // height 9
    top_idx    := add_landed_piece_at_top(*game, 10 * CELL_SIZE); // height 10, directly stacked, tallest -> threshold 10

    update_piece_freezing(*game);
    assert(is_frozen(*game, bottom_idx), "bottom of two stacked frozen pieces should freeze");
    assert(is_frozen(*game, top_idx), "top of two stacked frozen pieces, exactly at the line, should also freeze");

    // Two static (inverse_mass == 0) bodies touching is already a safe no-op in the physics engine's
    // own contact-resolution guards - this just confirms the freeze bookkeeping agrees on a second pass.
    update_piece_freezing(*game);
    assert(is_frozen(*game, bottom_idx));
    assert(is_frozen(*game, top_idx));
    print("test_two_frozen_pieces_touching ... ok\n");
}

// Regression test for a Physics-engine bug (Physics/physics.jai's resolve_contact): the friction
// section used to update angular_velocity on both contact bodies unconditionally, without gating
// on inverse_mass == 0 the way every other term in that function does. That was invisible before
// this feature existed (the only inverse_mass == 0 body was the floor, whose inverse_inertia is
// coincidentally the zero matrix), but a frozen tetromino keeps its real, nonzero inverse_inertia -
// so without the gate, ordinary frictional contact could spin a "static" frozen piece in place.
// This exercises the real physics loop end-to-end (not just update_piece_freezing in isolation) to
// catch a regression in that engine-level guard specifically.
test_frozen_body_immune_to_friction_spin :: ()
{
    game := make_test_game();

    frozen_idx := add_tetromino(*game.world, .O, .{0, 200, 0}, CELL_SIZE, PIECE_MASS);
    frozen_body := *game.world.bodies[frozen_idx];
    frozen_body.friction = 0.5;
    frozen_body.inverse_mass = 0; // as update_piece_freezing would set on freeze
    frozen_body.velocity = .{};
    frozen_body.angular_velocity = .{};

    // Lands on top of the frozen piece (top = 200 + CELL_SIZE = 250; an O-piece is 2 cells/100
    // units tall, so a center at 302 puts its bottom just above that, at 252) while sliding
    // sideways, so both a normal contact and tangential (frictional) relative motion occur.
    slider_idx := add_tetromino(*game.world, .O, .{0, 302, 0}, CELL_SIZE, PIECE_MASS);
    game.world.bodies[slider_idx].friction = 0.5;
    game.world.bodies[slider_idx].velocity = .{100, 0, 0};

    for i : 0..29
        simulate_world(*game.world);

    frozen_after := game.world.bodies[frozen_idx];
    assert(frozen_after.angular_velocity.x == 0 && frozen_after.angular_velocity.y == 0 && frozen_after.angular_velocity.z == 0,
           "a frozen body must never pick up angular velocity from frictional contact");
    assert(frozen_after.velocity.x == 0 && frozen_after.velocity.y == 0 && frozen_after.velocity.z == 0,
           "a frozen body must never pick up linear velocity either");
    assert(frozen_after.position.x == 0 && frozen_after.position.y == 200 && frozen_after.position.z == 0,
           "a frozen body must not move at all while a dynamic body slides/lands on it");
    print("test_frozen_body_immune_to_friction_spin ... ok\n");
}

test_empty_tetris_pieces_after_reset :: ()
{
    game := make_test_game();
    assert(game.tetris_pieces.count == 0, "reset_game should leave no tracked pieces");
    assert(game.world.bodies.count == 1, "reset_game should leave only the floor body");

    update_piece_freezing(*game); // must not crash on an empty piece list

    assert(game.world.bodies.count == 1, "update_piece_freezing must not add/remove bodies");
    print("test_empty_tetris_pieces_after_reset ... ok\n");
}

main :: ()
{
    test_compute_freeze_threshold_cells();
    test_single_piece_freeze_boundary();
    test_freeze_at_exact_threshold();
    test_fast_moving_piece_not_frozen_even_below_threshold();
    test_piece_freezes_once_it_slows_down();
    test_band_advancement();
    test_thaw_when_height_drops();
    test_straddling_piece_stays_dynamic();
    test_falling_piece_never_frozen();
    test_two_frozen_pieces_touching();
    test_frozen_body_immune_to_friction_spin();
    test_empty_tetris_pieces_after_reset();

    print("All tests passed.\n");
}
