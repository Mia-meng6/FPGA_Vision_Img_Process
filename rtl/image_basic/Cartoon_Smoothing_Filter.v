`timescale 1ns/1ns
module Cartoon_Smoothing_Filter (
    input  wire         clk,
    input  wire         rst_n,
    input  wire         matrix_frame_vsync,
    input  wire         matrix_frame_href,
    input  wire         matrix_frame_clken,
    input  wire [7:0]   matrix_p11, matrix_p12, matrix_p13,
    input  wire [7:0]   matrix_p21, matrix_p22, matrix_p23,
    input  wire [7:0]   matrix_p31, matrix_p32, matrix_p33,
    input  wire [7:0]   smooth_threshold,
    output wire         smooth_frame_vsync,
    output wire         smooth_frame_href,
    output wire         smooth_frame_clken,
    output wire [7:0]   smooth_img_Y
);

reg [9:0] sum_row1, sum_row2, sum_row3; reg [7:0] center_p1;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin sum_row1 <= 0; sum_row2 <= 0; sum_row3 <= 0; center_p1 <= 0; end 
    else begin 
        sum_row1  <= matrix_p11 + matrix_p12 + matrix_p13;
        sum_row2  <= matrix_p21 + matrix_p22 + matrix_p23;
        sum_row3  <= matrix_p31 + matrix_p32 + matrix_p33;
        center_p1 <= matrix_p22;
    end
end

reg [11:0] sum_total; reg [7:0] center_p2;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin sum_total <= 0; center_p2 <= 0; end 
    else begin
        sum_total <= sum_row1 + sum_row2 + sum_row3; center_p2 <= center_p1;
    end
end

reg [18:0] mean_mult; reg [7:0] center_p3;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin mean_mult <= 0; center_p3 <= 0; end 
    else begin
        mean_mult <= sum_total * 8'd114; center_p3 <= center_p2;
    end
end

reg [7:0] mean_val; reg [7:0] center_p4; reg [7:0] diff_val;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin mean_val <= 0; center_p4 <= 0; diff_val <= 0; end 
    else begin
        mean_val  <= mean_mult[17:10];
        center_p4 <= center_p3;
        diff_val  <= (center_p3 >= mean_mult[17:10]) ? (center_p3 - mean_mult[17:10]) : (mean_mult[17:10] - center_p3);
    end
end

reg [7:0] final_pixel;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin final_pixel <= 0; end 
    else begin
        if (diff_val < smooth_threshold) final_pixel <= mean_val;
        else final_pixel <= center_p4; 
    end
end
assign smooth_img_Y = {final_pixel[7:3], 3'b000}; 

reg [4:0] vsync_r, href_r, clken_r;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin vsync_r <= 0; href_r <= 0; clken_r <= 0; end 
    else begin
        vsync_r <= {vsync_r[3:0], matrix_frame_vsync};
        href_r  <= {href_r[3:0],  matrix_frame_href};
        clken_r <= {clken_r[3:0], matrix_frame_clken};
    end
end
assign smooth_frame_vsync = vsync_r[4];
assign smooth_frame_href  = href_r[4];
assign smooth_frame_clken = clken_r[4];
endmodule