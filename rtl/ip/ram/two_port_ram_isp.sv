module two_port_ram_isp 
#(
    parameter  DATA_WIDTH      = 32  ,  // Data Width
    parameter  DATA_DEEPTH     = 256 ,  // Data Depth   
	parameter  DATA_RD_LATENCY = 1    // Greater than 0
)  
(
    input       	                      i_clk_wr ,
    input                                 i_wr_en  , 
    input  [$clog2(DATA_DEEPTH) - 1 : 0]  i_wr_addr,
	input  [DATA_WIDTH - 1 : 0]           i_din    ,
    input       	                      i_clk_rd ,	
    input                                 i_rd_en  ,	
    input                                 i_rd_oce ,	
    input  [$clog2(DATA_DEEPTH) - 1 : 0]  i_rd_addr, 
    output [DATA_WIDTH - 1 : 0]           o_dout
);	


  reg [DATA_WIDTH - 1 : 0] mem [0:DATA_DEEPTH - 1];
  
`ifdef SIMULATION
  initial begin 
    for(int i=0;i<DATA_DEEPTH;i++)
	mem[i] = 0;
  end 
`endif
  
  reg [DATA_RD_LATENCY-1:0][DATA_WIDTH - 1 : 0] dout=0;
  
  assign 	 o_dout = dout[DATA_RD_LATENCY-1];
  
  always @ (posedge i_clk_wr)
         begin
         if (i_wr_en) begin
             mem[i_wr_addr] <= i_din;
  	     end 
  end
  
  always @ (posedge i_clk_rd)
         begin
         if (i_rd_en & i_rd_oce) begin
             dout[0] <= mem[i_rd_addr];
         end
  end
generate if(DATA_RD_LATENCY > 1)
  always @ (posedge i_clk_rd)
         if(i_rd_oce)
         begin 
         for(int i=1;i<DATA_RD_LATENCY;i++)
	         dout[i] <= dout[i-1]; 
         end
endgenerate 

endmodule
