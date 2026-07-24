`timescale 1ns/1ns
// =============================================================================
// 模块名：uart_cmd_decoder
// 功  能：解析 "55 XX AA" 指令，支持 0x04/0x0C 角度步进控制
// =============================================================================
module uart_cmd_decoder (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        uart_done,
    input  wire [7:0]  uart_data,
    output reg  [5:0]  algo_sel,        
    output wire [15:0] rot_angle_any    
);

reg uart_done_d1;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        uart_done_d1 <= 1'b0;
    end else begin
        uart_done_d1 <= uart_done;
    end
end

wire recv_pulse;
assign recv_pulse = uart_done & ~uart_done_d1;

reg [15:0] angle_reg;
assign rot_angle_any = angle_reg;

localparam S_IDLE = 2'd0;
localparam S_CMD  = 2'd1;
localparam S_TAIL = 2'd2;

reg [1:0]  state;
reg [7:0]  cmd_buf;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        state     <= S_IDLE;
        cmd_buf   <= 8'd0;
        algo_sel  <= 6'h3F;  
        angle_reg <= 16'd0;
    end else begin
        if (recv_pulse) begin
            if (uart_data == 8'h55) begin
                state <= S_CMD;
            end else begin
                case (state)
                    S_IDLE: begin
                        state <= S_IDLE;
                    end
                    S_CMD: begin
                        cmd_buf <= uart_data;
                        state   <= S_TAIL;
                    end
                    S_TAIL: begin
                        if (uart_data == 8'hAA) begin
                            case (cmd_buf)
                                8'h00: begin
                                    algo_sel <= 6'd0;
                                end
                                8'h01: begin
                                    algo_sel <= 6'd1;
                                end
                                8'h02: begin
                                    algo_sel <= 6'd2;
                                end
                                8'h03: begin
                                    algo_sel <= 6'd3;
                                end
                                8'h04: begin
                                    algo_sel  <= 6'd4;
                                    if (angle_reg >= 16'd355) begin
                                        angle_reg <= 16'd0;
                                    end else begin
                                        angle_reg <= angle_reg + 16'd5;
                                    end
                                end
                                8'h0C: begin
                                    algo_sel  <= 6'd4;
                                    if (angle_reg < 16'd5) begin
                                        angle_reg <= 16'd355;
                                    end else begin
                                        angle_reg <= angle_reg - 16'd5;
                                    end
                                end
                                8'h05: begin
                                    algo_sel <= 6'd5;   
                                end
                                8'h06: begin
                                    algo_sel <= 6'd6;
                                end
                                8'h07: begin
                                    algo_sel <= 6'd7;
                                end
                                8'h08: begin
                                    algo_sel <= 6'd8;
                                end
                                8'h09: begin
                                    algo_sel <= 6'd9;
                                end
                                8'h0A: begin
                                    algo_sel <= 6'd10;
                                end
                                8'h0B: begin
                                    algo_sel <= 6'd11;
                                end
                                8'h0D: begin
                                    algo_sel <= 6'd13;
                                end
                                8'h0E: begin
                                    algo_sel <= 6'd14;
                                end
                                default: begin
                                    algo_sel <= 6'h3F;
                                end
                            endcase
                        end
                        state <= S_IDLE;
                    end
                    default: begin
                        state <= S_IDLE;
                    end
                endcase
            end
        end
    end
end

endmodule