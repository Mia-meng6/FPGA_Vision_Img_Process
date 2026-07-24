/*
 * 模块名：grid_feature
 */

`timescale 1ns/1ps
module grid_feature #(
    parameter  GRID_COLS = 10,
    parameter  GRID_ROWS = 15,
    parameter  [10:0] IMG_HDISP = 11'd640,
    parameter  [10:0] IMG_VDISP = 11'd480
)(
    input        clk,
    input        rst_n,

    input        per_frame_vsync,
    input        per_frame_href,
    input        per_frame_clken,
    input        per_img_Bit,

    input [10:0] bbox_x_min,
    input [10:0] bbox_x_max,
    input [10:0] bbox_y_min,
    input [10:0] bbox_y_max,
    input        bbox_valid,

    output reg [GRID_COLS*GRID_ROWS-1:0] feature_vec,
    output reg                            feat_valid
);

localparam TOTAL_CELLS = GRID_COLS * GRID_ROWS; // 150

// -------------------------------------------------------
// vsync 沿检测
// -------------------------------------------------------
reg vsync_d;
always @(posedge clk or negedge rst_n)
    if (!rst_n) vsync_d <= 0; else vsync_d <= per_frame_vsync;

wire vsync_rise = per_frame_vsync & ~vsync_d;
wire vsync_fall = ~per_frame_vsync & vsync_d;

// -------------------------------------------------------
// 帧开始锁存边框；在消隐期用状态机计算步长
// step_col = bbox_w / GRID_COLS（10步减法）
// step_row = bbox_h / GRID_ROWS（15步减法）
// -------------------------------------------------------
reg [10:0] bx_min, by_min, bbox_w, bbox_h;
reg        bbox_ok;
reg [10:0] step_col, step_row;
reg [1:0]  step_state;   // 0=idle, 1=calc_col, 2=calc_row, 3=done
reg [3:0]  step_cnt;
reg [10:0] step_rem;     // 除法余数

localparam S_IDLE     = 2'd0;
localparam S_CALC_COL = 2'd1;
localparam S_CALC_ROW = 2'd2;
localparam S_DONE     = 2'd3;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        step_state <= S_IDLE;
        step_col   <= 11'd64;  
        step_row   <= 11'd32;  
        step_cnt   <= 4'd0;
        step_rem   <= 11'd0;
        bx_min     <= 0; by_min <= 0;
        bbox_w     <= 11'd640; bbox_h <= 11'd480;
        bbox_ok    <= 0;
    end else begin
        case (step_state)
            S_IDLE: begin
                if (vsync_rise) begin
                    bbox_ok  <= bbox_valid;
                    bx_min   <= bbox_x_min;
                    by_min   <= bbox_y_min;
                    bbox_w   <= (bbox_x_max > bbox_x_min) ? (bbox_x_max - bbox_x_min) : 11'd1;
                    bbox_h   <= (bbox_y_max > bbox_y_min) ? (bbox_y_max - bbox_y_min) : 11'd1;
                    step_state <= S_CALC_COL;
                    step_cnt   <= 4'd0;
                    // step_rem 在下一拍从 bbox_w 读取
                end
            end
            S_CALC_COL: begin
                if (step_cnt == 4'd0)
                    step_rem <= bbox_w;

                if (step_cnt < GRID_COLS) begin
                    step_cnt <= step_cnt + 1'b1;
                end else begin
                    step_col   <= bbox_w / GRID_COLS; // 帧消隐期计算
                    step_cnt   <= 4'd0;
                    step_rem   <= bbox_h;
                    step_state <= S_CALC_ROW;
                end
            end
            S_CALC_ROW: begin
                if (step_cnt < GRID_ROWS) begin
                    step_cnt <= step_cnt + 1'b1;
                end else begin
                    step_row   <= bbox_h / GRID_ROWS;
                    step_cnt   <= 4'd0;
                    step_state <= S_DONE;
                end
            end
            S_DONE: begin
                step_state <= S_IDLE;
            end
        endcase
    end
end

// -------------------------------------------------------
// 行列计数器
// -------------------------------------------------------
reg [10:0] col_cnt, row_cnt;
reg href_d;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin col_cnt <= 0; row_cnt <= 0; href_d <= 0; end
    else begin
        href_d <= per_frame_href;
        if (vsync_rise) begin
            col_cnt <= 0; row_cnt <= 0;
        end else if (per_frame_href && per_frame_clken) begin
            col_cnt <= (col_cnt == IMG_HDISP-1) ? 11'd0 : col_cnt + 1'b1;
        end else if (!per_frame_href && href_d) begin
            col_cnt <= 0;
            row_cnt <= row_cnt + 1'b1;
        end
    end
end

// -------------------------------------------------------
// 格索引：累加比较法
// -------------------------------------------------------
wire in_bbox = bbox_ok &&
               (col_cnt >= bx_min) && (col_cnt < bx_min + bbox_w) &&
               (row_cnt >= by_min) && (row_cnt < by_min + bbox_h);

wire [10:0] rel_col = col_cnt - bx_min;
wire [10:0] rel_row = row_cnt - by_min;

wire [3:0] grid_c_raw = (step_col == 0) ? 4'd0 : rel_col / step_col;
wire [3:0] grid_r_raw = (step_row == 0) ? 4'd0 : rel_row / step_row;
wire [3:0] grid_c = (grid_c_raw >= GRID_COLS) ? (GRID_COLS-1) : grid_c_raw;
wire [3:0] grid_r = (grid_r_raw >= GRID_ROWS) ? (GRID_ROWS-1) : grid_r_raw;

wire [7:0] cell_idx = grid_r * GRID_COLS + grid_c;

// -------------------------------------------------------
// 150 个格计数器
// -------------------------------------------------------
integer ii;
reg [12:0] cnt_total [0:TOTAL_CELLS-1];
reg [12:0] cnt_black [0:TOTAL_CELLS-1];

reg        in_bbox_d;
reg [7:0]  cell_idx_d;
reg        bit_d;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        in_bbox_d <= 0; cell_idx_d <= 0; bit_d <= 0;
    end else begin
        in_bbox_d  <= in_bbox && per_frame_href && per_frame_clken;
        cell_idx_d <= cell_idx;
        bit_d      <= per_img_Bit;
    end
end

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        for (ii = 0; ii < TOTAL_CELLS; ii = ii+1) begin
            cnt_total[ii] <= 13'd0;
            cnt_black[ii] <= 13'd0;
        end
    end else if (vsync_rise) begin
        for (ii = 0; ii < TOTAL_CELLS; ii = ii+1) begin
            cnt_total[ii] <= 13'd0;
            cnt_black[ii] <= 13'd0;
        end
    end else if (in_bbox_d) begin
        cnt_total[cell_idx_d] <= cnt_total[cell_idx_d] + 1'b1;
        if (bit_d)
            cnt_black[cell_idx_d] <= cnt_black[cell_idx_d] + 1'b1;
    end
end

// -------------------------------------------------------
// 帧末判决
// -------------------------------------------------------
reg [7:0]  judge_idx;
reg        judging;
reg [TOTAL_CELLS-1:0] feat_reg;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        judging <= 0; judge_idx <= 0;
        feat_reg <= {TOTAL_CELLS{1'b1}};
        feature_vec <= {TOTAL_CELLS{1'b1}};
        feat_valid  <= 0;
    end else if (vsync_fall && bbox_ok) begin
        judging    <= 1'b1;
        judge_idx  <= 8'd0;
        feat_valid <= 1'b0;
    end else if (judging) begin
        feat_reg[judge_idx] <= (cnt_black[judge_idx] <= (cnt_total[judge_idx] >> 1));
        if (judge_idx == TOTAL_CELLS-1) begin
            judging     <= 1'b0;
            feature_vec <= feat_reg;
            feat_valid  <= 1'b1;
        end else begin
            judge_idx <= judge_idx + 1'b1;
        end
    end
end

endmodule