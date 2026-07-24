`timescale 1ns/1ns
module VIP_RGB_Smooth #(
    parameter IMG_HDISP = 640
)(
    input  wire         clk,
    input  wire         rst_n,
    input  wire         in_vsync,
    input  wire         in_href,
    input  wire         in_clken,
    input  wire [15:0]  in_rgb,
    output wire         out_vsync,
    output wire         out_href,
    output wire         out_clken,
    output wire [15:0]  out_rgb
);
    reg [15:0] row1_data_d;
    always @(posedge clk) if(in_clken) row1_data_d <= in_rgb; 

    wire [15:0] row2_data, row3_data;
    Line_Shift_RAM_16Bit #(.RAM_DEPTH(IMG_HDISP)) u_line1 (.clock(clk), .clken(in_clken), .shiftin(in_rgb), .shiftout(row2_data));
    Line_Shift_RAM_16Bit #(.RAM_DEPTH(IMG_HDISP)) u_line2 (.clock(clk), .clken(in_clken), .shiftin(row2_data), .shiftout(row3_data));

    reg read_clken;
    always @(posedge clk) read_clken <= in_clken;

    reg [15:0] p11, p12, p13, p21, p22, p23, p31, p32, p33;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            {p11,p12,p13} <= 0; {p21,p22,p23} <= 0; {p31,p32,p33} <= 0;
        end else if(read_clken) begin
            p13 <= row3_data;   p12 <= p13; p11 <= p12;
            p23 <= row2_data;   p22 <= p23; p21 <= p22;
            p33 <= row1_data_d; p32 <= p33; p31 <= p32;
        end
    end

    // 剔除门控
    reg [8:0] sum_r; reg [9:0] sum_g; reg [8:0] sum_b;
    always @(posedge clk) begin
        sum_r <= p11[15:11] + p12[15:11] + p13[15:11] + p21[15:11] + p22[15:11] + p23[15:11] + p31[15:11] + p32[15:11] + p33[15:11];
        sum_g <= p11[10:5]  + p12[10:5]  + p13[10:5]  + p21[10:5]  + p22[10:5]  + p23[10:5]  + p31[10:5]  + p32[10:5]  + p33[10:5];
        sum_b <= p11[4:0]   + p12[4:0]   + p13[4:0]   + p21[4:0]   + p22[4:0]   + p23[4:0]   + p31[4:0]   + p32[4:0]   + p33[4:0];
    end

    reg [16:0] mean_r; reg [17:0] mean_g; reg [16:0] mean_b;
    always @(posedge clk) begin
        mean_r <= sum_r * 8'd114;
        mean_g <= sum_g * 8'd114;
        mean_b <= sum_b * 8'd114;
    end

    reg [15:0] out_rgb_reg;
    always @(posedge clk) begin
        out_rgb_reg <= {mean_r[14:10], mean_g[15:10], mean_b[14:10]};
    end
    assign out_rgb = out_rgb_reg;
    
    reg [4:0] vsync_r, href_r, clken_r;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin vsync_r<=0; href_r<=0; clken_r<=0; end
        else begin
            vsync_r <= {vsync_r[3:0], in_vsync};
            href_r  <= {href_r[3:0],  in_href};
            clken_r <= {clken_r[3:0], in_clken};
        end
    end
    assign out_vsync = vsync_r[4];
    assign out_href  = href_r[4];
    assign out_clken = clken_r[4];
endmodule