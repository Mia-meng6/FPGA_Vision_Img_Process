module pupil_detection (
    input  wire        clk,
    input  wire        rst_n,
    input  wire [15:0] pixel,
    output reg         pupil_flag
);

// RGB565 转 8-bit RGB 
wire [7:0] R8;
wire [7:0] G8;
wire [7:0] B8;

assign R8 = {pixel[15:11], pixel[15:13]};
assign G8 = {pixel[10:5],  pixel[10:9]};
assign B8 = {pixel[4:0],   pixel[4:2]};

// RGB -> Y 
wire [15:0] Y;
assign Y = (77*R8 + 150*G8 + 29*B8) / 256;

// 瞳孔亮度阈值（亮度小于该值认为是暗点，即瞳孔）
localparam PUPIL_Y_MAX = 8'd40;
wire is_dark;
assign is_dark = (Y < PUPIL_Y_MAX);

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        pupil_flag <= 1'b0;
    end else begin
        pupil_flag <= is_dark;
    end
end

endmodule