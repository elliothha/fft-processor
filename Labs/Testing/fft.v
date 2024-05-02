
module fft(
    input       clk_100mhz,     //
	input		vauxp3,         //
    input		vauxn3,         //
	input       vp_in,          //
	input		vn_in,          //
    output[5:0] JA,             //
    output[6:0] JB              //
);

    localparam FILES_PATH = "C:/Users/Elliot/Desktop/Processor/Labs/Testing/";

	localparam 
		MHz = 1000000,
		SYSTEM_FREQ = 100*MHz;

	localparam
		COLOR_COUNT = 64,						// 64 circular color gradient
		COLOR_ADDR_WIDTH = $clog2(COLOR_COUNT),	// $clog2(64) = 6-bit addresses
		BITS_PER_COLOR = 24;					// 24-bit colors

    localparam
        SAMPLE_COUNT = 1024,                    // 1024 point FFT
        FIFO_ADDR_WIDTH = $clog2(SAMPLE_COUNT), // $clog(1024) = 10-bit addrs
        BITS_PER_SAMPLE = 16;                   // xadc gives us 16-bit samples, the 12 MSBs are relevant data

    // ---- CLOCK SETUPS ----------------------------------------------------------------

	wire clk_50mhz;	// drives processor
	wire clk_25mhz;	// drives LED matrix display
	wire locked;

	clk_wiz_0 pll_clkgen(		// PLL Clocking Wizard IP Core
		// Control signals
		.reset(1'b0),			// I : set to 0
		.locked(locked),		// O : asserts high when freq of pll is at 50 MHz (don't care)

		// Clock in ports
		.clk_in1(clk_100mhz),		// I : 100 MHz sys clk

		// Clock out ports
		.clk_out1(clk_50mhz),	// O : 50 MHz pll clk for driving processor
		.clk_out2(clk_25mhz)	// O : 25 MHz pll clk for driving LED display
	);

	reg clk_8hz = 0;
	reg [25:0] clk_8hz_counter = 0;   // 26-bit counter to hold values up to 50,000,000

	always @(posedge clk_100mhz) begin
		if (clk_8hz_counter == (SYSTEM_FREQ / (2 * 8)) - 1) begin
			clk_8hz <= ~clk_8hz;
			clk_8hz_counter <= 0;
		end else begin
			clk_8hz_counter <= clk_8hz_counter + 1;
		end
	end

    // ---- WIRE SETUPS -----------------------------------------------------------------

    // BRAMS
    wire S_FIFO_wEn;
    wire [9:0] S_FIFO_addr;
    wire [15:0] S_FIFO_dataIn, S_FIFO_dataOut;

    wire M_FIFO_wEn;
    wire [9:0] M_FIFO_addr;
    wire [31:0] M_FIFO_dataIn, M_FIFO_dataOut;

    wire MAG_wEn;
    wire [4:0] MAG_addr;
    wire [32:0] MAG_dataIn, MAG_dataOut; 

    // XADC
    wire xadc_rdy;
    wire [15:0] xadc_data;      // use 12 MSBs !!!

    wire eoc, eos, busy, alarm; // don't care
    wire [4:0] channel;         // don't care

    // XFFT
    wire s_axis_config_tvalid;
    wire s_axis_config_tready;
    wire [15:0] s_axis_config_tdata;

    wire s_axis_data_tvalid;
    wire s_axis_data_tready;
    wire s_axis_data_tlast;
    wire [31:0] s_axis_data_tdata;

    wire m_axis_data_tvalid;
    wire m_axis_data_tlast;
    wire [31:0] m_axis_data_tdata;
    wire [15:0] m_axis_data_tuser;

    wire event_frame_started;
    wire event_tlast_unexpected, event_tlast_missing;
    wire event_status_channel_halt, event_data_in_channel_halt, event_data_out_channel_halt;

    // VISUALIZATION
    reg latch_oe = 0;
	reg [3:0] row_counter = 0;
	reg [5:0] col_head = 0;
	reg [4:0] col_counter = 5'd31;
	reg [7:0] tick_counter = 8'd255;

	wire [COLOR_ADDR_WIDTH-1:0] colorAddr;
	wire [BITS_PER_COLOR-1:0]	colorData;	// 24-bit color data, 24 -> [23:0]

    // ---- BRAM SETUPS -----------------------------------------------------------------

    ROM #(
		.DEPTH(COLOR_COUNT),
		.ADDRESS_WIDTH(COLOR_ADDR_WIDTH),
		.DATA_WIDTH(BITS_PER_COLOR),
		.MEMFILE({FILES_PATH, "colors.mem"})
	) ColorMem (
		.clk(clk_50mhz), 
		.addr(colorAddr), 
		.dataOut(colorData)
	);

    RAM #(
        .DEPTH(SAMPLE_COUNT),               // SAMPLE_COUNT     = 1024 samples
        .ADDRESS_WIDTH(FIFO_ADDR_WIDTH),    // FIFO_ADDR_WIDTH  = 10-bit addresses to store the 1024 samples
        .DATA_WIDTH(BITS_PER_SAMPLE)        // BITS_PER_SAMPLE  = 16-bit signed twos-comp PCM data
    ) S_FIFO (
        .clk(clk_50mhz),    // read/write ops are on posedge of clk_50mhz (choose which one based on stable value of wEn at the posedge)
        .wEn(S_FIFO_wEn),
        .addr(S_FIFO_addr),
        .dataIn(S_FIFO_dataIn),
        .dataOut(S_FIFO_dataOut)
    );

    RAM #(
        .DEPTH(SAMPLE_COUNT),               // SAMPLE_COUNT     = 1024 samples
        .ADDRESS_WIDTH(FIFO_ADDR_WIDTH),    // FIFO_ADDR_WIDTH  = 10-bit addresses to store the 1024 samples
        .DATA_WIDTH(32)                     // 32, needs to hold both 16'bIM and 16'bRE output samples
    ) M_FIFO (
        .clk(clk_50mhz),    // read/write ops are on posedge of clk_50mhz (choose which one based on stable value of wEn at the posedge)
        .wEn(M_FIFO_wEn),
        .addr(M_FIFO_addr),
        .dataIn(M_FIFO_dataIn),
        .dataOut(M_FIFO_dataOut)
    );

    RAM #(
        .DEPTH(32),
        .ADDRESS_WIDTH(5),
        .DATA_WIDTH(33)
    ) MAG_MEM (
        .clk(clk_50mhz),
        .wEn(MAG_wEn),
        .addr(MAG_addr),
        .dataIn(MAG_dataIn),
        .dataOut(MAG_dataOut)
    ); 

    // top half    = off if (15 - row counter > magnData), else (check tick)
	// bottom half = off if (row counter > magnData), else (check tick)

    // ---- XADC SETUP ------------------------------------------------------------------

    xadc_wiz_0 sampler(
        // Control Signals
        .dclk_in(clk_50mhz),    // I : 1'b,     uses 50 MHz clk
        .eoc_out(eoc),          // O : 1'b,     X
        .eos_out(eos),          // O : 1'b,     X
        .busy_out(busy),        // O : 1'b,     X
        .alarm_out(alarm),      // O : 1'b,     X  

        // DRP in ports
        .den_in(1'b1),          // I : 1'b1,    DRP always enabled
        .daddr_in(8'h13),       // I : 7'b,     always reading from channel vaux3
        .di_in(16'b0),          // I : 16'b0,   never writing
        .dwe_in(1'b0),          // I : 1'b0,    never writing

        // DRP out ports
        .drdy_out(xadc_rdy),    // O : 1'b      sample ready flag
        .do_out(xadc_data),     // O : 16'b     actual PCM-mapped data sample

        // XADC in ports
        .vp_in(1'b1),           // I : 1'b,     X
        .vn_in(1'b1),           // I : 1'b,     X
        .vauxp3(vauxp3),        // I : 1'b,     input from FPGA pin A13
        .vauxn3(vauxn3),        // I : 1'b,     input from FPGA pin A14

        // XADC out ports
        .channel_out(channel)   // O : 5'b, X
    );

    // ---- XFFT SETUP ------------------------------------------------------------------

    xfft_0 transform(
        // Control Signals
        .aclk(clk_50mhz),

        // -- IN  PORTS --
        // S_AXIS_CONFIG
        .s_axis_config_tvalid(1'b1),                    // I : [1'b1]
        .s_axis_config_tready(s_axis_config_tready),    // O : [1'b ]
        
        .s_axis_config_tdata(s_axis_config_tdata),      // I : [16'b] = {5'b0 pad, 10'b10101010 SCALE_SCH, 1'b1 FWD}

        // S_AXIS_DATA
        .s_axis_data_tvalid(s_axis_data_tvalid),        // I : [1'b1]
        .s_axis_data_tready(s_axis_data_tready),        // O : [1'b ]

        .s_axis_data_tlast(s_axis_data_tlast),          // I : [1'b ]
        .s_axis_data_tdata(s_axis_data_tdata),          // I : [32'b]

        // -- OUT PORTS --
        // M_AXIS_DATA
        .m_axis_data_tvalid(m_axis_data_tvalid),        // O : [1'b ]
        .m_axis_data_tready(1'b1),                      // I : [1'b1]
        
        .m_axis_data_tlast(m_axis_data_tlast),          // O : [1'b ]
        .m_axis_data_tdata(m_axis_data_tdata),          // O : [32'b]

        .m_axis_data_tuser(m_axis_data_tuser),          // O : [16'b] = {6'b0 pad, 10'b unsigned XK_INDEX}

        // EVENT SIGNALS (don't care)
        .event_frame_started(event_frame_started),
        .event_tlast_unexpected(event_tlast_unexpected),
        .event_tlast_missing(event_tlast_missing),
        .event_status_channel_halt(event_status_channel_halt),
        .event_data_in_channel_halt(event_data_in_channel_halt),
        .event_data_out_channel_halt(event_data_out_channel_halt)
    );

    // ---- SAMPLE + TRANSFORM CODE -----------------------------------------------------

    // initialize s_axis_config_tdata vals (never change these vals)
    reg FWD_INV = 1'b1;
    reg [9:0] SCALE_SCH = 10'b10101010;

    assign s_axis_config_tdata = {5'b00000, SCALE_SCH, FWD_INV};

    // XFFT I/O regs and wires

    reg [10:0] S_DATA_TNUM = 11'd2047;      // logic ctrl   = changes on posedge (reset happens on negedge!)

    reg [9:0] S_FIFO_readPtr = 10'd0;       // S_FIFO param = changes on negedge  
    reg [9:0] S_FIFO_writePtr = 10'd1023;   // S_FIFO param = changes on negedge
    reg [15:0] SAMPLED_DATA_48KHZ = 16'd0;  // S_FIFO param = changes on negedge

    reg S_DATA_TVALID = 1'b0;               // XFFT param   = changes on negedge
    reg S_DATA_TLAST = 1'b0;                // XFFT param   = changes on negedge
    reg [31:0] S_DATA_TDATA = 32'd0;        // XFFT param   = changes on negedge

    reg M_DATA_TVALID = 1'b0;
    reg M_DATA_TLAST = 1'b0;
    reg [31:0] M_DATA_TDATA = 32'd0;
    reg [15:0] M_DATA_TUSER = 16'd0;

    // s_axis_data logic
    // since XFFT and mem are posedge triggered, need params to change on negedge so they're stable

    always @(posedge clk_50mhz) begin
        S_DATA_TNUM <= S_DATA_TNUM + 1;
        // on clk_50mhz posedges, we also either read/write to S_FIFO
        // on clk_50mhz posedges, we also make a transaction to XFFT
    end
    
    always @(negedge clk_50mhz) begin
        
        // S_DATA LOGIC
        S_DATA_TDATA <= {16'd0, S_FIFO_dataOut};
        if (S_DATA_TNUM == 11'd1023) begin
            S_DATA_TLAST <= 1'b1;
            S_FIFO_readPtr <= S_FIFO_writePtr;
            
            SAMPLED_DATA_48KHZ <= xadc_data;

            S_DATA_TNUM <= 11'd2046;    // assign to (11'dmax - 1) to "reset" transaction counter
        end else begin
            S_DATA_TLAST <= 1'b0;
            S_FIFO_readPtr <= S_FIFO_readPtr + 1;
            if (S_DATA_TNUM == 11'd2047) begin  
                S_DATA_TVALID <= 1'b0;
                S_FIFO_writePtr <= S_FIFO_writePtr + 1;
            end else begin
                S_DATA_TVALID <= 1'b1;
            end 
        end

        // M_DATA LOGIC
        M_DATA_TVALID <= m_axis_data_tvalid;
        M_DATA_TLAST <= m_axis_data_tlast;
        M_DATA_TDATA <= m_axis_data_tdata;
        M_DATA_TUSER <= m_axis_data_tuser;

    end

    assign S_FIFO_wEn = S_DATA_TLAST;
    assign S_FIFO_addr = (S_DATA_TLAST == 1'b1) ? S_FIFO_writePtr : S_FIFO_readPtr;
    assign S_FIFO_dataIn = {
        ~SAMPLED_DATA_48KHZ[15],
        ~SAMPLED_DATA_48KHZ[15],
        ~SAMPLED_DATA_48KHZ[15],
        ~SAMPLED_DATA_48KHZ[15],
        ~SAMPLED_DATA_48KHZ[15],
        SAMPLED_DATA_48KHZ[14:4]
    };    // storing the signed twos-comp PCM data into S_FIFO on writes

    assign s_axis_data_tvalid = S_DATA_TVALID;
    assign s_axis_data_tlast = S_DATA_TLAST;
    assign s_axis_data_tdata = S_DATA_TDATA;    // updated on posedges

    // M_DATA
    assign M_FIFO_wEn = M_DATA_TVALID;
    assign M_FIFO_addr = M_DATA_TUSER[9:0];
    assign M_FIFO_dataIn = M_DATA_TDATA;

    // ---- MAPPING ---------------------------------------------------------------------

    assign MAG_wEn = (
        (M_DATA_TVALID) && 
        (M_DATA_TUSER[9:0] < 10'd512) && 
        (M_DATA_TUSER[3:0] == 4'b0000)
    ) ? 1'b1 : 1'b0;

    assign MAG_addr = (MAG_wEn) ? (
        M_DATA_TUSER[8:4]
    ) : col_counter;
    
    assign MAG_dataIn = (MAG_wEn) ? (
        (
            $signed(M_DATA_TDATA[31:16]) * $signed(M_DATA_TDATA[31:16]) + 
            $signed(M_DATA_TDATA[15:0]) * $signed(M_DATA_TDATA[15:0])
        )
    ) : 33'd0;

    // ---- LED MATRIX TESTING ----------------------------------------------------------

	always @(posedge clk_25mhz) begin
		col_counter <= col_counter + 1;

		if (col_counter == 5'd31) begin
			latch_oe <= 1;	// biggest reason i can get away w this is bc ROM is on 50 MHz and also fucking gate delays xd
			tick_counter <= tick_counter + 1;

			if (tick_counter == 8'd255) begin
				row_counter <= row_counter + 1;
			end

		end else begin
			latch_oe <= 0;
		end

	end

	always @(posedge clk_8hz) begin
		col_head <= col_head + 1;
	end

	assign colorAddr = {1'b0, col_counter} + col_head;

	// ---- ASSIGN OUTPUTS --------------------------------------------------------------

	assign JA = {
		(((4'd15 - row_counter) > MAG_dataOut[32:29]) ? (1'b0) : ((tick_counter > colorData[23:16]) ? 1'b0 : 1'b1)),	// JA[5] = R1
		(((4'd15 - row_counter) > MAG_dataOut[32:29]) ? (1'b0) : ((tick_counter > colorData[15:8]) ? 1'b0 : 1'b1)),	// JA[4] = G1
		(((4'd15 - row_counter) > MAG_dataOut[32:29]) ? (1'b0) : ((tick_counter > colorData[7:0]) ? 1'b0 : 1'b1)),	    // JA[3] = B1
		((row_counter > MAG_dataOut[32:29]) ? (1'b0) : ((tick_counter > colorData[23:16]) ? 1'b0 : 1'b1)),			    // JA[2] = R2
		((row_counter > MAG_dataOut[32:29]) ? (1'b0) : ((tick_counter > colorData[15:8]) ? 1'b0 : 1'b1)),				// JA[1] = G2
		((row_counter > MAG_dataOut[32:29]) ? (1'b0) : ((tick_counter > colorData[7:0]) ? 1'b0 : 1'b1))				// JA[0] = B2
	};

	assign JB = {
		row_counter[0],		// JB[6] = A = row[0]
		row_counter[1],		// JB[5] = B = row[1]
		row_counter[2],		// JB[4] = C = row[2]
		row_counter[3],		// JB[3] = D = row[3]
		clk_25mhz,			// JB[2] = CLK
		latch_oe,			// JB[1] = LAT
		latch_oe			// JB[0] = OE
	};

    // ---- END CODE --------------------------------------------------------------------

endmodule