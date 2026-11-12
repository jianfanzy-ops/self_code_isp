`timescale 1ns/1ps
////////////////////////////////////////////////////////////////////////////
// Company               :       
// Engineer              :     
// Function              :       two line FIFOs build the 3x3 window of every pixel, tvalid / tuser belong to the window center [4].
//                               A beat moves only on a handshake, so tvalid may be discontinuous. The last line is flushed after EOF.
// Creat Date            :       2024/5/17 
// Module Name           :       matrix_3x3_gen
// Tool Versions         :       modelsim 10.4d
// Description           :       Matrix_3x3_gen axi_stream interface    
// Vresion 1.0           :       File Created     

//-------------------- Modification History -----------------------------------
//2024/5/17            v1.0     :     File Created
//2026/7/06            v2.0     :     fix bug

module matrix_3x3_gen #(
    parameter PIXEL_WIDTH           = 10  ,//bits per pixel
    parameter PIXEL_TAP_NUM         = 8   ,//pixels per beat
    parameter PIXEL_AXIS_USER_WIDTH = 4   ,//0:SOF 1:SOL 2:EOL 3:EOF, higher bits: module flags
    parameter PIXEL_LINE_WIDTH_MAX  = 2048 //unit: pixels, line buffer depth
)(
    input  logic                                            i_pixel_clk         ,
    input  logic                                            i_pixel_rst_n       ,//active-low
    // configuration, not used: line width and frame height follow tuser
    input  logic [15:0]                                     i_x_width           ,//unit: pixels
    input  logic [15:0]                                     i_y_height          ,//unit: lines
    // input stream
    input  logic                                            i_s_axis_tvalid     ,
    output logic                                            o_s_axis_tready     ,
    input  logic [PIXEL_TAP_NUM-1:0][PIXEL_WIDTH-1:0]       i_s_axis_tdata      ,//new pixel in the high bits
    input  logic [PIXEL_AXIS_USER_WIDTH-1:0]                i_s_axis_tuser      ,
    // output stream
    output logic                                            o_m_axis_tvalid = 0 ,
    input  logic                                            i_m_axis_tready     ,
    output logic [PIXEL_TAP_NUM-1:0][8:0][PIXEL_WIDTH-1:0]  o_m_axis_tdata  = 0 ,//0 1 2 / 3 4 5 / 6 7 8, 4 = center
    output logic [PIXEL_AXIS_USER_WIDTH-1:0]                o_m_axis_tuser  = 0
);

    `include "./../define_isp.sv"

    localparam DATA_WIDTH = PIXEL_TAP_NUM*PIXEL_WIDTH;
    localparam FIFO_DEPTH = PIXEL_LINE_WIDTH_MAX/PIXEL_TAP_NUM + 16;//unit: beats, one line plus margin for the full flag delay

    // step: one beat enters the window, from the input or from the flush of the last line
    logic                                            s_axis_hs            ;
    logic                                            fifo_ready           ;
    logic                                            flush_step           ;
    logic                                            step                 ;

    // line count and flush of the last line
    logic [1:0]                                      line_cnt        = 0  ;//lines received in this frame, saturates at 2
    logic                                            line1_en             ;//center line is in FIFO 1
    logic                                            line2_en             ;//line above the center is in FIFO 2
    logic                                            end_stream_flag = 0  ;//EOF received, last line is being flushed
    logic [15:0]                                     line_gap_cnt    = 0  ;//unit: enabled clocks since the last EOL
    logic [15:0]                                     line_gap        = 0  ;//line gap of the input
    logic                                            flush_gap_done       ;

    // line FIFO 1: previous line with its tuser, the window center
    logic                                            line1_fifo_wr_en     ;
    logic                                            line1_fifo_wr_full   ;
    logic                                            line1_fifo_rd_en     ;
    logic                                            line1_fifo_rd_empty  ;
    logic [PIXEL_AXIS_USER_WIDTH+DATA_WIDTH-1:0]     line1_fifo_rd_data   ;
    logic [PIXEL_AXIS_USER_WIDTH-1:0]                line1_tuser          ;
    logic [PIXEL_TAP_NUM-1:0][PIXEL_WIDTH-1:0]       line1_tdata          ;

    // line FIFO 2: the line before the previous line
    logic                                            line2_fifo_wr_en     ;
    logic                                            line2_fifo_wr_full   ;
    logic                                            line2_fifo_rd_en     ;
    logic                                            line2_fifo_rd_empty  ;
    logic [PIXEL_TAP_NUM-1:0][PIXEL_WIDTH-1:0]       line2_tdata          ;

    // window columns: cur = beat of the center, prev = last pixel of the beat before it
    logic                                            cur_tvalid      = 0  ;
    logic [PIXEL_AXIS_USER_WIDTH-1:0]                cur_tuser       = 0  ;
    logic [PIXEL_TAP_NUM-1:0][PIXEL_WIDTH-1:0]       cur_line0_tdata = 0  ;
    logic [PIXEL_TAP_NUM-1:0][PIXEL_WIDTH-1:0]       cur_line1_tdata = 0  ;
    logic [PIXEL_TAP_NUM-1:0][PIXEL_WIDTH-1:0]       cur_line2_tdata = 0  ;
    logic [PIXEL_WIDTH-1:0]                          prev_line0_pixel = 0 ;
    logic [PIXEL_WIDTH-1:0]                          prev_line1_pixel = 0 ;
    logic [PIXEL_WIDTH-1:0]                          prev_line2_pixel = 0 ;

    // 3x3 window: {first pixel of the next beat, cur, prev}, pixel i of cur is at [i+1]
    logic                                            matrix_3x3_tvalid    ;
    logic [PIXEL_TAP_NUM+1:0][PIXEL_WIDTH-1:0]       matrix_line0_tdata   ;
    logic [PIXEL_TAP_NUM+1:0][PIXEL_WIDTH-1:0]       matrix_line1_tdata   ;
    logic [PIXEL_TAP_NUM+1:0][PIXEL_WIDTH-1:0]       matrix_line2_tdata   ;

    //--------------------------------------------------------------------------
    // step
    //--------------------------------------------------------------------------
    assign line1_en        = line_cnt != 0;
    assign line2_en        = line_cnt[1];
    assign fifo_ready      = (~line1_en | ~line1_fifo_rd_empty) & (~line2_en | ~line2_fifo_rd_empty)
                           & ~line1_fifo_wr_full & ~line2_fifo_wr_full;
    //no input while the last line is flushed; in reset the input is taken and dropped
    assign o_s_axis_tready = ~i_pixel_rst_n ? 1'b1 : i_m_axis_tready & fifo_ready & ~end_stream_flag;
    assign s_axis_hs       = i_s_axis_tvalid & o_s_axis_tready & i_pixel_rst_n;
    assign flush_step      = i_m_axis_tready & fifo_ready & end_stream_flag & flush_gap_done;
    assign step            = s_axis_hs | flush_step;

    //--------------------------------------------------------------------------
    // line count and flush of the last line
    //--------------------------------------------------------------------------
    always @ (posedge i_pixel_clk) begin
        if(~i_pixel_rst_n) begin
            line_cnt        <= '0;
            end_stream_flag <= 1'b0;
        end
        else if(flush_step) begin
            if(line1_tuser[`EOL]) begin
                line_cnt        <= '0;
                end_stream_flag <= 1'b0;
            end
        end
        else if(s_axis_hs & `i_eol) begin
            if(~line_cnt[1])
                line_cnt <= line_cnt + 1'b1;
            if(`i_eof)
                end_stream_flag <= 1'b1;
        end
    end

    //the flushed line starts after the same line gap as the input lines
    always @ (posedge i_pixel_clk) begin
        if(~i_pixel_rst_n) begin
            line_gap_cnt <= '0;
            line_gap     <= '0;
        end
        else if(i_m_axis_tready) begin
            if(s_axis_hs & `i_eol)
                line_gap_cnt <= '0;
            else if(~(&line_gap_cnt))
                line_gap_cnt <= line_gap_cnt + 1'b1;
            if(s_axis_hs & `i_sol & ~`i_sof)
                line_gap <= line_gap_cnt;
        end
    end

    assign flush_gap_done = line_gap_cnt >= line_gap;

    //--------------------------------------------------------------------------
    // line FIFOs, read and written only on a step
    //--------------------------------------------------------------------------
    assign line1_fifo_wr_en = s_axis_hs;
    assign line1_fifo_rd_en = step & line1_en;
    assign line2_fifo_wr_en = s_axis_hs & line1_en;
    assign line2_fifo_rd_en = step & line2_en;

    assign {line1_tuser, line1_tdata} = line1_fifo_rd_data;

    isp_dc_fifo #(
        .FIFO_MODE   ("ShowAhead"                          ),
        .DATA_WIDTH  (PIXEL_AXIS_USER_WIDTH+DATA_WIDTH     ),
        .FIFO_DEPTH  (FIFO_DEPTH                           )
    ) u_line1_fifo (
        .Reset       (~i_pixel_rst_n                       ), //System Reset
        .WrClk       (i_pixel_clk                          ), //(I)Write Clock
        .WrEn        (line1_fifo_wr_en                     ), //(I)Write Enable
        .WrData      ({i_s_axis_tuser, i_s_axis_tdata}     ), //(I)Write Data
        .WrDNum      (                                     ), //(O)Write Data Number In Fifo
        .WrFull      (line1_fifo_wr_full                   ), //(O)Write Full
        .RdClk       (i_pixel_clk                          ), //(I)Read Clock
        .RdEn        (line1_fifo_rd_en                     ), //(I)Read Enable
        .RdData      (line1_fifo_rd_data                   ), //(O)Read Data
        .DataVal     (                                     ), //(O)Data Valid
        .RdDNum      (                                     ), //(O)Read Data Number In Fifo
        .RdEmpty     (line1_fifo_rd_empty                  )  //(O)Read FifoEmpty
    );

    isp_dc_fifo #(
        .FIFO_MODE   ("ShowAhead"                          ),
        .DATA_WIDTH  (DATA_WIDTH                           ),
        .FIFO_DEPTH  (FIFO_DEPTH                           )
    ) u_line2_fifo (
        .Reset       (~i_pixel_rst_n                       ), //System Reset
        .WrClk       (i_pixel_clk                          ), //(I)Write Clock
        .WrEn        (line2_fifo_wr_en                     ), //(I)Write Enable
        .WrData      (line1_tdata                          ), //(I)Write Data
        .WrDNum      (                                     ), //(O)Write Data Number In Fifo
        .WrFull      (line2_fifo_wr_full                   ), //(O)Write Full
        .RdClk       (i_pixel_clk                          ), //(I)Read Clock
        .RdEn        (line2_fifo_rd_en                     ), //(I)Read Enable
        .RdData      (line2_tdata                          ), //(O)Read Data
        .DataVal     (                                     ), //(O)Data Valid
        .RdDNum      (                                     ), //(O)Read Data Number In Fifo
        .RdEmpty     (line2_fifo_rd_empty                  )  //(O)Read FifoEmpty
    );

    //--------------------------------------------------------------------------
    //1: window columns, line0 = input line, line1 = center line, line2 = line above
    //--------------------------------------------------------------------------
    always @ (posedge i_pixel_clk) begin
        if(~i_pixel_rst_n)
            cur_tvalid <= 1'b0;
        else if(step)
            cur_tvalid <= line1_en;
        else if(i_m_axis_tready & cur_tuser[`EOL])
            cur_tvalid <= 1'b0;
    end

    always @ (posedge i_pixel_clk) begin
        if(step) begin
            cur_tuser       <= line1_tuser;
            cur_line0_tdata <= i_s_axis_tdata;
            cur_line1_tdata <= line1_tdata;
            cur_line2_tdata <= line2_tdata;
        end
    end

    //the center beat leaves when the next beat arrives, the last beat of a line leaves at once
    assign matrix_3x3_tvalid = cur_tvalid & (step | cur_tuser[`EOL]);

    always @ (posedge i_pixel_clk) begin
        if(i_m_axis_tready & matrix_3x3_tvalid) begin
            prev_line0_pixel <= cur_line0_tdata[PIXEL_TAP_NUM-1];
            prev_line1_pixel <= cur_line1_tdata[PIXEL_TAP_NUM-1];
            prev_line2_pixel <= cur_line2_tdata[PIXEL_TAP_NUM-1];
        end
    end

    assign matrix_line0_tdata = {i_s_axis_tdata[0], cur_line0_tdata, prev_line0_pixel};
    assign matrix_line1_tdata = {line1_tdata[0]   , cur_line1_tdata, prev_line1_pixel};
    assign matrix_line2_tdata = {line2_tdata[0]   , cur_line2_tdata, prev_line2_pixel};

    //--------------------------------------------------------------------------
    //1+1: output register
    //--------------------------------------------------------------------------
    always @ (posedge i_pixel_clk) begin
        if(~i_pixel_rst_n)
            o_m_axis_tvalid <= 1'b0;
        else if(i_m_axis_tready)
            o_m_axis_tvalid <= matrix_3x3_tvalid;
    end

    always @ (posedge i_pixel_clk) begin
        if(i_m_axis_tready) begin
            o_m_axis_tuser <= cur_tuser;
            for(int i=0;i<PIXEL_TAP_NUM;i++) begin
                o_m_axis_tdata[i][0] <= matrix_line2_tdata[i]  ;
                o_m_axis_tdata[i][1] <= matrix_line2_tdata[i+1];
                o_m_axis_tdata[i][2] <= matrix_line2_tdata[i+2];
                o_m_axis_tdata[i][3] <= matrix_line1_tdata[i]  ;
                o_m_axis_tdata[i][4] <= matrix_line1_tdata[i+1];
                o_m_axis_tdata[i][5] <= matrix_line1_tdata[i+2];
                o_m_axis_tdata[i][6] <= matrix_line0_tdata[i]  ;
                o_m_axis_tdata[i][7] <= matrix_line0_tdata[i+1];
                o_m_axis_tdata[i][8] <= matrix_line0_tdata[i+2];
            end
        end
    end

    //////////////debug///////////////////

endmodule
