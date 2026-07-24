module skin_dilate (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        mask_in,
    input  wire        din_valid,
    output reg         mask_out
);

parameter H_ACTIVE = 640;

reg [0:H_ACTIVE-1] line_buf0;
reg [0:H_ACTIVE-1] line_buf1;
reg [9:0] col_cnt;
wire wr_en = din_valid;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
        col_cnt <= 10'd0;
    else if (!din_valid)
        col_cnt <= 10'd0;
    else if (col_cnt < H_ACTIVE - 1)
        col_cnt <= col_cnt + 1'b1;
end

always @(posedge clk) begin
    if (wr_en) begin
        line_buf0[col_cnt] <= mask_in;
        line_buf1[col_cnt] <= line_buf0[col_cnt];
    end
end

reg m11, m12, m13;
reg m21, m22, m23;
reg m31, m32, m33;

wire mask_cur = mask_in;
wire mask_row1 = line_buf0[col_cnt];
wire mask_row2 = line_buf1[col_cnt];

always @(posedge clk) begin
    if (wr_en) begin
        m31 <= mask_row2;
        m32 <= m31;
        m33 <= m32;
        m21 <= mask_row1;
        m22 <= m21;
        m23 <= m22;
        m11 <= mask_cur;
        m12 <= m11;
        m13 <= m12;
    end else begin
        m11 <= 1'b0; m12 <= 1'b0; m13 <= 1'b0;
        m21 <= 1'b0; m22 <= 1'b0; m23 <= 1'b0;
        m31 <= 1'b0; m32 <= 1'b0; m33 <= 1'b0;
    end
end

wire window_has_one = (m11 | m12 | m13 | m21 | m22 | m23 | m31 | m32 | m33);

always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
        mask_out <= 1'b0;
    else if (din_valid)
        mask_out <= window_has_one;
    else
        mask_out <= 1'b0;
end

endmodule