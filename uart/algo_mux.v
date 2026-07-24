`timescale 1ns/1ns
// =============================================================================
// Module Name : algo_mux
// Function    : Algorithm output multiplexer with optional zoom/crop processing
//   - Selects which algorithm output to route to the VGA display
//   - Supports on-the-fly algorithm switching at VGA vsync boundary
//   - Implements hardware zoom/crop for algo modes 2 & 3 using Block RAM
//   - Rotation mode (algo=4) receives pre-rotated data from rotate module
// Algorithm Map:
//   algo[3:0]=0 : Bypass (raw camera)
//   algo[3:0]=1 : Histogram equalization (pre-processed in top)
//   algo[3:0]=2 : Zoom mode (320x240 crop from center)
//   algo[3:0]=3 : Downscale mode (320x240 -> full VGA)
//   algo[3:0]=4 : Rotation (data from img_rotate_any module)
// Switching  : Safe at vsync falling edge to avoid frame tearing
// Clock Domain: clk_25m (25MHz VGA clock)
// =============================================================================
module algo_mux (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        vsync,
    input  wire        vga_rd_req,
    input  wire [15:0] din,
    input  wire [5:0]  algo_sel,
    input  wire [15:0] rotate_din, 
    output reg  [15:0] dout
);

reg vsync_d1;
reg vsync_d2;

always @(posedge clk) begin
    vsync_d1 <= vsync;
    vsync_d2 <= vsync_d1;
end

wire vsync_fall;
assign vsync_fall = vsync_d2 & ~vsync_d1;

reg [5:0] active_sel;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        active_sel <= 6'h3F;
    end else begin
        if (vsync_fall) begin
            active_sel <= algo_sel;
        end
    end
end

wire [3:0] active_algo;
assign active_algo = active_sel[3:0];

reg [9:0] req_x;
reg [9:0] req_y;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin 
        req_x <= 0; 
        req_y <= 0; 
    end else begin
        if (vsync_fall) begin 
            req_x <= 0; 
            req_y <= 0; 
        end else begin
            if (vga_rd_req) begin
                if (req_x == 639) begin 
                    req_x <= 0; 
                    if (req_y == 479) begin
                        req_y <= 0;
                    end else begin
                        req_y <= req_y + 1; 
                    end
                end else begin
                    req_x <= req_x + 1;
                end
            end
        end
    end
end

reg [9:0] req_x_d1;
reg [9:0] req_y_d1;
reg       req_d1;

always @(posedge clk) begin 
    req_d1   <= vga_rd_req; 
    req_x_d1 <= req_x; 
    req_y_d1 <= req_y; 
end

wire [7:0] r8;
assign r8 = {din[15:11], din[13:11]};

wire [7:0] g8;
assign g8 = {din[10:5],  din[6:5]};

wire [7:0] b8;
assign b8 = {din[4:0],   din[2:0]};

wire [15:0] gsum;
assign gsum = (r8 * 8'd77) + (g8 * 8'd150) + (b8 * 8'd29);

wire [7:0]  gray8;
assign gray8 = gsum[15:8];

function [16:0] calc_idx;
    input [8:0] fx;
    input [8:0] fy;
    begin
        calc_idx = ({8'd0, fy} << 8) + ({8'd0, fy} << 6) + {8'd0, fx};
    end
endfunction

reg        wr_en;
reg [16:0] temp_idx;

always @(*) begin
    wr_en    = 1'b0;
    temp_idx = 17'd0; 
    
    if (req_d1) begin
        case (active_algo) 
            4'd2: begin
                if (req_x_d1 >= 160 && req_x_d1 < 480 && req_y_d1 >= 120 && req_y_d1 < 360) begin
                    wr_en    = 1'b1;
                    temp_idx = calc_idx(req_x_d1[8:0]-9'd160, req_y_d1[8:0]-9'd120);
                end
            end
            4'd3: begin
                if (req_x_d1[0] == 0 && req_y_d1[0] == 0) begin
                    wr_en    = 1'b1;
                    temp_idx = calc_idx(req_x_d1[9:1], req_y_d1[9:1]);
                end
            end
            default: begin
            end
        endcase
    end
end

wire [14:0] wr_word;
assign wr_word = temp_idx[16:2];

wire [1:0]  wr_byte;
assign wr_byte = temp_idx[1:0];

(* ram_style = "block" *) reg [7:0] bank0 [0:19455];
(* ram_style = "block" *) reg [7:0] bank1 [0:19455];
(* ram_style = "block" *) reg [7:0] bank2 [0:19455];
(* ram_style = "block" *) reg [7:0] bank3 [0:19455];

always @(posedge clk) begin
    if (wr_en) begin
        case (wr_byte)
            2'd0: begin
                bank0[wr_word] <= gray8;
            end
            2'd1: begin
                bank1[wr_word] <= gray8;
            end
            2'd2: begin
                bank2[wr_word] <= gray8;
            end
            2'd3: begin
                bank3[wr_word] <= gray8;
            end
        endcase
    end
end

wire [8:0] rd_x_h;
assign rd_x_h = req_x[9:1];

wire [8:0] rd_y_h;
assign rd_y_h = req_y[9:1];

reg [8:0] img_x;
reg [8:0] img_y;
reg       vpx;

always @(*) begin
    img_x = 9'd0;
    img_y = 9'd0;
    vpx   = 1'b0;
    
    case (active_algo)
        4'd2: begin 
            img_x = rd_x_h;
            img_y = rd_y_h; 
            vpx   = 1'b1; 
        end
        4'd3: begin 
            if (req_x >= 160 && req_x < 480 && req_y >= 120 && req_y < 360) begin
                img_x = req_x[8:0] - 9'd160;
                img_y = req_y[8:0] - 9'd120;
                vpx   = 1'b1;
            end
        end
        default: begin
        end
    endcase
end

wire [16:0] rd_idx_raw;
assign rd_idx_raw = ({8'd0, img_y} << 8) + ({8'd0, img_y} << 6) + {8'd0, img_x};

wire [16:0] rd_idx;
assign rd_idx = (rd_idx_raw > 17'd76799) ? 17'd76799 : rd_idx_raw;

reg       vpx_d1;
reg [1:0] rd_byte_d1;
reg [7:0] q0;
reg [7:0] q1;
reg [7:0] q2;
reg [7:0] q3;

always @(posedge clk) begin
    vpx_d1     <= vpx; 
    rd_byte_d1 <= rd_idx[1:0];
    q0         <= bank0[rd_idx[16:2]]; 
    q1         <= bank1[rd_idx[16:2]];
    q2         <= bank2[rd_idx[16:2]]; 
    q3         <= bank3[rd_idx[16:2]];
end

reg [7:0] bram_out;

always @(*) begin
    case (rd_byte_d1) 
        2'd0: begin
            bram_out = q0; 
        end
        2'd1: begin
            bram_out = q1; 
        end
        2'd2: begin
            bram_out = q2; 
        end
        2'd3: begin
            bram_out = q3; 
        end
    endcase
end

wire [15:0] zoom_rgb565;
assign zoom_rgb565 = {bram_out[7:3], bram_out[7:2], bram_out[7:3]};

// 【还原为完美对齐的 vpx_d1】
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        dout <= 16'd0;
    end else begin
        case (active_algo)
            4'd0: begin
                dout <= din;                               
            end
            4'd1: begin
                dout <= din;                               
            end
            4'd2: begin
                if (vpx_d1) begin
                    dout <= zoom_rgb565;
                end else begin
                    dout <= 16'h0000;
                end
            end
            4'd3: begin
                if (vpx_d1) begin
                    dout <= zoom_rgb565;
                end else begin
                    dout <= 16'h0000;
                end
            end
            4'd4: begin
                dout <= rotate_din;                        
            end
            default: begin
                dout <= din;                               
            end
        endcase
    end
end

endmodule