`define SOF 0                                            //don't change
`define SOL 1                                            //don't change
`define EOL 2                                            //don't change
`define EOF 3                                            //don't change

`define WB_FLAG  4                                       //don't change
`define CCM_FLAG 5                                       //don't change
`define FIR_FRAME 6                                       //don't change


														 
`define i_sof i_s_axis_tuser[`SOF] 	//don't change
`define i_sol i_s_axis_tuser[`SOL] 	//don't change
`define i_eol i_s_axis_tuser[`EOL] 	//don't change
`define i_eof i_s_axis_tuser[`EOF] 	//don't change
`define i_pixel_valid (i_s_axis_tvalid & o_s_axis_tready)					//don't change
																			//don't change										 
`define o_sof o_m_axis_tuser[`SOF]	//don't change
`define o_sol o_m_axis_tuser[`SOL]	//don't change
`define o_eol o_m_axis_tuser[`EOL]	//don't change
`define o_eof o_m_axis_tuser[`EOF]	//don't change
`define o_pixel_valid (o_m_axis_tvalid & i_m_axis_tready)					//don't change

`define  RGGB                    0 
`define  GRBG                    1 
`define  BGGR                    2 
`define  GBRG                    3