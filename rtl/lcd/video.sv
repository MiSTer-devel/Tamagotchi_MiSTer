module video #(
    parameter WIDTH = 10'd360,
    parameter HEIGHT = 10'd360,
    parameter LCD_PIXEL_SIZE = 5'd11,

    parameter VBLANK_LEN = 10'd132,
    parameter HBLANK_LEN = 10'd84,

    parameter VBLANK_OFFSET = 10'd5,
    parameter HBLANK_OFFSET = 10'd5
) (
    input wire clk,
    input wire crt_15k_mode,

    output wire [7:0] video_addr,
    input  wire [3:0] video_data,

    input wire background_write_en,
    input wire spritesheet_write_en,
    input wire [16:0] image_write_addr,
    input wire [15:0] image_write_data,

    // Settings
    input wire show_pixel_dividers,
    input wire show_pixel_grid_background,

    input wire show_turbo_ui,
    input wire [2:0] turbo_speed,

    output wire vsync,
    output wire hsync,
    output wire vblank,
    output wire hblank,

    output wire de,
    output wire [23:0] rgb
);
  wire [9:0] active_width        = crt_15k_mode ? 10'd640 : WIDTH;
  wire [9:0] active_height       = crt_15k_mode ? 10'd240 : HEIGHT;

  wire [4:0] lcd_pixel_size_x_eff = crt_15k_mode ? 5'd15 : LCD_PIXEL_SIZE;
  wire [4:0] lcd_pixel_size_y_eff = crt_15k_mode ? 5'd7  : LCD_PIXEL_SIZE;

  wire [9:0] hblank_len_eff      = crt_15k_mode ? 10'd192 : HBLANK_LEN;
  wire [9:0] vblank_len_eff      = crt_15k_mode ? 10'd22  : VBLANK_LEN;

  wire [9:0] lcd_x_offset_eff    = (active_width  - (10'd32 * lcd_pixel_size_x_eff)) >> 1;
  wire [9:0] lcd_y_offset_eff    = (active_height - (10'd16 * lcd_pixel_size_y_eff)) >> 1;
  
  wire [9:0] horizontal_total   = active_width + hblank_len_eff;
  wire [9:0] vertical_total     = active_height + vblank_len_eff;

  wire [15:0] background_pixel_rgb565;
  wire [23:0] background_pixel_rgb888;

  wire [9:0] video_x;
  wire [9:0] video_y;
  wire [1:0] lcd_segment_row;

  wire [31:0] lcd_pixel;

  wire active_sprite_pixel;
  wire [7:0] sprite_alpha_pixel;

  wire [23:0] background_pixel_with_lcd;
  wire [23:0] background_pixel_with_sprite;
  wire [23:0] background_lcd_with_sprite;

  wire [7:0] sprite_enable_status;

  rgb565_to_rgb888 background_color_conversion (
      .rgb565(background_pixel_rgb565),
      .rgb888(background_pixel_rgb888)
  );

  alpha_blend lcd_alpha_blend (
      .background_pixel(background_pixel_rgb888),
      .foreground_pixel(lcd_pixel),
      .output_pixel(background_pixel_with_lcd)
  );

  wire [23:0] ui_rgb;
  wire ui_active;

  // The LCD and the sprites never overlap, so produce their results in parallel, then choose which one to use later

  alpha_blend sprite_alpha_blend (
      .background_pixel(background_pixel_rgb888),
      .foreground_pixel(active_sprite_pixel ? {24'b0, sprite_alpha_pixel} : 0),
      .output_pixel(background_pixel_with_sprite)
  );

  alpha_blend sprite_over_lcd_alpha_blend (
      .background_pixel(background_pixel_with_lcd),
      .foreground_pixel(active_sprite_pixel ? {24'b0, sprite_alpha_pixel} : 0),
      .output_pixel(background_lcd_with_sprite)
  );
  
  wire end_of_line  = (video_x == horizontal_total - 10'd1);
  wire end_of_frame = (video_y == vertical_total   - 10'd1);

  wire [9:0] raster_fetch_x = end_of_line ? 10'd0 : (video_x + 10'd1);
  wire [9:0] raster_fetch_y = end_of_line ? (end_of_frame ? 10'd0 : (video_y + 10'd1)) : video_y;

  wire [9:0] active_fetch_x = (raster_fetch_x < active_width)  ? raster_fetch_x : 10'd0;
  wire [9:0] active_fetch_y = (raster_fetch_y < active_height) ? raster_fetch_y : 10'd0;

  wire [9:0] crt_content_x_start = 10'd80;
  wire [9:0] crt_content_width   = 10'd480;

  wire crt_content_active = !crt_15k_mode || ((active_fetch_x >= crt_content_x_start) && (active_fetch_x <  crt_content_x_start + crt_content_width));
  wire [9:0] content_fetch_x = crt_15k_mode ? (crt_content_active ? (active_fetch_x - crt_content_x_start) : 10'd0) : active_fetch_x;

  wire [9:0] content_fetch_y = active_fetch_y;
  wire [9:0] source_fetch_x = crt_15k_mode ? ((content_fetch_x * 3) >> 2) : active_fetch_x;

  wire [9:0] source_fetch_y = crt_15k_mode ? ((active_fetch_y * 3) >> 1) : active_fetch_y;
  
  wire [9:0] sprite_fetch_x = crt_15k_mode ? (crt_content_active ? source_fetch_x : 10'h3FF) : source_fetch_x;

  wire [9:0] sprite_fetch_y = crt_15k_mode ? source_fetch_y : source_fetch_y;
  
  wire lcd_space_active = !crt_15k_mode || crt_content_active;

  wire [9:0] lcd_space_x        = lcd_space_active ? (crt_15k_mode ? content_fetch_x : active_fetch_x) : 10'h3FF;
  wire [9:0] lcd_space_y        = active_fetch_y;
  wire [9:0] lcd_space_width    = crt_15k_mode ? crt_content_width : active_width;
  wire [9:0] lcd_space_height   = active_height;
  wire [9:0] lcd_space_x_offset = crt_15k_mode ? 10'd0 : lcd_x_offset_eff;
  wire [9:0] lcd_space_y_offset = lcd_y_offset_eff;

  wire is_lcd =
      lcd_space_active &&
      (lcd_space_x >= lcd_space_x_offset) &&
      (lcd_space_x <  lcd_space_width  - lcd_space_x_offset) &&
      (lcd_space_y >= lcd_space_y_offset) &&
      (lcd_space_y <  lcd_space_height - lcd_space_y_offset);

  wire [23:0] main_rgb =
      crt_15k_mode ? 
      (crt_content_active ? (is_lcd ? background_lcd_with_sprite : background_pixel_with_sprite) : 24'b0) :
      (is_lcd ? background_pixel_with_lcd : background_pixel_with_sprite);
	
  assign rgb = (crt_15k_mode && !crt_content_active) ? 24'b0 : (show_turbo_ui && ui_active ? ui_rgb : main_rgb);

  sprites #(
      .WIDTH(WIDTH)
  ) sprites (
      .clk(clk),

      .video_x(sprite_fetch_x),
      .video_y(sprite_fetch_y),

      .sprite_enable_status(sprite_enable_status),

      .image_write_en  (spritesheet_write_en),
      .image_write_addr(image_write_addr[14:0]),
      .image_write_data(image_write_data[7:0]),

      .active_pixel(active_sprite_pixel),
      .pixel_alpha (sprite_alpha_pixel)
  );

  image_memory #(
      .MEM_WIDTH(WIDTH),
      .MEM_HEIGHT(HEIGHT),
      .SPRITE_WIDTH(WIDTH),
      .SPRITE_HEIGHT(HEIGHT),
      // No alpha needed
      .PIXEL_BIT_COUNT(16)
  ) background (
      .clk(clk),

      .sprite(0),
      .x(source_fetch_x),
      .y(source_fetch_y),

      .image_write_en  (background_write_en),
      .image_write_addr(image_write_addr),
      .image_write_data(image_write_data),

      .pixel(background_pixel_rgb565)
  );

  wire [4:0] lcd_subpixel_x;
  wire [4:0] lcd_subpixel_y;

  wire [7:0] lcd_video_addr;
  wire [3:0] lcd_video_data;

  lcd #(
      .WIDTH(WIDTH),
      .HEIGHT(HEIGHT),
      .LCD_X_OFFSET((WIDTH - 32 * LCD_PIXEL_SIZE) / 2),
      .LCD_Y_OFFSET((HEIGHT - 16 * LCD_PIXEL_SIZE) / 2)
  ) lcd (
      .clk(clk),

      .video_x(lcd_space_x),
      .video_y(lcd_space_y),
      .active_width(lcd_space_width),
      .active_height(lcd_space_height),
      .lcd_x_offset(lcd_space_x_offset),
      .lcd_y_offset(lcd_space_y_offset),

      .lcd_subpixel_x(lcd_subpixel_x),
      .lcd_subpixel_y(lcd_subpixel_y),

      .lcd_segment_row(lcd_segment_row),
      .video_data(lcd_video_data),

      // Settings
      .show_pixel_dividers(show_pixel_dividers),
      .show_pixel_grid_background(show_pixel_grid_background),

      .pixel(lcd_pixel)
  );

  frame_ram frame_ram (
      .clk(clk),

      .frame_addr(lcd_video_addr),
      .frame_data(lcd_video_data),

      .sprite_enable_status(sprite_enable_status),

      .cpu_video_addr(video_addr),
      .cpu_video_data(video_data),

      .vsync(vsync)
  );

  ui ui (
      .clk(clk),

      .video_fetch_x(source_fetch_x),
      .video_fetch_y(source_fetch_y),

      // Settings
      .turbo_speed(turbo_speed),

      .active (ui_active),
      .vid_out(ui_rgb)
  );

  video_gen video_gen (
      .clk(clk),

      .active_width(active_width),
      .active_height(active_height),
      .lcd_pixel_size_x(lcd_pixel_size_x_eff),
      .lcd_pixel_size_y(lcd_pixel_size_y_eff),

      .vblank_len(vblank_len_eff),
      .hblank_len(hblank_len_eff),

      .vblank_offset(VBLANK_OFFSET),
      .hblank_offset(HBLANK_OFFSET),

      .lcd_x_offset(lcd_x_offset_eff),
      .lcd_y_offset(lcd_y_offset_eff),

      .video_addr(lcd_video_addr),

      .x(video_x),
      .y(video_y),

      .lcd_subpixel_x(lcd_subpixel_x),
      .lcd_subpixel_y(lcd_subpixel_y),

      .lcd_segment_row(lcd_segment_row),

      .vsync (vsync),
      .hsync (hsync),
      .vblank(vblank),
      .hblank(hblank),

      .de(de)
  );

endmodule
