`timescale 1ns / 1ps
module Histogram_top(
    input           clk         ,
    input           rst_n       ,
    input   [23:0]  i_rgb       ,
    input           i_vsync     ,
    input           i_hsync     ,
    input           i_valid     ,
    output  [7:0]   o_y         ,
    output          o_vsync     ,
    output          o_hsync     ,
    output          o_valid
    );
    
    wire [19:0] i_histogram;
    wire        i_histogram_valid;
    wire [7:0]  y_o;
    wire        o_valid_r;
    wire        o_hsync_r;
    wire        o_vsync_r;
    
    RGB2YUV RGB2YUV_u(
        .clk     (clk),
        .rst_n   (rst_n),
        .i_rgb   (i_rgb),
        .i_valid (i_valid),
        .i_hsync (i_hsync),
        .i_vsync (i_vsync),
        .o_y     (y_o),
        .o_valid (o_valid_r),
        .o_hsync (o_hsync_r),
        .o_vsync (o_vsync_r)
    );
    
    histogram_adjust histogram_adjust_u(
        .clk               (clk),
        .rst_n             (rst_n),
        .i_y               (y_o),
        .i_valid           (o_valid_r),
        .i_hsync           (o_hsync_r),
        .i_vsync           (o_vsync_r),
        .o_histogram       (i_histogram),
        .o_histogram_valid (i_histogram_valid)
    );
    
    equalization equalization_u(
        .clk                (clk),
        .rst_n              (rst_n),
        .i_y                (y_o),
        .i_valid            (o_valid_r),
        .i_hsync            (o_hsync_r),
        .i_vsync            (o_vsync_r),
        .o_y                (o_y),
        .o_valid            (o_valid),
        .o_hsync            (o_hsync),
        .o_vsync            (o_vsync),
        .i_histogram        (i_histogram),
        .i_histogram_valid  (i_histogram_valid)
    );
    
endmodule