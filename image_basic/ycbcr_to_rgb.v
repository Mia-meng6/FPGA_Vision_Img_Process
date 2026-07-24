`timescale 1ns/1ps
module ycbcr_to_rgb(
    input clk,
    input [7:0] i_y_8b, i_cb_8b, i_cr_8b,
    input i_h_sync, i_v_sync, i_data_en,
    output [7:0] o_r_8b, o_g_8b, o_b_8b,
    output o_h_sync, o_v_sync, o_data_en
);
    reg [2:0] hs_d, vs_d, de_d;
    always @(posedge clk) begin
        hs_d <= {hs_d[1:0], i_h_sync};
        vs_d <= {vs_d[1:0], i_v_sync};
        de_d <= {de_d[1:0], i_data_en};
    end
    reg signed [11:0] cr_128, cb_128, y_sub_16;
    always @(posedge clk) begin
        cr_128   <= $signed({1'b0, i_cr_8b}) - 12'sd128;
        cb_128   <= $signed({1'b0, i_cb_8b}) - 12'sd128;
        y_sub_16 <= $signed({1'b0, i_y_8b}) - 12'sd16; 
    end

    // R = 1.164*(Y-16) + 1.793*(Cr-128)
    // G = 1.164*(Y-16) - 0.213*(Cb-128) - 0.533*(Cr-128)
    // B = 1.164*(Y-16) + 2.112*(Cb-128)
    reg signed [21:0] r_tmp, g_tmp, b_tmp;
    always @(posedge clk) begin
        r_tmp <= (y_sub_16 * 22'sd298) + (cr_128 * 22'sd459);
        g_tmp <= (y_sub_16 * 22'sd298) - (cb_128 * 22'sd55) - (cr_128 * 22'sd136);
        b_tmp <= (y_sub_16 * 22'sd298) + (cb_128 * 22'sd541);
    end

    reg [7:0] r_out, g_out, b_out;
    always @(posedge clk) begin
        // 255 << 8 = 65280
        if (r_tmp < 0) r_out <= 8'd0;
        else if (r_tmp > 22'sd65280) r_out <= 8'd255;
        else r_out <= r_tmp[15:8];

        if (g_tmp < 0) g_out <= 8'd0;
        else if (g_tmp > 22'sd65280) g_out <= 8'd255;
        else g_out <= g_tmp[15:8];

        if (b_tmp < 0) b_out <= 8'd0;
        else if (b_tmp > 22'sd65280) b_out <= 8'd255;
        else b_out <= b_tmp[15:8];
    end

    assign o_r_8b = r_out;
    assign o_g_8b = g_out;
    assign o_b_8b = b_out;
    assign o_h_sync = hs_d[2];
    assign o_v_sync = vs_d[2];
    assign o_data_en = de_d[2];
endmodule