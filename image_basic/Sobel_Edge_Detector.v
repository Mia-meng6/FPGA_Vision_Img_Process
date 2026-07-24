// =============================================================================
// Module Name : Sobel_Edge_Detector
// Function    : Real-time Sobel edge detection with 3x3 convolution kernel
// Algorithm   : |G| = |Gx| + |Gy|
//               Gx = [+1 0 -1; +2 0 -2; +1 0 -1] * window
//               Gy = [+1 +2 +1; 0 0 0; -1 -2 -1] * window
// Pipeline    : 4-stage (Gx/Gy compute -> abs -> sum -> threshold compare)
// Latency     : 4 clock cycles
// Throughput  : 1 pixel/cycle
// Clock Domain: ov5640_pclk (24MHz)
// =============================================================================
`timescale 1ns/1ns
module Sobel_Edge_Detector (
    input  wire         clk,                    // pixel clock (24MHz)
    input  wire         rst_n,                  // async reset, active low
    // 3x3 convolution window input
    input  wire         matrix_frame_vsync,     // frame vsync
    input  wire         matrix_frame_href,      // horizontal reference
    input  wire         matrix_frame_clken,      // data valid
    input  wire [7:0]   matrix_p11, matrix_p12, matrix_p13,  // row1: p11 p12 p13
    input  wire [7:0]   matrix_p21, matrix_p22, matrix_p23,  // row2: p21 p22 p23
    input  wire [7:0]   matrix_p31, matrix_p32, matrix_p33,  // row3: p31 p32 p33
    input  wire [7:0]   sobel_threshold,        // edge detection threshold (0-255)
    // Edge detection output
    output wire         sobel_frame_vsync,      // frame vsync (aligned)
    output wire         sobel_frame_href,       // horizontal ref (aligned)
    output wire         sobel_frame_clken,      // output data valid
    output wire         sobel_edge_bit           // edge flag: 1=edge, 0=flat
);

reg [9:0] Gx_pos, Gx_neg, Gy_pos, Gy_neg;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin Gx_pos <= 0; Gx_neg <= 0; Gy_pos <= 0; Gy_neg <= 0; end 
    else begin // 剔除 clken
        Gx_pos <= matrix_p13 + {matrix_p23, 1'b0} + matrix_p33;
        Gx_neg <= matrix_p11 + {matrix_p21, 1'b0} + matrix_p31;
        Gy_pos <= matrix_p11 + {matrix_p12, 1'b0} + matrix_p13;
        Gy_neg <= matrix_p31 + {matrix_p32, 1'b0} + matrix_p33;
    end
end

reg [9:0] Gx_abs, Gy_abs;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin Gx_abs <= 0; Gy_abs <= 0; end 
    else begin
        Gx_abs <= (Gx_pos >= Gx_neg) ? (Gx_pos - Gx_neg) : (Gx_neg - Gx_pos);
        Gy_abs <= (Gy_pos >= Gy_neg) ? (Gy_pos - Gy_neg) : (Gy_neg - Gy_pos);
    end
end

reg [10:0] G_total;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin G_total <= 0; end 
    else begin G_total <= Gx_abs + Gy_abs; end
end

reg edge_flag;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin edge_flag <= 0; end 
    else begin
        if (G_total > sobel_threshold) edge_flag <= 1'b1;
        else edge_flag <= 1'b0;
    end
end
assign sobel_edge_bit = edge_flag;

// 对齐时钟
reg [3:0] vsync_r, href_r, clken_r;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin vsync_r <= 0; href_r <= 0; clken_r <= 0; end 
    else begin
        vsync_r <= {vsync_r[2:0], matrix_frame_vsync};
        href_r  <= {href_r[2:0],  matrix_frame_href};
        clken_r <= {clken_r[2:0], matrix_frame_clken};
    end
end
assign sobel_frame_vsync = vsync_r[3];
assign sobel_frame_href  = href_r[3];
assign sobel_frame_clken = clken_r[3];
endmodule