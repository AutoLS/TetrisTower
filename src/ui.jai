text_button :: (text: string, position: Vector2, font_size: s32, color: Color) -> bool
{
    text_width := MeasureText(temp_c_string(text), font_size);
    scale := Vector2.{xx text_width, xx font_size};
    p := left_corner(position, scale);
    rect := Rectangle.{p.x, p.y, xx text_width, xx font_size};

    cursor := GetMousePosition();

    if point_in_rect(cursor, rect)
    {
        //DrawText("true", 0, font_size*2, font_size, color);
        DrawText(temp_c_string(text), xx p.x, xx p.y, font_size, .{color.r, color.g, color.b, 100});

        if IsMouseButtonPressed(.MOUSE_BUTTON_LEFT) return true;
    }
    else
    {
        DrawText(temp_c_string(text), xx p.x, xx p.y, font_size, color);
    }

    //DrawRectangle(xx position.x, xx position.y, text_width, font_size, color);

    //DrawText(temp_c_string(tprint("(%, %)", cursor.x, cursor.y)), 0, 0, font_size, color);
    //DrawText(temp_c_string(tprint("(%, %)", rect.x, rect.y)), 0, font_size, font_size, color);

    return false;
}

//Auto: Position by default is left corner instead of center like everything else
slider :: (label: string, position: Vector2, data: *float, min_v: float, max_v: float) -> bool
{
    modified: bool;
    font_size: s32 = 40;
    text_width := MeasureText(temp_c_string(label), font_size);

    DrawText(temp_c_string(label), xx position.x, xx position.y, font_size, BLACK);

    line_width := 200;
    line_pos_start := position + Vector2.{text_width + 5.0, font_size*0.5};
    line_pos_end := line_pos_start + Vector2.{xx line_width, 0};

    DrawLineV(line_pos_start, line_pos_end, BLACK);

    slider_button_width := 20;
    slider_button_y := line_pos_start.y - font_size*0.5;

    slider_rect := Rectangle.{line_pos_start.x, line_pos_start.y - (font_size*0.5), xx line_width, xx font_size};

    cursor := GetMousePosition();

    if point_in_rect(cursor, slider_rect) && IsMouseButtonDown(.MOUSE_BUTTON_LEFT)
    {
        t := (cursor.x - (line_pos_start.x + slider_button_width*0.5)) /
             (xx (line_width - slider_button_width));
        t = max(min(t, 1.0), 0.0);
        << data = lerp(min_v, max_v, t);

        modified = true;
    }

    t := ((<< data) - min_v) / (max_v - min_v);
    slider_button_x := lerp(line_pos_start.x, line_pos_end.x - slider_button_width, t);

    DrawRectangle(xx slider_button_x, xx slider_button_y, xx slider_button_width, font_size, BLACK);

    return modified;
}