/*
 * 模块名：template_match
 * 功  能：卷积模板匹配——将当前帧 150-bit 特征向量与
 *         预存的手势模板逐位比较，计算汉明距离（相似度），
 *         输出最相似手势编号及置信度。
 */

`timescale 1ns/1ps
module template_match #(
    parameter GRID_CELLS      = 150,      // 特征向量位宽 (10×15)
    parameter NUM_TEMPLATES   = 5,        // 手势种类数
    parameter MATCH_THRESHOLD = 8'd110,   // 匹配阈值（可调）

    // ----------------------------------------------------------------
    // 手势模板（150 bit，依据实际采集数据修改）
    // ----------------------------------------------------------------
    parameter [GRID_CELLS-1:0] TEMPLATE_0 = 150'h0,  // 手势 0 模板
    parameter [GRID_CELLS-1:0] TEMPLATE_1 = 150'h0,  // 手势 1 模板
    parameter [GRID_CELLS-1:0] TEMPLATE_2 = 150'h0,  // 手势 2 模板
    parameter [GRID_CELLS-1:0] TEMPLATE_3 = 150'h0,  // 手势 3 模板
    parameter [GRID_CELLS-1:0] TEMPLATE_4 = 150'h0   // 手势 4 模板
)(
    input        clk,
    input        rst_n,

    // 来自 grid_feature 的特征向量
    input  [GRID_CELLS-1:0] feature_vec,
    input                   feat_valid,

    // 匹配结果输出
    output reg [2:0] gesture_id,     // 最佳手势编号
    output reg       gesture_valid,  // 是否超过阈值
    output reg [7:0] best_score      // 最佳匹配分数
);

// -------------------------------------------------------
// 模板 ROM
// -------------------------------------------------------
reg [GRID_CELLS-1:0] tmpl_rom [0:NUM_TEMPLATES-1];

initial begin
    tmpl_rom[0] = TEMPLATE_0;
    tmpl_rom[1] = TEMPLATE_1;
    tmpl_rom[2] = TEMPLATE_2;
    tmpl_rom[3] = TEMPLATE_3;
    tmpl_rom[4] = TEMPLATE_4;
end

// -------------------------------------------------------
// 逐模板比较状态机
// -------------------------------------------------------
reg [2:0]  tmpl_idx;       
reg        comparing;     
reg [GRID_CELLS-1:0] feat_latch; 

reg [2:0]  best_id_r;
reg [7:0]  best_sc_r;

wire [GRID_CELLS-1:0] match_bits = feat_latch ~^ tmpl_rom[tmpl_idx]; 

//统计 1 的个数
function automatic [7:0] popcount150;
    input [GRID_CELLS-1:0] v;
    integer k;
    reg [7:0] cnt;
    begin
        cnt = 8'd0;
        for (k = 0; k < GRID_CELLS; k = k+1)
            cnt = cnt + v[k];
        popcount150 = cnt;
    end
endfunction

wire [7:0] cur_score = popcount150(match_bits);

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        comparing     <= 1'b0;
        tmpl_idx      <= 3'd0;
        feat_latch    <= {GRID_CELLS{1'b0}};
        best_id_r     <= 3'h7;
        best_sc_r     <= 8'd0;
        gesture_id    <= 3'h7;
        gesture_valid <= 1'b0;
        best_score    <= 8'd0;
    end else if (feat_valid && !comparing) begin
        // 特征就绪，开始逐模板比较
        feat_latch <= feature_vec;
        comparing  <= 1'b1;
        tmpl_idx   <= 3'd0;
        best_id_r  <= 3'h7;
        best_sc_r  <= 8'd0;
    end else if (comparing) begin
        // 比较当前模板
        if (cur_score > best_sc_r) begin
            best_sc_r <= cur_score;
            best_id_r <= tmpl_idx;
        end

        if (tmpl_idx == NUM_TEMPLATES-1) begin
            // 所有模板比较完毕
            comparing     <= 1'b0;
            best_score    <= (cur_score > best_sc_r) ? cur_score : best_sc_r;
            gesture_id    <= (cur_score > best_sc_r) ? tmpl_idx  : best_id_r;
            gesture_valid <= ((cur_score > best_sc_r) ? cur_score : best_sc_r) >= MATCH_THRESHOLD;
        end else begin
            tmpl_idx <= tmpl_idx + 1'b1;
        end
    end
end

endmodule