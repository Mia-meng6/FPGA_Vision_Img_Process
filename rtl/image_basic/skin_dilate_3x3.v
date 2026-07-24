module skin_dilate_3x3 #(
    parameter IMG_WIDTH = 640
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        iDataEnable,
    input  wire        din,
    output wire        dout
);
    reg [IMG_WIDTH-1:0] line0;
    reg [IMG_WIDTH-1:0] line1;
    reg [9:0] col_cnt;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            col_cnt <= 10'd0;
        else if (!iDataEnable)
            col_cnt <= 10'd0;
        else if (col_cnt < IMG_WIDTH - 1)
            col_cnt <= col_cnt + 1'b1;
    end

    always @(posedge clk) begin
        if (iDataEnable) begin
            line0[col_cnt] <= din;
            line1[col_cnt] <= line0[col_cnt];
        end
    end

    reg m11,m12,m13, m21,m22,m23, m31,m32,m33;
    wire mask_cur = din;
    wire mask_row0 = line0[col_cnt];
    wire mask_row1 = line1[col_cnt];

    always @(posedge clk) begin
        if (iDataEnable) begin
            {m31, m32, m33} <= {mask_row1, m31, m32};
            {m21, m22, m23} <= {mask_row0, m21, m22};
            {m11, m12, m13} <= {mask_cur, m11, m12};
        end else begin
            {m11,m12,m13,m21,m22,m23,m31,m32,m33} <= 9'd0;
        end
    end

    wire window_has_one = |{m11,m12,m13,m21,m22,m23,m31,m32,m33};
    reg dout_r;
    always @(posedge clk) dout_r <= window_has_one;
    assign dout = dout_r;   
endmodule