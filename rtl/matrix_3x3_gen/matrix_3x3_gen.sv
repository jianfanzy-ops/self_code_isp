module matrix_3x3_gen#(
     parameter    PIXEL_WIDTH            = 10	,
     parameter    PIXEL_TAP_NUM          = 8	,  
     parameter    PIXEL_AXIS_USER_WIDTH  = 4	,
     parameter    PIXEL_LINE_WIDTH_MAX	 = 2048 
  
)    
(    
     input  logic                                            i_pixel_clk	  	,//    
     input  logic                                            i_pixel_rst_n		,
	 input  logic [15:0]                                     i_x_width          , 
	 input  logic [15:0]                                     i_y_height         ,
     input  logic                                            i_s_axis_tvalid  	,//
     output logic                                            o_s_axis_tready  	,//
     input  logic [PIXEL_TAP_NUM-1:0] [PIXEL_WIDTH-1:0]      i_s_axis_tdata   	,//
     input  logic [PIXEL_AXIS_USER_WIDTH-1:0]                i_s_axis_tuser   	,//
     output logic                                            o_m_axis_tvalid  =0,//
     input  logic                                            i_m_axis_tready    , //	
     output logic [PIXEL_TAP_NUM-1:0][8:0][PIXEL_WIDTH-1:0]  o_m_axis_tdata     ,//
     output logic [PIXEL_AXIS_USER_WIDTH-1:0]                o_m_axis_tuser   =0 //
);  

  `include "./../define_isp.sv"
  localparam RAM_RD_LATENCY = 2;
  localparam USE_AT_FLD_IF  = 1;
  
  
  
  logic [$clog2(PIXEL_LINE_WIDTH_MAX/PIXEL_TAP_NUM)-1:0] line1_wr_addr=0;
  logic [$clog2(PIXEL_LINE_WIDTH_MAX/PIXEL_TAP_NUM)-1:0] line1_rd_addr=0;
  logic [$clog2(PIXEL_LINE_WIDTH_MAX/PIXEL_TAP_NUM)-1:0] line2_wr_addr=0;
  
  logic [RAM_RD_LATENCY:0]                                     r_s_axis_tvalid = 0;
  logic [RAM_RD_LATENCY:0][PIXEL_AXIS_USER_WIDTH-1:0]          r_s_axis_tuser  = 0;
  logic [RAM_RD_LATENCY:0][PIXEL_TAP_NUM-1:0][PIXEL_WIDTH-1:0] r_s_axis_tdata  = 0;

  logic      [PIXEL_TAP_NUM-1:0][PIXEL_WIDTH-1:0]   line0_data    	 ;
  logic      [PIXEL_TAP_NUM-1:0][PIXEL_WIDTH-1:0]   line1_data    	 ;
  logic      [PIXEL_TAP_NUM-1:0][PIXEL_WIDTH-1:0]   line2_data    	 ;  
  logic [1:0][PIXEL_TAP_NUM-1:0][PIXEL_WIDTH-1:0] r_line0_data=0  	 ; 
  logic [1:0][PIXEL_TAP_NUM-1:0][PIXEL_WIDTH-1:0] r_line1_data=0  	 ;
  logic [1:0][PIXEL_TAP_NUM-1:0][PIXEL_WIDTH-1:0] r_line2_data=0  	 ;  
  	 
  logic [PIXEL_TAP_NUM-1:0][PIXEL_WIDTH-1:0] matrix_0;
  logic [PIXEL_TAP_NUM-1:0][PIXEL_WIDTH-1:0] matrix_1; 
  logic [PIXEL_TAP_NUM-1:0][PIXEL_WIDTH-1:0] matrix_2;  
  logic [PIXEL_TAP_NUM-1:0][PIXEL_WIDTH-1:0] matrix_3; 
  logic [PIXEL_TAP_NUM-1:0][PIXEL_WIDTH-1:0] matrix_4;
  logic [PIXEL_TAP_NUM-1:0][PIXEL_WIDTH-1:0] matrix_5;
  logic [PIXEL_TAP_NUM-1:0][PIXEL_WIDTH-1:0] matrix_6; 
  logic [PIXEL_TAP_NUM-1:0][PIXEL_WIDTH-1:0] matrix_7;
  logic [PIXEL_TAP_NUM-1:0][PIXEL_WIDTH-1:0] matrix_8;
  
  logic [15:0] cnt_y=0;
  logic        last_line=0;
  logic [RAM_RD_LATENCY+1:0] r_last_line=0;

  logic [31:0]   cnt_line_gap    = 0;
  logic [31:0]   r_cnt_line_gap  = 0;
  logic          cnt_line_gap_en = 0;
  
  always @ (posedge i_pixel_clk)
    if(i_m_axis_tready) begin
         if(i_s_axis_tuser[`SOF] & i_s_axis_tvalid) 	
             cnt_y <= 0;			 
    else if(r_s_axis_tuser[RAM_RD_LATENCY][`EOF] & r_s_axis_tvalid[RAM_RD_LATENCY])	
             cnt_y <= 0;  	 
	else if(r_s_axis_tuser[RAM_RD_LATENCY][`EOL] & r_s_axis_tvalid[RAM_RD_LATENCY])
		     cnt_y <= cnt_y + 1'b1;
  end	

  assign o_s_axis_tready = i_m_axis_tready;
  assign line0_data      = r_s_axis_tdata [RAM_RD_LATENCY-1];		

generate if(USE_AT_FLD_IF) begin : USE_AT_FLD_IF_PRC
  
  always @ (posedge i_pixel_clk) 
    if(i_m_axis_tready) begin 
             if(r_cnt_line_gap !=0 && cnt_line_gap == 0)		      
                last_line <= 1'b1;
	    else if(line1_rd_addr == (i_x_width >> $clog2(PIXEL_TAP_NUM)) - 1)
		        last_line <= 1'b0;
    end 	  
	
  always @ (posedge i_pixel_clk) begin 
    if(i_m_axis_tready) begin 
              if(cnt_y == 1 && r_s_axis_tuser[RAM_RD_LATENCY][`EOL] & r_s_axis_tvalid[RAM_RD_LATENCY])
                  cnt_line_gap_en <= 1'b1;
       	 else if(r_s_axis_tuser[RAM_RD_LATENCY][`SOL] & r_s_axis_tvalid[RAM_RD_LATENCY])
                  cnt_line_gap_en <= 1'b0;		 
    end
  end 
  
  always @ (posedge i_pixel_clk) begin 
    if(i_m_axis_tready) begin 
            if(`i_pixel_valid & `i_sof)
             cnt_line_gap <= 0;	           
	 else if(cnt_line_gap_en) 
		     cnt_line_gap <= cnt_line_gap + 1'b1;   	 
     else if(cnt_y == 0 && cnt_line_gap != 0)
	         cnt_line_gap <= cnt_line_gap - 1'b1;
    end 
  end 	

  always @ (posedge i_pixel_clk) begin 
      if(i_m_axis_tready) begin 
         r_cnt_line_gap <= cnt_line_gap;
	  end	 
	end	
	
end else begin : NOT_USE_AT_FLD_IF_PRC

  always @ (posedge i_pixel_clk) 
    if(i_m_axis_tready) begin 
             if(r_s_axis_tuser[RAM_RD_LATENCY][`EOF] & r_s_axis_tvalid[RAM_RD_LATENCY])		      
                last_line <= 1'b1;
	    else if(line1_rd_addr == (i_x_width >> $clog2(PIXEL_TAP_NUM)) - 1)
		        last_line <= 1'b0;
    end 
	
end     
endgenerate



  always @ (posedge i_pixel_clk)
         if(i_m_axis_tready)
         begin 	 
             for(int i=1;i<=RAM_RD_LATENCY;i++)
			 begin 
				r_s_axis_tvalid[0] <= i_s_axis_tvalid     ;
				r_s_axis_tvalid[i] <= r_s_axis_tvalid[i-1];
			    r_s_axis_tuser [0] <= i_s_axis_tuser      ;
				r_s_axis_tuser [i] <= r_s_axis_tuser[i-1] ;
				r_s_axis_tdata [0] <= i_s_axis_tdata	  ;
				r_s_axis_tdata [i] <= r_s_axis_tdata[i-1] ;	
				
				r_last_line[0]     <= last_line           ;
				r_last_line[i]     <= r_last_line[i-1]    ;
				r_last_line[RAM_RD_LATENCY+1]   <= r_last_line[RAM_RD_LATENCY]    ;
			 end
		 end
		 
  always @ (posedge i_pixel_clk)
         if(i_m_axis_tready)  
         begin		 
			 r_line0_data[0] <= line0_data;
			 r_line1_data[0] <= line1_data;
			 r_line2_data[0] <= line2_data;
		 for(int i=1;i<2;i++)
			begin 		 
			 r_line0_data[i] <= r_line0_data[i-1];
			 r_line1_data[i] <= r_line1_data[i-1];
			 r_line2_data[i] <= r_line2_data[i-1];
			end  
         end
		 
  always @ (posedge i_pixel_clk)
	if(i_m_axis_tready) begin 
         if(r_s_axis_tuser[0][`EOL] & r_s_axis_tvalid[0])
			line1_wr_addr <= 'd0;        
	else if(r_s_axis_tvalid[0])
			line1_wr_addr <= line1_wr_addr + 1'b1;
    end 
		
  always @ (posedge i_pixel_clk)
	if(i_m_axis_tready) begin 
	     if(r_s_axis_tuser[RAM_RD_LATENCY-1][`EOL] & r_s_axis_tvalid[RAM_RD_LATENCY-1])
	        line2_wr_addr <= 'd0;
    else if(r_s_axis_tvalid[RAM_RD_LATENCY-1])
		    line2_wr_addr <= line2_wr_addr + 1'b1;
    end
	
	
  always @ (posedge i_pixel_clk)
	if(i_m_axis_tready) begin 
		   if(line1_rd_addr == (i_x_width >> $clog2(PIXEL_TAP_NUM)) - 1)
	          line1_rd_addr <= 'd0;			 
     else  if(i_s_axis_tuser[`EOL] && cnt_y != 0 && i_s_axis_tvalid)
	          line1_rd_addr <= 'd0;	
     else  if(last_line)
		      line1_rd_addr <= line1_rd_addr + 1'b1;
     else  if(i_s_axis_tvalid && cnt_y != 0)
		      line1_rd_addr <= line1_rd_addr + 1'b1;	 	 
    end  
	
	
	two_port_ram_isp 
	#(
	 .DATA_WIDTH     	(PIXEL_TAP_NUM * PIXEL_WIDTH       ),  // Data x_width
	 .DATA_DEEPTH    	(PIXEL_LINE_WIDTH_MAX/PIXEL_TAP_NUM),  // Data Depth   
	 .DATA_RD_LATENCY	(RAM_RD_LATENCY                    )  // Greater than 0
	) 
	line_1_data_ram 
	(
	 .i_clk_wr     		(i_pixel_clk      			),
	 .i_wr_en      		(i_m_axis_tready & r_s_axis_tvalid[0]), 
	 .i_wr_addr    		(line1_wr_addr  			),
	 .i_din        		(r_s_axis_tdata[0]   	    ),
	 .i_clk_rd     		(i_pixel_clk      			),	
	 .i_rd_en      		(i_s_axis_tvalid | last_line),
	 .i_rd_oce     		(i_m_axis_tready            ),
	 .i_rd_addr    		(line1_rd_addr  			),	
	 .o_dout       		(line1_data           	 	)
	);
	
	two_port_ram_isp 
	#(
	 .DATA_WIDTH     	(PIXEL_TAP_NUM * PIXEL_WIDTH       ),  // Data x_width
	 .DATA_DEEPTH    	(PIXEL_LINE_WIDTH_MAX/PIXEL_TAP_NUM),  // Data Depth   
	 .DATA_RD_LATENCY	(RAM_RD_LATENCY                    )  // Greater than 0
	) 
	line_2_data_ram 
	(
	 .i_clk_wr     		(i_pixel_clk      			      ),
	 .i_wr_en      		(i_m_axis_tready & r_s_axis_tvalid[RAM_RD_LATENCY-1]), 
	 .i_wr_addr    		(line2_wr_addr  			      ),
	 .i_din        		(line1_data            	          ),
	 .i_clk_rd     		(i_pixel_clk      			      ),	
	 .i_rd_en      		(i_s_axis_tvalid | last_line      ),
	 .i_rd_oce     		(i_m_axis_tready                  ),
	 .i_rd_addr    		(line1_rd_addr  			      ),	
	 .o_dout       		(line2_data           	 	      )
	);	
  
//3x3 martix 
generate
      if(PIXEL_TAP_NUM == 1) 
  begin      
         assign matrix_2 = r_line2_data[0];             
		 assign matrix_5 = r_line1_data[0];             
		 assign matrix_8 = r_line0_data[0];	
		 
  always @ (posedge i_pixel_clk)
		if(i_m_axis_tready)  
         begin
		     matrix_0 <= matrix_1;
             matrix_1 <= matrix_2;
			 matrix_3 <= matrix_4;	
			 matrix_4 <= matrix_5;			 
			 matrix_6 <= matrix_7; 
			 matrix_7 <= matrix_8;
		 end
  end		 
  else if(PIXEL_TAP_NUM == 2)
  begin 
  always @ (posedge i_pixel_clk)
		if(i_m_axis_tready) 
         begin
		   matrix_0[0] <= r_line2_data[1][PIXEL_TAP_NUM-1]	;
		   matrix_1[0] <= r_line2_data[0][0]        	  	;
		   matrix_2[0] <= r_line2_data[0][1]        	  	;
		   matrix_3[0] <= r_line1_data[1][PIXEL_TAP_NUM-1] 	;
		   matrix_4[0] <= r_line1_data[0][0]        		;
		   matrix_5[0] <= r_line1_data[0][1]        		;
		   matrix_6[0] <= r_line0_data[1][PIXEL_TAP_NUM-1]	;
		   matrix_7[0] <= r_line0_data[0][0]        	    ;
		   matrix_8[0] <= r_line0_data[0][1]        	    ;
		   
		   matrix_0[PIXEL_TAP_NUM-1] <= r_line2_data[0][PIXEL_TAP_NUM-2];
		   matrix_1[PIXEL_TAP_NUM-1] <= r_line2_data[0][PIXEL_TAP_NUM-1];
		   matrix_2[PIXEL_TAP_NUM-1] <=   line2_data[0]      			;
		   matrix_3[PIXEL_TAP_NUM-1] <= r_line1_data[0][PIXEL_TAP_NUM-2];
		   matrix_4[PIXEL_TAP_NUM-1] <= r_line1_data[0][PIXEL_TAP_NUM-1];	   
		   matrix_5[PIXEL_TAP_NUM-1] <=   line1_data[0]      			;
		   matrix_6[PIXEL_TAP_NUM-1] <= r_line0_data[0][PIXEL_TAP_NUM-2]	;
		   matrix_7[PIXEL_TAP_NUM-1] <= r_line0_data[0][PIXEL_TAP_NUM-1]	;
		   matrix_8[PIXEL_TAP_NUM-1] <=   line0_data[0]       			;
		 end 
  end     
  else if(PIXEL_TAP_NUM > 2)begin
     always @ (posedge i_pixel_clk)
		if(i_m_axis_tready) 
         begin  
		   matrix_0[0] <= r_line2_data[1][PIXEL_TAP_NUM-1]		;
		   matrix_1[0] <= r_line2_data[0][0]        			;
		   matrix_2[0] <= r_line2_data[0][1]        			;
		   matrix_3[0] <= r_line1_data[1][PIXEL_TAP_NUM-1]		;
		   matrix_4[0] <= r_line1_data[0][0]        			;
		   matrix_5[0] <= r_line1_data[0][1]        			;
		   matrix_6[0] <= r_line0_data[1][PIXEL_TAP_NUM-1]	;
		   matrix_7[0] <= r_line0_data[0][0]        			;
		   matrix_8[0] <= r_line0_data[0][1]        			;
		   
		   matrix_0[PIXEL_TAP_NUM-1] <= r_line2_data[0][PIXEL_TAP_NUM-2];
		   matrix_1[PIXEL_TAP_NUM-1] <= r_line2_data[0][PIXEL_TAP_NUM-1];
		   matrix_2[PIXEL_TAP_NUM-1] <=   line2_data[0]       			;
		   matrix_3[PIXEL_TAP_NUM-1] <= r_line1_data[0][PIXEL_TAP_NUM-2];
		   matrix_4[PIXEL_TAP_NUM-1] <= r_line1_data[0][PIXEL_TAP_NUM-1];	   
		   matrix_5[PIXEL_TAP_NUM-1] <=   line1_data[0]        			;
		   matrix_6[PIXEL_TAP_NUM-1] <= r_line0_data[0][PIXEL_TAP_NUM-2];
		   matrix_7[PIXEL_TAP_NUM-1] <= r_line0_data[0][PIXEL_TAP_NUM-1];
		   matrix_8[PIXEL_TAP_NUM-1] <=   line0_data[0]        			;			   
	     for(int i=1; i<PIXEL_TAP_NUM-1; i++)
		 begin   
		   matrix_0[i] <= r_line2_data[0][i-1]	;
		   matrix_1[i] <= r_line2_data[0][i]	;
		   matrix_2[i] <= r_line2_data[0][i+1]	;
		   matrix_3[i] <= r_line1_data[0][i-1]	;
		   matrix_4[i] <= r_line1_data[0][i]	;
		   matrix_5[i] <= r_line1_data[0][i+1]  ;
		   matrix_6[i] <= r_line0_data[0][i-1]	;
		   matrix_7[i] <= r_line0_data[0][i]  	;
		   matrix_8[i] <= r_line0_data[0][i+1]	;
		 end 
      end		
  end
endgenerate		 
 
  always @ (posedge i_pixel_clk)
		if(i_m_axis_tready)
		 begin
             o_m_axis_tuser[`EOF] <=   r_last_line[RAM_RD_LATENCY] & (~r_last_line[RAM_RD_LATENCY-1]);
            if(cnt_y > 0)
            begin			
			 o_m_axis_tvalid <= r_s_axis_tvalid[RAM_RD_LATENCY] | r_last_line[RAM_RD_LATENCY];
			 o_m_axis_tuser[`SOF] <= (cnt_y == 1) && r_s_axis_tuser[RAM_RD_LATENCY][`SOL];   
			 o_m_axis_tuser[`SOL] <=  r_s_axis_tuser[RAM_RD_LATENCY][`SOL];  
			 o_m_axis_tuser[`EOL] <=  r_s_axis_tuser[RAM_RD_LATENCY][`EOL] | (r_last_line[RAM_RD_LATENCY] & (~r_last_line[RAM_RD_LATENCY-1]));  			 
		    end
	        else begin 
			 o_m_axis_tvalid      <=   r_last_line[RAM_RD_LATENCY];
			 o_m_axis_tuser[`SOL] <= (~r_last_line[RAM_RD_LATENCY+1]) &   r_last_line[RAM_RD_LATENCY]   ; 
			 o_m_axis_tuser[`EOL] <=   r_last_line[RAM_RD_LATENCY]    & (~r_last_line[RAM_RD_LATENCY-1]); 
            end			  
		 end
		 
generate if(PIXEL_AXIS_USER_WIDTH > 4)
  always @ (posedge i_pixel_clk) begin 
         if(`i_pixel_valid & `i_sof) 
		     o_m_axis_tuser[PIXEL_AXIS_USER_WIDTH-1:`EOF+1] <=  i_s_axis_tuser[PIXEL_AXIS_USER_WIDTH-1:`EOF+1];
  end 
endgenerate
	 
  always @ (*)
		for(int i=0;i<PIXEL_TAP_NUM;i++)
        begin		 
            o_m_axis_tdata[i][0] = matrix_0[i];  
            o_m_axis_tdata[i][1] = matrix_1[i]; 
            o_m_axis_tdata[i][2] = matrix_2[i]; 
			o_m_axis_tdata[i][3] = matrix_3[i];
			o_m_axis_tdata[i][4] = matrix_4[i];
			o_m_axis_tdata[i][5] = matrix_5[i];
			o_m_axis_tdata[i][6] = matrix_6[i];
			o_m_axis_tdata[i][7] = matrix_7[i];
			o_m_axis_tdata[i][8] = matrix_8[i];
		end
endmodule 