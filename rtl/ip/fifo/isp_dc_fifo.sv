//isp_dc_fifo: dual clock FIFO, "ShowAhead" (data on RdData while not empty) or "Normal"; Reset is active-high.
//Company library module (with sub modules isp_FifoAddrCnt, isp_GrayCnt, isp_GrayDecode): copy this file as is, do not rewrite it.
`timescale 1ns/100ps
module isp_dc_fifo
# (
  	parameter     FIFO_MODE     = "Normal"            , //"Normal"; //"ShowAhead"
    parameter     DATA_WIDTH    = 8                   ,
    parameter     FIFO_DEPTH    = 512                 ,

    parameter     AW_C          = $clog2(FIFO_DEPTH)  ,
    parameter     DW_C          = DATA_WIDTH          ,
    parameter     DD_C          = 2**AW_C
  )
(
  //System Signal
  input                 Reset   , //System Reset
  //Write Signal
  input                 WrClk   , //(I)Wirte Clock
  input                 WrEn    , //(I)Write Enable
  output  [AW_C  :0]    WrDNum  , //(O)Write Data Number In Fifo
  output                WrFull  , //(O)Write Full
  input   [DW_C -1:0]   WrData  , //(I)Write Data
  //Read Signal
  input                 RdClk   , //(I)Read Clock
  input                 RdEn    , //(I)Read Enable
  output  [AW_C  :0]    RdDNum  , //(O)Radd Data Number In Fifo
  output                RdEmpty , //(O)Read FifoEmpty
  output                DataVal , //(O)Data Valid
  output  [DW_C-1 :0]   RdData    //(O)Read Data
);

//Define  Parameter
  /////////////////////////////////////////////////////////
  localparam    TCo_C       = 0  ;

  /////////////////////////////////////////////////////////

//111111111111111111111111111111111111111111111111111111111
//Synchronize the async reset to both clocks;
//release it only after both clock domains have seen the reset
//********************************************************/
  /////////////////////////////////////////////////////////
  reg   [1:0]         WrClkRstGen   = 2'h3;
  reg   [1:0]         RdClkRstGen   = 2'h3;

  always @( posedge   WrClk or posedge Reset)
  begin
    if (Reset)                WrClkRstGen  <= # TCo_C 2'h3 ;
    else if (&WrClkRstGen)    WrClkRstGen  <= # TCo_C 2'h2 ;
    else if (~&RdClkRstGen)   WrClkRstGen  <= # TCo_C WrClkRstGen - {1'h0,(|WrClkRstGen)} ;
  end
  always @( posedge   RdClk or posedge Reset)
  begin
    if (Reset)              RdClkRstGen  <= # TCo_C 2'h3  ;
    else if (&RdClkRstGen)  RdClkRstGen  <= # TCo_C 2'h2  ;
    else if (~&WrClkRstGen) RdClkRstGen  <= # TCo_C RdClkRstGen - {1'h0,(|RdClkRstGen)} ;
  end

  /////////////////////////////////////////////////////////
  reg     WrClkRst =  1'h1 ;
  reg     RdClkRst =  1'h1 ;

  always @( posedge   WrClk or posedge Reset)
  begin
    if (Reset)        WrClkRst  <= # TCo_C 1'h1 ;
    else              WrClkRst  <= # TCo_C |WrClkRstGen ;
  end
  always @( posedge   RdClk or posedge Reset)
  begin
    if (Reset)        RdClkRst  <= # TCo_C 1'h1 ;
    else              RdClkRst  <= # TCo_C |RdClkRstGen ;
  end

  /////////////////////////////////////////////////////////
//111111111111111111111111111111111111111111111111111111111

//222222222222222222222222222222222222222222222222222222222
//Write data into FifoBuff
//addresses in Gray code
//********************************************************/
  /////////////////////////////////////////////////////////
  wire                FifoWrEn    = WrEn & (~WrFull) ;
  wire  [AW_C :0]     WrNextAddr  ;
  wire  [AW_C :0]     FifoWrAddr  ;
  wire                FifoWrFull  ;

  isp_FifoAddrCnt     # ( .CounterWidth_C (AW_C))
  U1_WrAddrCnt
  (
    //System Signal
    .Reset          ( WrClkRst    ) , //System Reset
    .SysClk         ( WrClk       ) , //System Clock
    //Counter Signal
    .ClkEn          ( FifoWrEn    ) , //(I)Clock Enable
    .FifoFlag       ( FifoWrFull  ) , //(I)Fifo Flag
    .AddrCnt        ( WrNextAddr  ) , //(O)Next Address
    .Addess         ( FifoWrAddr  )   //(O)Address Output
  );

  /////////////////////////////////////////////////////////
  reg [DW_C-1:0]      FifoBuff [DD_C-1:0];

  always @( posedge   WrClk)
  begin
    if (WrEn & (~WrFull))
    begin
      FifoBuff[FifoWrAddr[AW_C-1:0]]  <= # TCo_C WrData;
    end
  end

  /////////////////////////////////////////////////////////

//222222222222222222222222222222222222222222222222222222222

//333333333333333333333333333333333333333333333333333333333
//Read data from FifoBuff
//addresses in Gray code
//********************************************************/
  /////////////////////////////////////////////////////////
  wire                FifoEmpty   ;
  wire                FifoRdEn    ;

  wire  [AW_C :0]     RdNextAddr  ;
  wire  [AW_C :0]     FifoRdAddr  ;

  isp_FifoAddrCnt     # ( .CounterWidth_C (AW_C))
  U2_RdAddrCnt
  (
    //System Signal
    .Reset          ( RdClkRst    ) , //System Reset
    .SysClk         ( RdClk       ) , //System Clock
    //Counter Signal
    .ClkEn          ( FifoRdEn    ) , //(I)Clock Enable
    .FifoFlag       ( FifoEmpty   ) , //(I)Fifo Flag
    .AddrCnt        ( RdNextAddr  ) , //(O)Next Address
    .Addess         ( FifoRdAddr  )   //(O)Address Output
  );

  /////////////////////////////////////////////////////////
  reg   [DW_C-1 :0]   FifoRdData  ;

  always @( posedge   RdClk)
  begin
    if (FifoRdEn)     FifoRdData  <= # TCo_C FifoBuff[FifoRdAddr[AW_C-1:0]];
  end

  /////////////////////////////////////////////////////////
  assign RdData   =   FifoRdData  ; //(O)Read Data

  /////////////////////////////////////////////////////////
//333333333333333333333333333333333333333333333333333333333

//444444444444444444444444444444444444444444444444444444444
//Read / write address difference in the write clock domain
//********************************************************/
  /////////////////////////////////////////////////////////
  //move the read address into the write clock domain (WrClk)
  reg   [AW_C:0]      RdAddrOut   = {AW_C+1{1'h0}};
  reg   [AW_C:0]      WrRdAddr    = {AW_C+1{1'h0}};

  always @( posedge   WrClk)
  begin
    if (WrClkRst)     WrRdAddr <= # TCo_C {AW_C+1{1'h0}}     ;
    else              WrRdAddr <= # TCo_C RdAddrOut [AW_C:0] ;
  end

  /////////////////////////////////////////////////////////
  //convert the Gray coded read / write addresses to binary
  wire  [AW_C-1:0]    WrRdAHex  ;
  wire  [AW_C-1:0]    WrWrAHex  ;

  isp_GrayDecode #(AW_C)  WRAGray2Hex (WrRdAddr   [AW_C-1:0] , WrRdAHex[AW_C-1:0])  ;
  isp_GrayDecode #(AW_C)  WWAGray2Hex (FifoWrAddr [AW_C-1:0] , WrWrAHex[AW_C-1:0])  ;

  /////////////////////////////////////////////////////////
  //address difference in the write clock domain
  reg   [AW_C:0]    WrAddrDiff  = {AW_C+1{1'h0}}  ;

  wire  [AW_C:0]    Calc_WrAddrDiff =  ( {FifoWrAddr[AW_C]  , WrWrAHex  }
                                    +  { {AW_C{1'h0}}       , FifoWrEn  } ) ;
  always @( posedge   WrClk)
  begin
    if (WrClkRst)       WrAddrDiff  <= # TCo_C  {AW_C+1{1'h0}}      ;
    else                WrAddrDiff  <= # TCo_C  Calc_WrAddrDiff
                                    - {WrRdAddr  [AW_C] , WrRdAHex} ;
  end

  /////////////////////////////////////////////////////////
  assign  WrDNum  =   WrAddrDiff;  //(O)Data Number In Fifo

  /////////////////////////////////////////////////////////
//444444444444444444444444444444444444444444444444444444444

//555555555555555555555555555555555555555555555555555555555
//WrFull
//********************************************************/
  /////////////////////////////////////////////////////////
  //WrFull clear (WrFullClr)
  //generated when FifoRdAddr changes
  reg   [AW_C:0]      WrRdAddrReg = {AW_C+1{1'h0}};
  reg                 WrFullClr   = 1'h0;

  always @( posedge   WrClk)
  begin
    if (  WrClkRst)   WrRdAddrReg <= # TCo_C {AW_C+1{1'h0}}     ;
    else              WrRdAddrReg <= # TCo_C WrRdAddr[AW_C : 0] ;
  end
  always @( posedge   WrClk)
  begin
    if (  WrClkRst)   WrFullClr   <= # TCo_C 1'h0         ;
    else              WrFullClr   <= # TCo_C (WrRdAddr[AW_C-1:0] != WrRdAddrReg[AW_C-1:0]);
  end

  /////////////////////////////////////////////////////////
  //full flag
  reg   RdAHighNext   = 1'h0;

  wire  RdAHighRise   = (~WrRdAddrReg[AW_C-1]) &  WrRdAddr[AW_C-1];

  always @( posedge   WrClk)
  begin
    if (WrClkRst  )         RdAHighNext <= # TCo_C 1'h0 ;
    else if (RdAHighRise)   RdAHighNext <= # TCo_C (~WrRdAddr[AW_C])  ;
  end

  wire  FullCalc = (WrNextAddr[AW_C-1:0] ==  WrRdAddr[AW_C-1:0])
                && (WrNextAddr[AW_C    ] != (WrRdAddr[AW_C-1] ? WrRdAddrReg[AW_C] : RdAHighNext) );

///////////////////////////////////////////////////
  reg   FullFlag        = 1'h0;

  always @( posedge     WrClk)
  begin
    if (WrClkRst)       FullFlag  <= # TCo_C 1'h0;
    else if (FullFlag)  FullFlag  <= # TCo_C (~WrFullClr);
    else if (FifoWrEn)  FullFlag  <= # TCo_C FullCalc;
  end

  assign FifoWrFull     = FullFlag;

///////////////////////////////////////////////////
  assign  WrFull        = WrClkRst ? 1'b1 : FifoWrFull  ; //(I)Write Full

///////////////////////////////////////////////////


//555555555555555555555555555555555555555555555555555555555

//666666666666666666666666666666666666666666666666666666666
//Read / write address difference in the read clock domain
//********************************************************/
  /////////////////////////////////////////////////////////
  //move the write address (FifoWrAddr) into the read clock domain
  reg   [AW_C :0]     RdWrAddr  = {AW_C+1{1'h0}};

  always @( posedge   RdClk)
  begin
    if (RdClkRst )    RdWrAddr  <= # TCo_C {AW_C+1{1'h0}}       ;
    else              RdWrAddr  <= # TCo_C FifoWrAddr [AW_C:0]  ;
  end

  /////////////////////////////////////////////////////////
  //read address used for WrDNum and RdDNum, depends on FIFO_MODE
  wire  ReadEn  = (RdEn & (~RdEmpty)) ;

  generate
    if (FIFO_MODE == "ShowAhead")
    begin
      always @( posedge   RdClk)
      begin
        if (RdClkRst )    RdAddrOut <= # TCo_C {AW_C+1{1'h0}}       ;
        else if (ReadEn)  RdAddrOut <= # TCo_C FifoRdAddr [AW_C:0]  ;
      end
    end
    else
    begin
      always @( * )   RdAddrOut = # TCo_C FifoRdAddr [AW_C:0]  ;
    end
  endgenerate

  /////////////////////////////////////////////////////////
  wire  [AW_C-1:0]    RdWrAHex;
  wire  [AW_C-1:0]    RdRdAHex;

  isp_GrayDecode # (AW_C) RWAGray2Hex (RdWrAddr   [AW_C-1:0] , RdWrAHex[AW_C-1:0] );
  isp_GrayDecode # (AW_C) RRAGray2Hex (RdAddrOut  [AW_C-1:0] , RdRdAHex[AW_C-1:0] );

  /////////////////////////////////////////////////////////
  //address difference in the read clock domain
  reg   [AW_C:0]      RdAddrDiff  = {AW_C+1{1'h0}} ;

  wire  [AW_C:0]      Calc_RdAddrDiff = ( {RdAddrOut[AW_C] , RdRdAHex }
                                      + { {AW_C{1'h0}}     , ReadEn   } ) ;
  always @( posedge   RdClk)
  begin
    if (RdClkRst)     RdAddrDiff <= # TCo_C {AW_C+1{1'h0}}    ;
    else              RdAddrDiff <= # TCo_C {RdWrAddr[AW_C]   , RdWrAHex }
                                          - Calc_RdAddrDiff   ;
  end

  /////////////////////////////////////////////////////////
  assign  RdDNum    = RdAddrDiff[AW_C] & (|RdAddrDiff[AW_C-1:0]) ? RdAddrDiff[AW_C-1:0] : RdAddrDiff;   //(O)Data Number In Fifo

  /////////////////////////////////////////////////////////


//666666666666666666666666666666666666666666666666666666666

//777777777777777777777777777777777777777777777777777777777
//RdEmpty
//********************************************************/
  /////////////////////////////////////////////////////////
  //RdEmpty clear
  reg   [AW_C:0]      RdWrAddrReg = {AW_C+1{1'h0}};
  reg                 EmptyClr    = 1'h0;

  always @( posedge   RdClk)
  begin
    if (RdClkRst)     RdWrAddrReg <= # TCo_C {AW_C+1{1'h0}}     ;
    else              RdWrAddrReg <= # TCo_C RdWrAddr [AW_C:0]  ;
  end
  always @( posedge   RdClk)
  begin
    if (RdClkRst)     EmptyClr    <= # TCo_C 1'h0;
    else              EmptyClr    <= # TCo_C (RdWrAddr[AW_C-1:0] != RdWrAddrReg[AW_C-1:0])  ;
  end

  reg   EmptyClrReg   = 1'h0;

  always @( posedge     RdClk )   EmptyClrReg   <= EmptyClr ;

  /////////////////////////////////////////////////////////
  //empty flag (EmptyCalc)
  reg   WrAHighNext   = 1'h0;

  wire  WrAHighRise   = (~RdWrAddrReg[AW_C-1]) &  RdWrAddr[AW_C-1];

  always @( posedge   RdClk)
  begin
    if (RdClkRst)           WrAHighNext   <= # TCo_C  1'h0 ;
    else if (WrAHighRise)   WrAHighNext   <= # TCo_C (~RdWrAddr[AW_C]);
  end

  wire  EmptyCalc   = (RdNextAddr[AW_C-1:0] == RdWrAddr[AW_C-1:0])
                   && (RdNextAddr[AW_C    ] == (RdWrAddr[AW_C-1] ? RdWrAddrReg[AW_C] : WrAHighNext));

  /////////////////////////////////////////////////////////
  reg     EmptyFlag     = 1'h1;

  always @( posedge     RdClk)
  begin
    if (RdClkRst)       EmptyFlag   <= # TCo_C  1'h1  ;
    else if (EmptyFlag) EmptyFlag   <= # TCo_C ~EmptyClr;
    else if (FifoRdEn)  EmptyFlag   <= # TCo_C  EmptyCalc;
  end

  assign FifoEmpty    = EmptyFlag;

  /////////////////////////////////////////////////////////
  reg   EmptyReg      = 1'h0;

  always @( posedge     RdClk )
  begin
    if (RdClkRst)       EmptyReg  <= # TCo_C 1'h1;
    else if (FifoRdEn)      EmptyReg  <= # TCo_C FifoEmpty;
  end

  /////////////////////////////////////////////////////////
  assign RdEmpty = (FIFO_MODE == "ShowAhead") ? EmptyReg : FifoEmpty; //(O)Read FifoEmpty

  /////////////////////////////////////////////////////////
//777777777777777777777777777777777777777777777777777777777

//888888888888888888888888888888888888888888888888888888888
//
//********************************************************/
  /////////////////////////////////////////////////////////
  reg   RdFirst     = 1'h0;

  always @( posedge   RdClk)
  begin
    if (FIFO_MODE == "ShowAhead")
    begin
      if (RdClkRst)       RdFirst <= # TCo_C 1'h0     ;
    	else if (RdFirst)	  RdFirst <= # TCo_C 1'h0     ;
    	else if (EmptyClr)	RdFirst <= # TCo_C RdEmpty  ;
    	else if (EmptyReg ^ EmptyFlag)	RdFirst <= # TCo_C RdEmpty  ;
    end
    else                  RdFirst <= # TCo_C 1'h0     ;
  end

  /////////////////////////////////////////////////////////
  reg   ReadEn_Reg  = 1'h0 ;

  always @( posedge   RdClk)    ReadEn_Reg  <= ReadEn ;

  wire  Data_Valid  = (FIFO_MODE == "ShowAhead") ? ReadEn : ReadEn_Reg ;

  /////////////////////////////////////////////////////////
  assign  FifoRdEn  =   ReadEn ||  RdFirst ;
  assign  DataVal   =   Data_Valid  ; //(O)Data Valid

  /////////////////////////////////////////////////////////
//888888888888888888888888888888888888888888888888888888888

endmodule

module isp_FifoAddrCnt
# (
    parameter CounterWidth_C  = 9   ,
    parameter CW_C            = CounterWidth_C
  )
(
  //System Signal
  input             Reset     , //System Reset
  input             SysClk    , //System Clock
  //Counter Signal
  input             ClkEn     , //(I)Clock Enable
  input             FifoFlag  , //(I)Fifo Flag
  output  [CW_C:0]  AddrCnt   , //(O)Address Counter
  output  [CW_C:0]  Addess      //(O)Address Output
);

//Define  Parameter
  /////////////////////////////////////////////////////////
localparam    TCo_C       = 1;

//111111111111111111111111111111111111111111111111111111111
//
//	Input:
//	output:
//********************************************************/

  /////////////////////////////////////////////////////////
  wire [CW_C-1:0]   GrayAddrCnt;
  wire              CarryOut;

  isp_GrayCnt #(.CounterWidth_C (CW_C))
  U1_AddrCnt
  (
    //System Signal
    .Reset    ( Reset       ),  //System Reset
    .SysClk   ( SysClk      ),  //System Clock
    //Counter Signal
    .SyncClr  ( 1'h0        ),  //(I)Sync Clear
    .ClkEn    ( ClkEn       ),  //(I)Clock Enable
    .CarryIn  ( ~FifoFlag   ),  //(I)Carry input
    .CarryOut ( CarryOut    ),  //(O)Carry output
    .Count    ( GrayAddrCnt )   //(O)Counter Value Output
  );

  /////////////////////////////////////////////////////////
  reg   CntHighBit;

  always @( posedge SysClk )
  begin
    if (Reset)      CntHighBit <= # TCo_C 1'h0;
    else if (ClkEn) CntHighBit <= # TCo_C CntHighBit + CarryOut;
  end

  /////////////////////////////////////////////////////////
  reg  [CW_C:0]  AddrOut;    //(O)Address Output

  always @(posedge SysClk)
  begin
    if (Reset)        AddrOut <= # TCo_C {CW_C{1'h0}};
    else if (ClkEn)   AddrOut <= # TCo_C FifoFlag ? AddrOut : AddrCnt;
  end

  /////////////////////////////////////////////////////////
  assign  AddrCnt  = {CntHighBit , GrayAddrCnt} ; //(O)Next Address
  assign  Addess   =  AddrOut                   ; //(O)Address Output

//111111111111111111111111111111111111111111111111111111111

endmodule

/////////////////// isp_FifoAddrCnt //////////////////////////

module isp_GrayCnt
# (
    parameter   CounterWidth_C    = 9   ,
    parameter   CW_C              = CounterWidth_C
  )
(
  //System Signal
  input                 Reset     , //System Reset
  input                 SysClk    , //System Clock
  //Counter Signal
  input                 SyncClr   , //(I)Sync Clear
  input                 ClkEn     , //(I)Clock Enable
  input                 CarryIn   , //(I)Carry input
  output                CarryOut  , //(O)Carry output
  output  [CW_C-1:0]    Count       //(O)Counter Value Output
);

//Define  Parameter
  /////////////////////////////////////////////////////////
localparam    TCo_C       = 1;

//111111111111111111111111111111111111111111111111111111111
//
//	Input:
//	output:
//********************************************************/

  /////////////////////////////////////////////////////////
  wire  [CW_C:0  ]  CryIn  ;
  wire  [CW_C-1:0]  CryOut ;

  reg   [CW_C-1:0]  isp_GrayCnt;

  assign CryIn[0] = CarryIn;

  genvar i;
  generate
    for(i=0;i<CW_C;i=i+1)
    begin : GrayCnt_CrayCntUnit
      //////////////
      always @( posedge SysClk )
      begin
        if (Reset)        isp_GrayCnt[i]  <= # TCo_C (i>1) ? 1'h0: 1'h1  ;
        else if (SyncClr) isp_GrayCnt[i]  <= # TCo_C (i>1) ? 1'h0: 1'h1  ;
        else if (ClkEn)   isp_GrayCnt[i]  <= # TCo_C isp_GrayCnt[i] + CryIn[i];
      end

      //////////////
      if (i==0)
      begin
        assign CryOut[0]  =  isp_GrayCnt[0] && CarryIn;
        assign CryIn [1]  = ~isp_GrayCnt[0] && CarryIn;
      end
      else
      begin
        assign CryOut[i  ]  =  CryOut[  0] && (~|isp_GrayCnt[i:1]);
        assign CryIn [i+1]  =  CryOut[i-1] &&    isp_GrayCnt[i  ] ;
      end
    end

  endgenerate

  wire GrayCarry = CryOut[CW_C-2];

  /////////////////////////////////////////////////////////
  reg  CntHigh = 1'h0;

  always @( posedge SysClk)
  begin
    if (Reset)      CntHigh   <= # TCo_C 1'h0;
    else if (ClkEn) CntHigh   <= # TCo_C (CntHigh + GrayCarry);
  end

  /////////////////////////////////////////////////////////
  assign Count    = {CntHigh  , isp_GrayCnt[CW_C-1:1]}  ; //(O)Counter Value Output
  assign CarryOut =  CntHigh  & GrayCarry           ; //(O)Carry output

  /////////////////////////////////////////////////////////

//111111111111111111111111111111111111111111111111111111111

endmodule

////////////////////// isp_GrayCnt ////////////////////////////

module isp_GrayDecode
# (
    parameter DataWidht_C = 8
  )
(
  input   [DataWidht_C-1:0]  GrayIn,
  output  [DataWidht_C-1:0]  HexOut
);

 	//Define  Parameter
  /////////////////////////////////////////////////////////
	parameter		TCo_C   		= 1;

	localparam DW_C = DataWidht_C;

  /////////////////////////////////////////////////////////
  reg [DW_C-1:0] Hex;

  integer i;

  always @ (GrayIn)
  begin
    Hex[DW_C-1]=GrayIn[DW_C-1];
    for(i=DW_C-2;i>=0;i=i-1)   Hex[i]=Hex[i+1]^GrayIn[i];
  end

  assign HexOut = Hex;

  /////////////////////////////////////////////////////////

endmodule
