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