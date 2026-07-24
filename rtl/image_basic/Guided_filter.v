`timescale 1ns/1ps
// =============================================================================
// Module  : guided_filter
// Purpose : 导引滤波
// =============================================================================
module guided_filter #(
    parameter IMG_WIDTH = 640,
    parameter EPS_Q8    = 16'd2500      
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

    reg [7:0] p22_d [0:30];
    integer j;

    always @(posedge clk) begin
        p22_d[0] <= p22;
        for (j = 1; j <= 30; j = j + 1) begin
            p22_d[j] <= p22_d[j-1];
        end
    end

    reg [11:0] sum_I; 
    reg [17:0] sq_row0, sq_row1, sq_row2;
    always @(posedge clk) begin
        sum_I   <= p11 + p12 + p13 + p21 + p22 + p23 + p31 + p32 + p33;
        sq_row0 <= p11*p11 + p12*p12 + p13*p13;
        sq_row1 <= p21*p21 + p22*p22 + p23*p23;
        sq_row2 <= p31*p31 + p32*p32 + p33*p33;
    end

    reg [19:0] sum_I2; 
    reg [11:0] sum_I_s2b;
    always @(posedge clk) begin
        sum_I2    <= {2'd0, sq_row0} + {2'd0, sq_row1} + {2'd0, sq_row2};
        sum_I_s2b <= sum_I;
    end

    wire [19:0] sum_I_mul = sum_I_s2b * 20'd28;  
    wire [27:0] sum_I2_mul = sum_I2 * 28'd28;     
    wire [11:0] mean_I_comb = sum_I_mul[19:8];
    wire [19:0] mean_I2_comb = sum_I2_mul[27:8];

    reg [7:0]  mean_I_r; 
    reg [15:0] mean_I2_r, mean_I_sq;
    always @(posedge clk) begin
        mean_I_r  <= mean_I_comb[7:0];
        mean_I2_r <= mean_I2_comb[15:0];
        mean_I_sq <= mean_I_comb[7:0] * mean_I_comb[7:0];
    end

    reg [7:0] mean_I_d [0:26];
    integer i;
    always @(posedge clk) begin
        mean_I_d[0] <= mean_I_r;
        for(i = 1; i <= 26; i = i + 1) begin
            mean_I_d[i] <= mean_I_d[i-1];
        end
    end

    reg [15:0] var_I;
    always @(posedge clk) begin
        if (mean_I2_r >= mean_I_sq) var_I <= mean_I2_r - mean_I_sq;
        else var_I <= 16'd0;
    end

    reg [23:0] var_num; 
    reg [15:0] var_den;
    always @(posedge clk) begin
        var_num <= {var_I, 8'd0}; 
        var_den <= var_I + EPS_Q8;
    end

    wire [23:0] ip_quotient;
    divider_h u_div_ip (
        .aclr      (1'b0), 
        .clken     (1'b1), 
        .clock     (clk),
        .denom     (var_den), 
        .numer     (var_num), 
        .quotient  (ip_quotient), 
        .remain    ()  
    );

    wire [7:0] a_k_q8 = ip_quotient[7:0];
    reg [7:0] a_k_r;
    always @(posedge clk) a_k_r <= a_k_q8;

    wire [16:0] b_k_num = mean_I_d[26] * (9'd256 - {1'b0, a_k_r}); 
    
    reg [7:0] b_k_r, a_k_r_d1;
    always @(posedge clk) begin
        b_k_r    <= b_k_num[15:8];
        a_k_r_d1 <= a_k_r;
    end

    reg [32:0] de_pipe;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) de_pipe <= 33'd0;
        else de_pipe <= {de_pipe[31:0], iDataEnable};
    end
    wire ab_valid = de_pipe[32]; 

    wire [15:0] ab11, ab12, ab13, ab21, ab22, ab23, ab31, ab32, ab33;
    wire [7:0]  I_sync_p11, I_sync_p12, I_sync_p13, I_sync_p21, I_sync_p22, I_sync_p23, I_sync_p31, I_sync_p32, I_sync_p33;

    line_buffer_3x3 #( .IMG_WIDTH (IMG_WIDTH) ) u_lbuf_ab_a (
        .clk(clk), .rst_n(rst_n), .iDataEnable(ab_valid), .din(a_k_r_d1),
        .p11(ab11[15:8]), .p12(ab12[15:8]), .p13(ab13[15:8]),
        .p21(ab21[15:8]), .p22(ab22[15:8]), .p23(ab23[15:8]),
        .p31(ab31[15:8]), .p32(ab32[15:8]), .p33(ab33[15:8])
    );

    line_buffer_3x3 #( .IMG_WIDTH (IMG_WIDTH) ) u_lbuf_ab_b (
        .clk(clk), .rst_n(rst_n), .iDataEnable(ab_valid), .din(b_k_r),
        .p11(ab11[7:0]), .p12(ab12[7:0]), .p13(ab13[7:0]),
        .p21(ab21[7:0]), .p22(ab22[7:0]), .p23(ab23[7:0]),
        .p31(ab31[7:0]), .p32(ab32[7:0]), .p33(ab33[7:0])
    );

    line_buffer_3x3 #( .IMG_WIDTH (IMG_WIDTH) ) u_lbuf_I (
        .clk(clk), .rst_n(rst_n), .iDataEnable(ab_valid), .din(p22_d[30]),
        .p11(I_sync_p11), .p12(I_sync_p12), .p13(I_sync_p13),
        .p21(I_sync_p21), .p22(I_sync_p22), .p23(I_sync_p23),
        .p31(I_sync_p31), .p32(I_sync_p32), .p33(I_sync_p33)
    );

    reg [11:0] sum_a, sum_b; 
    reg [7:0]  I_sync_d1;

    always @(posedge clk) begin 
        sum_a <= (ab11[15:8] + ab12[15:8] + ab13[15:8]) + (ab21[15:8] + ab22[15:8] + ab23[15:8]) + (ab31[15:8] + ab32[15:8] + ab33[15:8]);
        sum_b <= (ab11[7:0]  + ab12[7:0]  + ab13[7:0] ) + (ab21[7:0]  + ab22[7:0]  + ab23[7:0] ) + (ab31[7:0]  + ab32[7:0]  + ab33[7:0] );
        I_sync_d1 <= I_sync_p22; 
    end

    wire [19:0] sum_a_mul = sum_a * 20'd28;
    wire [19:0] sum_b_mul = sum_b * 20'd28;

    reg [7:0] mean_a, mean_b, I_sync_d2;
    always @(posedge clk) begin 
        mean_a <= sum_a_mul[19:8]; mean_b <= sum_b_mul[19:8]; 
        I_sync_d2 <= I_sync_d1;
    end

    wire [15:0] ap_raw = mean_a * I_sync_d2;
    wire [8:0] q_sum = ap_raw[15:8] + mean_b;
    wire [7:0] q_clamp = (q_sum[8]) ? 8'd255 : q_sum[7:0]; 

    reg [7:0] oData_r;
    always @(posedge clk) oData_r <= q_clamp;

    reg [37:0] hs_r;
    reg [37:0] vs_r;
    reg [37:0] de_r;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            hs_r <= 38'd0; vs_r <= 38'd0; de_r <= 38'd0;
        end else begin
            hs_r <= {hs_r[36:0], iHSync};
            vs_r <= {vs_r[36:0], iVSync};
            de_r <= {de_r[36:0], iDataEnable};
        end
    end

    // ============================================================
    //掐头补尾空间相位对齐
    // ============================================================
    wire raw_de = de_r[37];
    reg [18:0] valid_cnt;
    reg [10:0] pad_cnt; 
    reg        padding_en;
    reg        vs_d1;

    always @(posedge clk) vs_d1 <= iVSync;
    wire frame_start = iVSync ^ vs_d1; 

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            valid_cnt  <= 19'd0;
            pad_cnt    <= 11'd0;
            padding_en <= 1'b0;
        end else begin
            if (frame_start && !padding_en) begin
                valid_cnt <= 19'd0;
                pad_cnt   <= 11'd0;
            end

            if (raw_de) begin
                if (valid_cnt == 19'd307199) begin
                    valid_cnt  <= 19'd0;
                    padding_en <= 1'b1; 
                end else begin
                    valid_cnt <= valid_cnt + 1'b1;
                end
            end

            if (padding_en) begin
                if (pad_cnt == 11'd1283) begin // 导引滤波偏移像素
                    padding_en <= 1'b0;
                    pad_cnt    <= 11'd0;
                end else begin
                    pad_cnt <= pad_cnt + 1'b1;
                end
            end
        end
    end

    wire aligned_de = (raw_de && (valid_cnt >= 19'd1284)) || padding_en;

    assign oHSync      = hs_r[37];
    assign oVSync      = vs_r[37]; 
    assign oDataEnable = aligned_de;
    assign oData       = padding_en ? 8'd0 : oData_r;

endmodule