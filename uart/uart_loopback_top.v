

module uart_loopback_top(
    input           sys_clk,            //外部50M时钟
    input           sys_rst_n,          //外部复位信号，低有效

    //output          led1 ,        //LED灯

    input           uart_rxd,           //UART接收端口
    output          uart_txd            //UART发送端口
    );

//parameter define
parameter  CLK_FREQ = 50000000;         //定义系统时钟频率
parameter  UART_BPS = 115200;           //定义串口波特率
    
//wire define   
wire       uart_recv_done;              //UART接收完成
wire [7:0] uart_recv_data;              //UART接收数据
wire       uart_send_en;                //UART发送使能
wire [7:0] uart_send_data;              //UART发送数据
wire       uart_tx_busy;                //UART发送忙状态标志

reg  [25:0]  cnt ;
//*****************************************************
//**                    main code
//*****************************************************
//assign led1 = (cnt < 26'd2500_0000) ? 1'b1 : 1'b0 ;
//计数器在0~5000_000之间进行计数
always @ (posedge sys_clk or negedge sys_rst_n) begin
    if(!sys_rst_n)
        cnt <= 26'd0;
    else if(cnt < 26'd5000_0000)
        cnt <= cnt + 1'b1;
    else
        cnt <= 26'd0;
end

//串口接收模块     
uart_recv #(                          
    .CLK_FREQ       (CLK_FREQ),         //设置系统时钟频率
    .UART_BPS       (UART_BPS))         //设置串口接收波特率
u_uart_recv(                 
    .sys_clk        (sys_clk), 
    .sys_rst_n      (sys_rst_n),
    
    .uart_rxd       (uart_rxd),
    .uart_done      (uart_recv_done),
    .uart_data      (uart_recv_data)
    );

//串口发送模块    
uart_send #(                          
    .CLK_FREQ       (CLK_FREQ),         //设置系统时钟频率
    .UART_BPS       (UART_BPS))         //设置串口发送波特率
u_uart_send(                 
    .sys_clk        (sys_clk),
    .sys_rst_n      (sys_rst_n),
     
    .uart_en        (uart_send_en),
    .uart_din       (uart_send_data),
    .uart_tx_busy   (uart_tx_busy),
    .uart_txd       (uart_txd)
    );
    
//串口环回模块    
uart_loop u_uart_loop(
    .sys_clk        (sys_clk),             
    .sys_rst_n      (sys_rst_n),           
   
    .recv_done      (uart_recv_done),   //接收一帧数据完成标志信号
    .recv_data      (uart_recv_data),   //接收的数据
   
    .tx_busy        (uart_tx_busy),     //发送忙状态标志      
    .send_en        (uart_send_en),     //发送使能信号
    .send_data      (uart_send_data)    //待发送数据
    );
    
endmodule