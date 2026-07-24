`timescale 1ns / 1ps
module histogram_adjust(
    input         clk     ,
    input         rst_n   ,
    input [7:0]   i_y     ,
    input         i_valid ,
    input         i_hsync ,
    input         i_vsync ,
    output [19:0] o_histogram,
    output reg    o_histogram_valid
);
    reg [19:0] ram [255:0];
    reg [19:0] ram_q;
    reg [1:0]  vsync_reg;
    reg [7:0]  out_addr;
    reg        valid_internal;
    reg [7:0]  clear_addr;
    reg        is_clearing;

    reg [7:0]  delay1_y;  reg delay1_valid;
    reg [7:0]  delay2_y;  reg delay2_valid;
    reg [7:0]  delay3_y;  reg delay3_valid;
    reg [19:0] delay3_count;
    reg [19:0] current_count;

    always @(posedge clk) vsync_reg <= {vsync_reg[0], i_vsync};

    always @(posedge clk) begin
        if (!rst_n) begin
            is_clearing <= 1'b0; clear_addr  <= 8'd0;
        end else if (~vsync_reg[0] && vsync_reg[1]) begin 
            is_clearing <= 1'b1; clear_addr  <= 8'd0;
        end else if (is_clearing) begin
            if (clear_addr == 8'd255) is_clearing <= 1'b0;
            else clear_addr <= clear_addr + 1'b1;
        end
    end

    wire [7:0] ram_rd_addr = valid_internal ? out_addr : i_y;
    always @(posedge clk) ram_q <= ram[ram_rd_addr];

    always @(posedge clk) begin
        if (!rst_n || is_clearing) begin
            delay1_valid <= 0; delay2_valid <= 0; delay3_valid <= 0;
        end else begin
            delay1_valid <= i_valid;      delay1_y <= i_y;
            delay2_valid <= delay1_valid; delay2_y <= delay1_y;
            delay3_valid <= delay2_valid; delay3_y <= delay2_y;
            delay3_count <= current_count;
        end
    end

    // 全旁路数据转发
    always @(posedge clk) begin
        if (delay1_valid) begin
            if (delay2_valid && (delay1_y == delay2_y))
                current_count <= current_count + 20'd1;
            else if (delay3_valid && (delay1_y == delay3_y))
                current_count <= delay3_count + 20'd1;
            else
                current_count <= ram_q + 20'd1;
        end
    end

    always @(posedge clk) begin
        if (is_clearing) ram[clear_addr] <= 20'd0;
        else if (delay2_valid) ram[delay2_y] <= current_count;
    end

    always @(posedge clk) begin
        if(!rst_n || out_addr == 8'd255) valid_internal <= 1'b0;
        else if(vsync_reg[0] && ~vsync_reg[1]) valid_internal <= 1'b1;
    end

    always @(posedge clk) begin
        if(!rst_n) out_addr <= 8'd0;
        else if(valid_internal) out_addr <= out_addr + 1'b1;
    end

    always @(posedge clk) begin
        if(!rst_n) o_histogram_valid <= 1'b0;
        else o_histogram_valid <= valid_internal;
    end
    assign o_histogram = ram_q;
endmodule