module rgb_mean_filter_5x5 (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        din_valid,
    input  wire        vs_in,
    input  wire [15:0] din,
    input  wire        filter_en,
    output wire        dout_valid,
    output wire        vs_out,
    output wire [15:0] dout
);

parameter LATENCY   = 5;
parameter H_ACTIVE  = 640;

// 4 行缓存
reg [15:0] line_buf0 [0:H_ACTIVE-1];
reg [15:0] line_buf1 [0:H_ACTIVE-1];
reg [15:0] line_buf2 [0:H_ACTIVE-1];
reg [15:0] line_buf3 [0:H_ACTIVE-1];
reg [9:0]  col_cnt;

wire wr_en;
assign wr_en = din_valid;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        col_cnt <= 10'd0;
    end else if (!din_valid) begin
        col_cnt <= 10'd0;
    end else if (col_cnt < H_ACTIVE - 1) begin
        col_cnt <= col_cnt + 1'b1;
    end else begin
        col_cnt <= col_cnt;
    end
end

always @(posedge clk) begin
    if (wr_en) begin
        line_buf0[col_cnt] <= din;
    end
end

always @(posedge clk) begin
    if (wr_en) begin
        line_buf1[col_cnt] <= line_buf0[col_cnt];
    end
end

always @(posedge clk) begin
    if (wr_en) begin
        line_buf2[col_cnt] <= line_buf1[col_cnt];
    end
end

always @(posedge clk) begin
    if (wr_en) begin
        line_buf3[col_cnt] <= line_buf2[col_cnt];
    end
end

// 5 行数据
wire [15:0] row0;
wire [15:0] row1;
wire [15:0] row2;
wire [15:0] row3;
wire [15:0] row4;

assign row0 = din;
assign row1 = line_buf0[col_cnt];
assign row2 = line_buf1[col_cnt];
assign row3 = line_buf2[col_cnt];
assign row4 = line_buf3[col_cnt];

// 5x5 窗口寄存器
reg [15:0] p11;
reg [15:0] p12;
reg [15:0] p13;
reg [15:0] p14;
reg [15:0] p15;

reg [15:0] p21;
reg [15:0] p22;
reg [15:0] p23;
reg [15:0] p24;
reg [15:0] p25;

reg [15:0] p31;
reg [15:0] p32;
reg [15:0] p33;
reg [15:0] p34;
reg [15:0] p35;

reg [15:0] p41;
reg [15:0] p42;
reg [15:0] p43;
reg [15:0] p44;
reg [15:0] p45;

reg [15:0] p51;
reg [15:0] p52;
reg [15:0] p53;
reg [15:0] p54;
reg [15:0] p55;

reg vs_r1;
reg vs_r2;
reg vs_r3;
reg vs_r4;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        vs_r1 <= 1'b0;
        vs_r2 <= 1'b0; 
        vs_r3 <= 1'b0; 
        vs_r4 <= 1'b0;
        
        p11 <= 16'd0;
        p12 <= 16'd0; 
        p13 <= 16'd0; 
        p14 <= 16'd0; 
        p15 <= 16'd0;
        
        p21 <= 16'd0; 
        p22 <= 16'd0;
        p23 <= 16'd0; 
        p24 <= 16'd0; 
        p25 <= 16'd0;
        
        p31 <= 16'd0; 
        p32 <= 16'd0; 
        p33 <= 16'd0;
        p34 <= 16'd0; 
        p35 <= 16'd0;
        
        p41 <= 16'd0; 
        p42 <= 16'd0; 
        p43 <= 16'd0; 
        p44 <= 16'd0;
        p45 <= 16'd0;
        
        p51 <= 16'd0; 
        p52 <= 16'd0; 
        p53 <= 16'd0; 
        p54 <= 16'd0; 
        p55 <= 16'd0;
    end else begin
        vs_r1 <= vs_in;
        vs_r2 <= vs_r1;
        vs_r3 <= vs_r2;
        vs_r4 <= vs_r3;
        
        if (vs_r4) begin
            p11 <= 16'd0;
            p12 <= 16'd0; 
            p13 <= 16'd0; 
            p14 <= 16'd0; 
            p15 <= 16'd0;
            
            p21 <= 16'd0; 
            p22 <= 16'd0;
            p23 <= 16'd0; 
            p24 <= 16'd0; 
            p25 <= 16'd0;
            
            p31 <= 16'd0; 
            p32 <= 16'd0; 
            p33 <= 16'd0;
            p34 <= 16'd0; 
            p35 <= 16'd0;
            
            p41 <= 16'd0; 
            p42 <= 16'd0; 
            p43 <= 16'd0; 
            p44 <= 16'd0;
            p45 <= 16'd0;
            
            p51 <= 16'd0; 
            p52 <= 16'd0; 
            p53 <= 16'd0; 
            p54 <= 16'd0; 
            p55 <= 16'd0;
        end else begin
            // 5x5 移位寄存器
            {p15, p14, p13, p12, p11} <= {p14, p13, p12, p11, row4};
            {p25, p24, p23, p22, p21} <= {p24, p23, p22, p21, row3};
            {p35, p34, p33, p32, p31} <= {p34, p33, p32, p31, row2};
            {p45, p44, p43, p42, p41} <= {p44, p43, p42, p41, row1};
            {p55, p54, p53, p52, p51} <= {p54, p53, p52, p51, row0};
        end
    end
end

// 提取所有像素的 RGB 分量
wire [7:0] R11;
wire [7:0] G11;
wire [7:0] B11;
assign R11 = {3'b0, p11[15:11]};
assign G11 = {2'b0, p11[10:5]};
assign B11 = {3'b0, p11[4:0]};

wire [7:0] R12;
wire [7:0] G12;
wire [7:0] B12;
assign R12 = {3'b0, p12[15:11]};
assign G12 = {2'b0, p12[10:5]};
assign B12 = {3'b0, p12[4:0]};

wire [7:0] R13;
wire [7:0] G13;
wire [7:0] B13;
assign R13 = {3'b0, p13[15:11]};
assign G13 = {2'b0, p13[10:5]};
assign B13 = {3'b0, p13[4:0]};

wire [7:0] R14;
wire [7:0] G14;
wire [7:0] B14;
assign R14 = {3'b0, p14[15:11]};
assign G14 = {2'b0, p14[10:5]};
assign B14 = {3'b0, p14[4:0]};

wire [7:0] R15;
wire [7:0] G15;
wire [7:0] B15;
assign R15 = {3'b0, p15[15:11]};
assign G15 = {2'b0, p15[10:5]};
assign B15 = {3'b0, p15[4:0]};

wire [7:0] R21;
wire [7:0] G21;
wire [7:0] B21;
assign R21 = {3'b0, p21[15:11]};
assign G21 = {2'b0, p21[10:5]};
assign B21 = {3'b0, p21[4:0]};

wire [7:0] R22;
wire [7:0] G22;
wire [7:0] B22;
assign R22 = {3'b0, p22[15:11]};
assign G22 = {2'b0, p22[10:5]};
assign B22 = {3'b0, p22[4:0]};

wire [7:0] R23;
wire [7:0] G23;
wire [7:0] B23;
assign R23 = {3'b0, p23[15:11]};
assign G23 = {2'b0, p23[10:5]};
assign B23 = {3'b0, p23[4:0]};

wire [7:0] R24;
wire [7:0] G24;
wire [7:0] B24;
assign R24 = {3'b0, p24[15:11]};
assign G24 = {2'b0, p24[10:5]};
assign B24 = {3'b0, p24[4:0]};

wire [7:0] R25;
wire [7:0] G25;
wire [7:0] B25;
assign R25 = {3'b0, p25[15:11]};
assign G25 = {2'b0, p25[10:5]};
assign B25 = {3'b0, p25[4:0]};

wire [7:0] R31;
wire [7:0] G31;
wire [7:0] B31;
assign R31 = {3'b0, p31[15:11]};
assign G31 = {2'b0, p31[10:5]};
assign B31 = {3'b0, p31[4:0]};

wire [7:0] R32;
wire [7:0] G32;
wire [7:0] B32;
assign R32 = {3'b0, p32[15:11]};
assign G32 = {2'b0, p32[10:5]};
assign B32 = {3'b0, p32[4:0]};

wire [7:0] R33;
wire [7:0] G33;
wire [7:0] B33;
assign R33 = {3'b0, p33[15:11]};
assign G33 = {2'b0, p33[10:5]};
assign B33 = {3'b0, p33[4:0]};

wire [7:0] R34;
wire [7:0] G34;
wire [7:0] B34;
assign R34 = {3'b0, p34[15:11]};
assign G34 = {2'b0, p34[10:5]};
assign B34 = {3'b0, p34[4:0]};

wire [7:0] R35;
wire [7:0] G35;
wire [7:0] B35;
assign R35 = {3'b0, p35[15:11]};
assign G35 = {2'b0, p35[10:5]};
assign B35 = {3'b0, p35[4:0]};

wire [7:0] R41;
wire [7:0] G41;
wire [7:0] B41;
assign R41 = {3'b0, p41[15:11]};
assign G41 = {2'b0, p41[10:5]};
assign B41 = {3'b0, p41[4:0]};

wire [7:0] R42;
wire [7:0] G42;
wire [7:0] B42;
assign R42 = {3'b0, p42[15:11]};
assign G42 = {2'b0, p42[10:5]};
assign B42 = {3'b0, p42[4:0]};

wire [7:0] R43;
wire [7:0] G43;
wire [7:0] B43;
assign R43 = {3'b0, p43[15:11]};
assign G43 = {2'b0, p43[10:5]};
assign B43 = {3'b0, p43[4:0]};

wire [7:0] R44;
wire [7:0] G44;
wire [7:0] B44;
assign R44 = {3'b0, p44[15:11]};
assign G44 = {2'b0, p44[10:5]};
assign B44 = {3'b0, p44[4:0]};

wire [7:0] R45;
wire [7:0] G45;
wire [7:0] B45;
assign R45 = {3'b0, p45[15:11]};
assign G45 = {2'b0, p45[10:5]};
assign B45 = {3'b0, p45[4:0]};

wire [7:0] R51;
wire [7:0] G51;
wire [7:0] B51;
assign R51 = {3'b0, p51[15:11]};
assign G51 = {2'b0, p51[10:5]};
assign B51 = {3'b0, p51[4:0]};

wire [7:0] R52;
wire [7:0] G52;
wire [7:0] B52;
assign R52 = {3'b0, p52[15:11]};
assign G52 = {2'b0, p52[10:5]};
assign B52 = {3'b0, p52[4:0]};

wire [7:0] R53;
wire [7:0] G53;
wire [7:0] B53;
assign R53 = {3'b0, p53[15:11]};
assign G53 = {2'b0, p53[10:5]};
assign B53 = {3'b0, p53[4:0]};

wire [7:0] R54;
wire [7:0] G54;
wire [7:0] B54;
assign R54 = {3'b0, p54[15:11]};
assign G54 = {2'b0, p54[10:5]};
assign B54 = {3'b0, p54[4:0]};

wire [7:0] R55;
wire [7:0] G55;
wire [7:0] B55;
assign R55 = {3'b0, p55[15:11]};
assign G55 = {2'b0, p55[10:5]};
assign B55 = {3'b0, p55[4:0]};

// 对每个颜色分量求25个像素的和
wire [15:0] sum_R;
assign sum_R = 16'd0 + R11 + R12 + R13 + R14 + R15 
                     + R21 + R22 + R23 + R24 + R25 
                     + R31 + R32 + R33 + R34 + R35
                     + R41 + R42 + R43 + R44 + R45 
                     + R51 + R52 + R53 + R54 + R55;

wire [15:0] sum_G;
assign sum_G = 16'd0 + G11 + G12 + G13 + G14 + G15 
                     + G21 + G22 + G23 + G24 + G25 
                     + G31 + G32 + G33 + G34 + G35
                     + G41 + G42 + G43 + G44 + G45 
                     + G51 + G52 + G53 + G54 + G55;

wire [15:0] sum_B;
assign sum_B = 16'd0 + B11 + B12 + B13 + B14 + B15 
                     + B21 + B22 + B23 + B24 + B25 
                     + B31 + B32 + B33 + B34 + B35
                     + B41 + B42 + B43 + B44 + B45 
                     + B51 + B52 + B53 + B54 + B55;

//(sum * 5) / 128 等效于除以 25.6，这里用移位加法 (sum<<2)+sum 实现乘以 5
wire [4:0] R_out;
assign R_out = (((sum_R << 2) + sum_R) >> 7) & 5'h1F;

wire [5:0] G_out;
assign G_out = (((sum_G << 2) + sum_G) >> 7) & 6'h3F;

wire [4:0] B_out;
assign B_out = (((sum_B << 2) + sum_B) >> 7) & 5'h1F;

wire [15:0] filtered_pixel;
assign filtered_pixel = {R_out, G_out, B_out};

reg [15:0] din_pipe0;
reg [15:0] din_pipe1;
reg [15:0] din_pipe2;
reg [15:0] din_pipe3;
reg [15:0] din_pipe4;

reg valid_pipe0;
reg valid_pipe1;
reg valid_pipe2;
reg valid_pipe3;
reg valid_pipe4;

reg vs_pipe0;
reg vs_pipe1;
reg vs_pipe2;
reg vs_pipe3;
reg vs_pipe4;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        din_pipe0 <= 16'd0; 
        din_pipe1 <= 16'd0; 
        din_pipe2 <= 16'd0; 
        din_pipe3 <= 16'd0; 
        din_pipe4 <= 16'd0;
        
        valid_pipe0 <= 1'b0; 
        valid_pipe1 <= 1'b0; 
        valid_pipe2 <= 1'b0; 
        valid_pipe3 <= 1'b0; 
        valid_pipe4 <= 1'b0;
        
        vs_pipe0 <= 1'b0; 
        vs_pipe1 <= 1'b0; 
        vs_pipe2 <= 1'b0; 
        vs_pipe3 <= 1'b0; 
        vs_pipe4 <= 1'b0;
    end else begin
        din_pipe0 <= din;
        valid_pipe0 <= din_valid;
        vs_pipe0 <= vs_in;
        
        din_pipe1 <= din_pipe0;
        valid_pipe1 <= valid_pipe0;
        vs_pipe1 <= vs_pipe0;
        
        din_pipe2 <= din_pipe1;
        valid_pipe2 <= valid_pipe1;
        vs_pipe2 <= vs_pipe1;
        
        din_pipe3 <= din_pipe2;
        valid_pipe3 <= valid_pipe2;
        vs_pipe3 <= vs_pipe2;
        
        din_pipe4 <= din_pipe3;
        valid_pipe4 <= valid_pipe3;
        vs_pipe4 <= vs_pipe3;
    end
end

wire [15:0] raw_delayed;
assign raw_delayed = din_pipe4;

assign dout = filter_en ? filtered_pixel : raw_delayed;
assign dout_valid = valid_pipe4;
assign vs_out = vs_pipe4;

endmodule