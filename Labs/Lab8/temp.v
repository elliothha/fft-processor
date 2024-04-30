module AudioController(
    input        clk, 		  // [used directly] FROM FPGA: E3 = System Clock Input 100 Mhz
	input		 vauxn3,
	input		 vauxp3,
	input		 vn_in,
	input		 vp_in,
	output[15:0] LED
);

	// CLOCKS

	// WIRES 

	reg [9:0] inputWritePtr_reg = 10'd1023;
	reg [9:0] inputReadPtr_reg = 10'd0;
	reg [11:0] inputDataIn_reg;
	wire [11:0] inputDataIn, inputDataOut;

	wire adc_ready;
	wire [15:0] adc_data;
	
	xadc_wiz_0 my_adc ( 
		// S_DRP INPUTS
		.daddr_in(8'h13), 		// I: read from 0x13 for channel vaux3
		.di_in(16'b0), 			// I: DRP input data = always 0, not writing
		.den_in(1), 			// I: enable DRP = always 1
		.dwe_in(0),				// I: write en DRP = always 0
		// S_DRP OUTPUTS
		.do_out(adc_data), 		// O: what we get from ADC, 16'b data
		.drdy_out(adc_ready),  	// O: ready flag

		// Vp_Vn
        .vp_in(1),				// I: 
		.vn_in(1),				// I: 

		// Vaux3
		.vauxn3(vauxn3),		// I: Input from FPGA pin A14
		.vauxp3(vauxp3),		// I: Input from FPGA pin A13
        
		// DCLK
		.dclk_in(clk)	// I: 
	);

	wire s_config_tready, s_config_tvalid;
	wire [15:0] s_config_tdata;

	wire s_data_tlast, s_data_tready, s_data_tvalid;
	wire [31:0] s_data_tdata;

	wire m_data_tlast, m_data_tvalid, m_data_tready;
	wire [23:0] m_data_tuser;
	wire [31:0] m_data_tdata;

	wire m_status_tready, m_status_tvalid;
	wire [7:0] m_status_tdata;

	wire event_frame_started;
	wire event_tlast_unexpected, event_tlast_missing, event_fft_overflow, event_status_channel_halt, event_data_in_channel_halt, event_data_out_channel_halt;
	
	assign m_status_tready = 1'b1;

	xfft_0 my_xfft (
		.aclk(clk),                                                // input wire aclk
		
		.s_axis_config_tdata(s_config_tdata),                  // input wire [15 : 0] s_axis_config_tdata
		.s_axis_config_tvalid(s_config_tvalid),                // input wire s_axis_config_tvalid
		.s_axis_config_tready(s_config_tready),                // output wire s_axis_config_tready
		
		.s_axis_data_tdata(s_data_tdata),                      // input wire [31 : 0] s_axis_data_tdata
		.s_axis_data_tvalid(s_data_tvalid),                    // input wire s_axis_data_tvalid
		.s_axis_data_tready(s_data_tready),                    // output wire s_axis_data_tready
		.s_axis_data_tlast(s_data_tlast),                      // input wire s_axis_data_tlast
		
		.m_axis_data_tdata(m_data_tdata),                      // output wire [31 : 0] m_axis_data_tdata
		.m_axis_data_tuser(m_data_tuser),                      // output wire [23 : 0] m_axis_data_tuser
		.m_axis_data_tvalid(m_data_tvalid),                    // output wire m_axis_data_tvalid
		.m_axis_data_tready(m_data_tready),                    // input wire m_axis_data_tready
		.m_axis_data_tlast(m_data_tlast),                      // output wire m_axis_data_tlast
		
		.m_axis_status_tdata(m_status_tdata),                  // output wire [7 : 0] m_axis_status_tdata
		.m_axis_status_tvalid(m_status_tvalid),                // output wire m_axis_status_tvalid
		.m_axis_status_tready(m_status_tready),                // input wire m_axis_status_tready
		
		.event_frame_started(event_frame_started),                  // output wire event_frame_started
		.event_tlast_unexpected(event_tlast_unexpected),            // output wire event_tlast_unexpected
		.event_tlast_missing(event_tlast_missing),                  // output wire event_tlast_missing
		.event_fft_overflow(event_fft_overflow),                    // output wire event_fft_overflow
		.event_status_channel_halt(event_status_channel_halt),      // output wire event_status_channel_halt
		.event_data_in_channel_halt(event_data_in_channel_halt),    // output wire event_data_in_channel_halt
		.event_data_out_channel_halt(event_data_out_channel_halt)  // output wire event_data_out_channel_halt
	);

	wire [15:0] output_data;

	FIFO #(
		.DATA_WIDTH(12),
		.ADDRESS_WIDTH(12),
		.DEPTH(4096),
		.MEMFILE("")
	) inputFIFO (
		.clk(s_data_tready), 
		.wEn(adc_ready), 
		.addr(inputWritePtr), 
		.dataIn(inputDataIn), 
		.dataOut(inputDataOut)
	);

	FIFO #(
		.DATA_WIDTH(16),
		.ADDRESS_WIDTH(12),
		.DEPTH(1024),
		.MEMFILE("")
	) outputFIFO (
		.clk(m_data_tvalid), 
		.wEn(1'b1), 
		.addr(m_data_tuser[9:0]), 
		.dataIn(m_data_tdata[15:0]), 
		.dataOut(output_data)
	);
    
	
	//


    
endmodule