`timescale 1ns/1ps
// =============================================================================
// Module  : bilateral_filter
// =============================================================================
module bilateral_filter #(
    parameter IMG_WIDTH = 640
)(
    input  wire           clk,
    input  wire           rst_n,
    input  wire           iHSync,
    input  wire           iVSync,
    input  wire           iDataEnable,
    input  wire  [7:0]    iData,
    output wire           oHSync,
    output wire           oVSync,
    output wire           oDataEnable,
    output wire  [7:0]    oData
);

    wire [7:0] p11, p12, p13, p21, p22, p23, p31, p32, p33;

    line_buffer_3x3 #(
        .IMG_WIDTH (IMG_WIDTH)
    ) u_lbuf (
        .clk         (clk),
        .rst_n       (rst_n),
        .iDataEnable (iDataEnable),
        .din         (iData),
        .p11(p11), .p12(p12), .p13(p13),
        .p21(p21), .p22(p22), .p23(p23),
        .p31(p31), .p32(p32), .p33(p33)
    );

    function [6:0] range_lut;
        input [7:0] d;
        begin
            if      (d <  10) range_lut = 7'd127;
            else if (d <  20) range_lut = 7'd112;
            else if (d <  30) range_lut = 7'd96;
            else if (d <  50) range_lut = 7'd72;
            else if (d <  80) range_lut = 7'd40;
            else if (d < 120) range_lut = 7'd16;
            else              range_lut = 7'd4;
        end
    endfunction

    reg [7:0] d11, d12, d13, d21, d23, d31, d32, d33;
    reg [7:0] px11, px12, px13, px21, px22, px23, px31, px32, px33;

    always @(posedge clk) begin
        px11 <= p11; px12 <= p12; px13 <= p13;
        px21 <= p21; px22 <= p22; px23 <= p23;
        px31 <= p31; px32 <= p32; px33 <= p33;

        d11 <= (p11 > p22) ? (p11 - p22) : (p22 - p11);
        d12 <= (p12 > p22) ? (p12 - p22) : (p22 - p12);
        d13 <= (p13 > p22) ? (p13 - p22) : (p22 - p13);
        d21 <= (p21 > p22) ? (p21 - p22) : (p22 - p21);
        d23 <= (p23 > p22) ? (p23 - p22) : (p22 - p23);
        d31 <= (p31 > p22) ? (p31 - p22) : (p22 - p31);
        d32 <= (p32 > p22) ? (p32 - p22) : (p22 - p32);
        d33 <= (p33 > p22) ? (p33 - p22) : (p22 - p33);
    end

    wire [6:0] rl11 = range_lut(d11);
    wire [6:0] rl12 = range_lut(d12);
    wire [6:0] rl13 = range_lut(d13);
    wire [6:0] rl21 = range_lut(d21);
    wire [6:0] rl23 = range_lut(d23);
    wire [6:0] rl31 = range_lut(d31);
    wire [6:0] rl32 = range_lut(d32);
    wire [6:0] rl33 = range_lut(d33);

    reg [14:0] pr11, pr12, pr13, pr21, pr23, pr31, pr32, pr33, pr22_sh;

    wire [9:0] wt_sum_comb = 
        ({3'd0, rl11>>2} + {3'd0, rl13>>2} + {3'd0, rl31>>2} + {3'd0, rl33>>2}) +
        ({2'd0, rl12>>1} + {2'd0, rl21>>1} + {2'd0, rl23>>1} + {2'd0, rl32>>1}) + 10'd128;
    reg [9:0] sum_wt_s2;

    always @(posedge clk) begin
        pr11 <= px11 * rl11; pr12 <= px12 * rl12; pr13 <= px13 * rl13;
        pr21 <= px21 * rl21; pr23 <= px23 * rl23;
        pr31 <= px31 * rl31; pr32 <= px32 * rl32; pr33 <= px33 * rl33;
        pr22_sh <= {px22, 7'd0}; 
        sum_wt_s2 <= wt_sum_comb;
    end

    reg [21:0] sum_pix;
    reg [9:0]  sum_wt_s3;

    always @(posedge clk) begin
        sum_pix <= 
            ({7'd0, pr11>>2} + {7'd0, pr13>>2} + {7'd0, pr31>>2} + {7'd0, pr33>>2}) +
            ({6'd0, pr12>>1} + {6'd0, pr21>>1} + {6'd0, pr23>>1} + {6'd0, pr32>>1}) + 
            {7'd0, pr22_sh};
        sum_wt_s3 <= sum_wt_s2;
    end

    wire [23:0] ip_quotient;

    divider_h u_div_bil (
        .aclr      (1'b0), 
        .clken     (1'b1), 
        .clock     (clk),
        .denom     ({6'd0, sum_wt_s3}), 
        .numer     ({2'd0, sum_pix}), 
        .quotient  (ip_quotient), 
        .remain    ()  
    );

    reg [7:0] oData_r;
    always @(posedge clk) begin
        oData_r <= (|ip_quotient[23:8]) ? 8'd255 : ip_quotient[7:0];
    end

    reg [29:0] hs_r;
    reg [29:0] vs_r;
    reg [29:0] de_r;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            hs_r <= 30'd0;
            vs_r <= 30'd0;
            de_r <= 30'd0;
        end else begin
            hs_r <= {hs_r[28:0], iHSync};
            vs_r <= {vs_r[28:0], iVSync};
            de_r <= {de_r[28:0], iDataEnable};
        end
    end

    wire raw_de = de_r[29];
    reg [18:0] valid_cnt;
    reg [9:0]  pad_cnt; 
    reg        padding_en;
    reg        vs_d1;

    always @(posedge clk) vs_d1 <= iVSync;
    wire frame_start = iVSync ^ vs_d1; 

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            valid_cnt  <= 19'd0;
            pad_cnt    <= 10'd0;
            padding_en <= 1'b0;
        end else begin
            if (frame_start && !padding_en) begin
                valid_cnt <= 19'd0;
                pad_cnt   <= 10'd0;
            end

            if (raw_de) begin
                if (valid_cnt == 19'd307199) begin
                    valid_cnt  <= 19'd0;
                    padding_en <= 1'b1; // 真实数据结束，启动尾部补齐
                end else begin
                    valid_cnt <= valid_cnt + 1'b1;
                end
            end

            if (padding_en) begin
                if (pad_cnt == 10'd641) begin // 双边滤波偏移像素
                    padding_en <= 1'b0;
                    pad_cnt    <= 10'd0;
                end else begin
                    pad_cnt <= pad_cnt + 1'b1;
                end
            end
        end
    end

    wire aligned_de = (raw_de && (valid_cnt >= 19'd642)) || padding_en;
    assign oHSync      = hs_r[29];
    assign oVSync      = vs_r[29];
    assign oDataEnable = aligned_de;
    assign oData       = padding_en ? 8'd0 : oData_r;

endmodule