`timescale 1ns/1ns
module VIP_Matrix_Generate_3X3_8Bit #(
    parameter IMG_HDISP = 10'd640
)(
    input  wire         clk,
    input  wire         rst_n,
    input  wire         per_frame_vsync,
    input  wire         per_frame_href,
    input  wire         per_frame_clken,
    input  wire [7:0]   per_img_Y,

    output wire         matrix_frame_vsync,
    output wire         matrix_frame_href,
    output wire         matrix_frame_clken,
    output reg  [7:0]   matrix_p11, matrix_p12, matrix_p13,
    output reg  [7:0]   matrix_p21, matrix_p22, matrix_p23,
    output reg  [7:0]   matrix_p31, matrix_p32, matrix_p33
);

    wire [7:0] row2_data, row3_data;
    reg  [7:0] row1_data_d;
    
    always @(posedge clk) begin
        if (per_frame_clken) row1_data_d <= per_img_Y;
    end

    Line_Shift_RAM_8Bit #(.RAM_DEPTH(IMG_HDISP)) u_Line_Shift_1 (.clock(clk), .clken(per_frame_clken), .shiftin(per_img_Y), .shiftout(row2_data));
    Line_Shift_RAM_8Bit #(.RAM_DEPTH(IMG_HDISP)) u_Line_Shift_2 (.clock(clk), .clken(per_frame_clken), .shiftin(row2_data), .shiftout(row3_data));

    reg read_clken;
    always @(posedge clk) read_clken <= per_frame_clken;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            {matrix_p11, matrix_p12, matrix_p13} <= 24'd0;
            {matrix_p21, matrix_p22, matrix_p23} <= 24'd0;
            {matrix_p31, matrix_p32, matrix_p33} <= 24'd0;
        end else if (read_clken) begin
            {matrix_p11, matrix_p12, matrix_p13} <= {matrix_p12, matrix_p13, row3_data};
            {matrix_p21, matrix_p22, matrix_p23} <= {matrix_p22, matrix_p23, row2_data};
            {matrix_p31, matrix_p32, matrix_p33} <= {matrix_p32, matrix_p33, row1_data_d};
        end
    end

    reg [1:0] vsync_r, href_r, clken_r;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin vsync_r <= 2'b0; href_r <= 2'b0; clken_r <= 2'b0; end 
        else begin
            vsync_r <= {vsync_r[0], per_frame_vsync};
            href_r  <= {href_r[0],  per_frame_href};
            clken_r <= {clken_r[0], per_frame_clken};
        end
    end
    assign matrix_frame_vsync = vsync_r[1];
    assign matrix_frame_href  = href_r[1];
    assign matrix_frame_clken = clken_r[1];

endmodule