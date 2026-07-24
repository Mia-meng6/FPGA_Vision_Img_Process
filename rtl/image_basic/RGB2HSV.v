`timescale 1ns / 1ps
module RGB2HSV (
    input                   I_clk,      
    input                   I_rst_n,    
    input                   I_tlast,    
    input                   I_tuser,    
    input       [23:0]      I_tdata,    
    input                   I_tvalid,   
    output                  I_tready,   
    output                  O_tlast,    
    output                  O_tuser,    
    output      [23:0]      O_tdata,    
    output                  O_tvalid,   
    input                   O_tready    
);

    wire [7:0] red_in, green_in, blue_in;
    assign {red_in, green_in, blue_in} = I_tdata;

    // =========================== Stage 1：极值与绝对差分 ===========================
    wire [7:0] w_min = (red_in < green_in) ? ((red_in < blue_in) ? red_in : blue_in) : ((green_in < blue_in) ? green_in : blue_in);
    wire [7:0] w_max = (red_in >= green_in && red_in >= blue_in) ? red_in :
                       (green_in >= red_in && green_in >= blue_in) ? green_in : blue_in;

    reg [7:0] rgb_max, delta_rgb, abs_diff, h_base;
    reg       h_add;

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            rgb_max <= 0; delta_rgb <= 0; abs_diff <= 0; h_base <= 0; h_add <= 0;
        end else if (I_tvalid) begin
            rgb_max <= w_max;
            delta_rgb <= w_max - w_min;

            // 绝对值算法：规避任何负数下溢引发的色相跨界跳变
            if (w_max == red_in) begin
                if (green_in >= blue_in) begin abs_diff <= green_in - blue_in; h_base <= 8'd0;   h_add <= 1'b1; end
                else                     begin abs_diff <= blue_in - green_in; h_base <= 8'd255; h_add <= 1'b0; end
            end else if (w_max == green_in) begin
                if (blue_in >= red_in)   begin abs_diff <= blue_in - red_in;   h_base <= 8'd85;  h_add <= 1'b1; end
                else                     begin abs_diff <= red_in - blue_in;   h_base <= 8'd85;  h_add <= 1'b0; end
            end else begin
                if (red_in >= green_in)  begin abs_diff <= red_in - green_in;  h_base <= 8'd171; h_add <= 1'b1; end
                else                     begin abs_diff <= green_in - red_in;  h_base <= 8'd171; h_add <= 1'b0; end
            end
        end
    end

    // =========================== Stage 2：除法器数据准备 ===========================
    reg [25:0] I_tvalid_r, I_tlast_r, I_tuser_r;
    reg [15:0] numer_s, denom_s;
    reg [23:0] numer_h;
    reg [15:0] denom_h;
    wire [15:0] s_div_result; 
    wire [23:0] h_div_result;

    reg [199:0] h_base_pipe; 
    reg [24:0]  h_add_pipe;  
    reg [199:0] val_pipe;    
    reg [63:0]  sat_pipe;    

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            I_tvalid_r <= 0; I_tlast_r <= 0; I_tuser_r <= 0;
            numer_s <= 0; denom_s <= 1; numer_h <= 0; denom_h <= 1;
            h_base_pipe <= 0; h_add_pipe <= 0; val_pipe <= 0; sat_pipe <= 0;
        end else begin
            I_tvalid_r <= {I_tvalid_r[24:0], I_tvalid};
            I_tlast_r  <= {I_tlast_r[24:0],  I_tlast};
            I_tuser_r  <= {I_tuser_r[24:0],  I_tuser};

            numer_s <= {delta_rgb, 8'd0} - delta_rgb;
            denom_s <= (rgb_max == 0) ? 16'd1 : rgb_max;
            
            numer_h <= {abs_diff, 8'd0} - abs_diff;
            denom_h <= (delta_rgb == 0) ? 16'd1 : ({delta_rgb, 2'd0} + {delta_rgb, 1'd0});

            h_base_pipe <= {h_base_pipe[191:0], h_base};
            h_add_pipe  <= {h_add_pipe[23:0],   h_add};
            val_pipe    <= {val_pipe[191:0],    rgb_max};
            sat_pipe    <= {sat_pipe[55:0],     s_div_result[7:0]};
        end
    end

    // =========================== 除法器例化 ===========================
    divider_s divider_s_inst (.aclr(!I_rst_n), .clken(1'b1), .clock(I_clk), .denom(denom_s), .numer(numer_s), .quotient(s_div_result), .remain());
    divider_h divider_h_inst (.aclr(!I_rst_n), .clken(1'b1), .clock(I_clk), .denom(denom_h), .numer(numer_h), .quotient(h_div_result), .remain());

    // =========================== 输出合成 ===========================
    wire [7:0] final_h_base = h_base_pipe[199:192];
    wire       final_h_add  = h_add_pipe[24];
    wire [7:0] final_val    = val_pipe[199:192];
    wire [7:0] final_sat    = sat_pipe[63:56];
    wire [7:0] h_div_out    = h_div_result[7:0];

    wire [7:0] final_hue = final_h_add ? (final_h_base + h_div_out) : (final_h_base - h_div_out);

    assign O_tlast  = I_tlast_r[25];
    assign O_tuser  = I_tuser_r[25];
    assign O_tvalid = I_tvalid_r[25];

    assign O_tdata  = {final_hue, final_sat, final_val}; 
    assign I_tready = O_tready;

endmodule
