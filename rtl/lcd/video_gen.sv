module video_gen (
    input wire clk,

    input wire [9:0] active_width,
    input wire [9:0] active_height,
    input wire [4:0] lcd_pixel_size_x,
    input wire [4:0] lcd_pixel_size_y,
	 
    input wire [9:0] vblank_len,
    input wire [9:0] hblank_len,

    input wire [9:0] vblank_offset,
    input wire [9:0] hblank_offset,

    input wire [9:0] lcd_x_offset,
    input wire [9:0] lcd_y_offset,

    output reg [7:0] video_addr = 0,

    output reg [9:0] x = 0,
    output reg [9:0] y = 0,

    output wire [4:0] lcd_subpixel_x,
    output wire [4:0] lcd_subpixel_y,

    output wire [1:0] lcd_segment_row,

    output reg  vsync = 0,
    output reg  hsync = 0,
    output wire vblank,
    output wire hblank,

    output wire de
);
  
  wire crt_mode = (active_width == 10'd640);
  wire [9:0] hfront_porch = crt_mode ? 10'd16 : hblank_offset;
  wire [9:0] vfront_porch = crt_mode ? 10'd4  : vblank_offset;

  wire [9:0] hsync_start = active_width  + hfront_porch;
  wire [9:0] vsync_start = active_height + vfront_porch;

  wire [9:0] max_x = active_width  + hblank_len;
  wire [9:0] max_y = active_height + vblank_len;

  wire [9:0] hsync_len = crt_mode ? 10'd64 : 10'd1;
  wire [9:0] vsync_len = crt_mode ? 10'd3  : 10'd1;
  
  initial begin
    $display("video_gen runtime-timed build");
  end

  reg [4:0] pixel_count_x = 0;
  reg [4:0] pixel_count_y = 0;

  reg [4:0] lcd_x = 0;
  reg [3:0] lcd_y = 0;

  assign lcd_subpixel_x = pixel_count_x;
  assign lcd_subpixel_y = pixel_count_y;

  assign lcd_segment_row = lcd_y[1:0];

  assign de = x < active_width && y < active_height;

  assign vblank = y >= active_height;
  assign hblank = x >= active_width;

  // Map from an LCD X coordinate to the actual column of memory used
  function [5:0] lcd_column_addr(reg [5:0] x_coord);
    // const reverse_map = [
    //       0, 1, 2, 3, 4, 5, 6, 7, 9, 10, 11, 12, 13, 14, 15, 16, 36, 35, 34, 33,
    //       32, 31, 30, 29, 27, 26, 25, 24, 23, 22, 21, 20, 8, 17, 18, 19, 28, 37,
    //       38, 39,
    //     ];
    case (x_coord)
      0:  return 0;
      1:  return 1;
      2:  return 2;
      3:  return 3;
      4:  return 4;
      5:  return 5;
      6:  return 6;
      7:  return 7;
      8:  return 9;
      9:  return 10;
      10: return 11;
      11: return 12;
      12: return 13;
      13: return 14;
      14: return 15;
      15: return 16;
      16: return 36;
      17: return 35;
      18: return 34;
      19: return 33;
      20: return 32;
      21: return 31;
      22: return 30;
      23: return 29;
      24: return 27;
      25: return 26;
      26: return 25;
      27: return 24;
      28: return 23;
      29: return 22;
      30: return 21;
      31: return 20;
      32: return 8;
      33: return 17;
      34: return 18;
      35: return 19;
      36: return 28;
      37: return 37;
      38: return 38;
      39: return 39;
    endcase
  endfunction

  always @(posedge clk) begin
    reg [9:0] next_x;
    reg [9:0] next_y;
    reg [4:0] next_lcd_x;
    reg [3:0] next_lcd_y;
    reg [7:0] temp_video_addr;

    next_x = x + 10'd1;
    next_y = y;

    if (next_x == max_x) begin
      next_x = 10'd0;
      next_y = y + 10'd1;

      if (next_y == max_y) begin
        next_y = 10'd0;
      end
    end

    hsync <= (next_x >= hsync_start) && (next_x < (hsync_start + hsync_len));
    vsync <= (next_y >= vsync_start) && (next_y < (vsync_start + vsync_len));

    if (next_x == hsync_start) begin
      lcd_x <= 0;
      pixel_count_x <= 0;
    end

    if ((next_y == vsync_start) && (next_x == 10'd0)) begin
      lcd_y <= 0;
      pixel_count_y <= 0;
    end

    x <= next_x;
    y <= next_y;
    next_lcd_x = lcd_x;
    next_lcd_y = lcd_y;

    if (next_x >= lcd_x_offset && next_x < active_width - lcd_x_offset && next_y >= lcd_y_offset && next_y < active_height - lcd_y_offset) begin
      pixel_count_x <= pixel_count_x + 5'b1;

      if (pixel_count_x == lcd_pixel_size_x - 5'b1) begin
        // End of this pixel horizontally
        pixel_count_x <= 0;

        next_lcd_x = lcd_x + 5'b1;

        if (lcd_x == 5'd31) begin
          // End of row
          next_lcd_x = 0;

          pixel_count_y <= pixel_count_y + 5'b1;

          if (pixel_count_y == lcd_pixel_size_y - 5'b1) begin
            // End of this pixel vertically
            pixel_count_y <= 0;

            next_lcd_y = lcd_y + 4'b1;

            if (lcd_y == 4'd15) begin
              // End of column
              next_lcd_y = 0;
            end
          end
        end
      end

      lcd_x <= next_lcd_x;
      lcd_y <= next_lcd_y;
    end

    // Upper bits are column address, lowest bit is whether it's Y=0 or Y=4
    temp_video_addr = {1'b0, lcd_column_addr({1'b0, next_lcd_x[4:0]}), next_lcd_y[2]};

    // If Y >= 8, it's in second RAM bank
    if (next_lcd_y >= 8) begin
      temp_video_addr = temp_video_addr + 8'h50;
    end

    video_addr <= temp_video_addr;
  end

endmodule
