// =============================================================================
// Module Name : VIP_Matrix_Generate_3X3_8Bit
// Function    : 3x3 sliding window generator for 8-bit grayscale image processing
// Architecture: 2-line buffer (Line_Shift_RAM_8Bit) + 9 pixel registers
//               Row timing: row3(newest) -> row2 -> row1(oldest)
//               The window slides pixel-by-pixel in raster-scan order
// Latency     : 2 line periods for buffer fill, then 1 pixel/cycle output
// Use Cases   : Filtering (smooth/median), edge detection, morphology, etc.
// Clock Domain: Typically ov5640_pclk (24MHz)
// =============================================================================
`timescale 1ns/1ns
module VIP_Matrix_Generate_3X3_8Bit #(
    parameter IMG_HDISP = 10'd640               // image horizontal resolution
)(
    input  wire         clk,                    // pixel clock
    input  wire         rst_n,                  // async reset, active low
    // Pixel stream input
    input  wire         per_frame_vsync,        // frame vsync
    input  wire         per_frame_href,         // horizontal reference (line valid)
    input  wire         per_frame_clken,        // pixel data valid
    input  wire [7:0]   per_img_Y,              // 8-bit grayscale pixel in
    // 3x3 window output
    output wire         matrix_frame_vsync,      // frame vsync (1 cycle delayed)
    output wire         matrix_frame_href,       // horizontal ref (1 cycle delayed)
    output wire         matrix_frame_clken,      // window data valid
    output reg  [7:0]   matrix_p11, matrix_p12, matrix_p13,   // row1 (oldest)
    output reg  [7:0]   matrix_p21, matrix_p22, matrix_p23,   // row2
    output reg  [7:0]   matrix_p31, matrix_p32, matrix_p33    // row3 (newest)
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