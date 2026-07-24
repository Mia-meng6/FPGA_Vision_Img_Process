`timescale 1ns / 1ps
////////////////////////////////////////////////////////////////////////
// Module Name   : key_filter
// Description   : 标准按键消抖模块 (20ms) 带状态翻转功能
////////////////////////////////////////////////////////////////////////

module key_filter
#(
    // 假设输入时钟为 25MHz，20ms = 500,000 个时钟周期
    parameter CNT_MAX = 20'd499_999 
)
(
    input   wire    sys_clk,    // 模块时钟 (接入 25MHz)
    input   wire    sys_rst_n,  // 系统复位
    input   wire    key_in,     // 外部按键物理输入

    output  reg     key_flag,   // 按下瞬间输出一个时钟周期的高脉冲
    output  reg     key_state   // 每次按下状态翻转一次 (0 -> 1 -> 0)
);

    // 内部信号定义
    reg [19:0] cnt_20ms;
    reg key_in_d0;
    reg key_in_d1;

    // 1. 打两拍，防止外部异步信号带来的亚稳态
    always @(posedge sys_clk or negedge sys_rst_n) begin
        if (!sys_rst_n) begin
            key_in_d0 <= 1'b1;  // 假设按键默认上拉（未按下为高电平）
            key_in_d1 <= 1'b1;
        end else begin
            key_in_d0 <= key_in;
            key_in_d1 <= key_in_d0;
        end
    end

    // 2. 边沿检测：异或操作，一旦按键电平发生任何跳变，key_change 为高
    wire key_change = (key_in_d0 != key_in_d1);

    // 3. 20ms 延时计数器
    always @(posedge sys_clk or negedge sys_rst_n) begin
        if (!sys_rst_n)
            cnt_20ms <= 20'd0;
        else if (key_change)
            cnt_20ms <= 20'd0; // 只要有抖动，计数器立刻清零重新计
        else if (cnt_20ms < CNT_MAX)
            cnt_20ms <= cnt_20ms + 1'b1; // 电平稳定时开始累加
    end

    // 4. 产生有效脉冲和翻转状态
    always @(posedge sys_clk or negedge sys_rst_n) begin
        if (!sys_rst_n) begin
            key_flag  <= 1'b0;
            key_state <= 1'b0; // 默认输出状态 0 (对应原图模式)
        end else if (cnt_20ms == CNT_MAX - 1) begin
            // 延时 20ms 且电平稳定后，确认按键被按下（低电平有效）
            if (key_in_d1 == 1'b0) begin 
                key_flag  <= 1'b1;
                key_state <= ~key_state; // 状态翻转：切换算法模式
            end else begin
                key_flag  <= 1'b0;
            end
        end else begin
            key_flag <= 1'b0;
        end
    end

endmodule