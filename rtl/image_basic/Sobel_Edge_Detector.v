`timescale 1ns/1ns
module Sobel_Edge_Detector (
    input  wire         clk,
    input  wire         rst_n,
    input  wire         matrix_frame_vsync,
    input  wire         matrix_frame_href,
    input  wire         matrix_frame_clken,
    input  wire [7:0]   matrix_p11, matrix_p12, matrix_p13,
    input  wire [7:0]   matrix_p21, matrix_p22, matrix_p23,
    input  wire [7:0]   matrix_p31, matrix_p32, matrix_p33,
    input  wire [7:0]   sobel_threshold,
    output wire         sobel_frame_vsync,
    output wire         sobel_frame_href,
    output wire         sobel_frame_clken,
    output wire         sobel_edge_bit
);

reg [9:0] Gx_pos, Gx_neg, Gy_pos, Gy_neg;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin Gx_pos <= 0; Gx_neg <= 0; Gy_pos <= 0; Gy_neg <= 0; end 
    else begin 
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