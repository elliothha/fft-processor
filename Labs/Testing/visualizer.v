
module visualizer(
    input			clk_100mhz,	// I : 100 MHz system clock received from the FPGA
	output[5:0]		JA,			// O : 6-bit data signal for the LED sent to the FPGA
	output[6:0]		JB			// O : 7-bit ctrl signal for the LED sent to the FPGA
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
		MAGN_COUNT = 32,
		MAGN_ADDR_WIDTH = $clog2(MAGN_COUNT),
		BITS_PER_MAGN = 4;

	// ---- WIRE SETUPS -----------------------------------------------------------------

	reg latch_oe = 0;
	reg [3:0] row_counter = 0;
	reg [5:0] col_head = 0;
	reg [4:0] col_counter = 5'd31;
	reg [7:0] tick_counter = 8'd255;

	wire [COLOR_ADDR_WIDTH-1:0] colorAddr;
	wire [BITS_PER_COLOR-1:0]	colorData;	// 24-bit color data, 24 -> [23:0]
	wire [BITS_PER_MAGN-1:0] 	magnData;	// 4-bit magnitude data for 16 heights!

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

	// ---- BRAM SETUPS -----------------------------------------------------------------

	ROM #(
		.DEPTH(COLOR_COUNT),
		.ADDRESS_WIDTH(COLOR_ADDR_WIDTH),
		.DATA_WIDTH(BITS_PER_COLOR),
		.MEMFILE({FILES_PATH, "colors.mem"})
	) ColorMem (
		.clk(clk_50mhz), 
		.addr(colorAddr), 
		.dataOut(colorData)	// posedge 100 MHz clk reads
	);

	ROM #(
		.DEPTH(MAGN_COUNT),
		.ADDRESS_WIDTH(MAGN_ADDR_WIDTH),
		.DATA_WIDTH(BITS_PER_MAGN),
		.MEMFILE({FILES_PATH, "magnitudes.mem"})
	) MagnitudesMem (
		.clk(clk_50mhz), 
		.addr(col_counter), 
		.dataOut(magnData)
	);

	// top half    = off if (15 - row counter > magnData), else (check tick)
	// bottom half = off if (row counter > magnData), else (check tick)

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
		(((4'd15 - row_counter) > magnData) ? (1'b0) : ((tick_counter > colorData[23:16]) ? 1'b0 : 1'b1)),	// JA[5] = R1
		(((4'd15 - row_counter) > magnData) ? (1'b0) : ((tick_counter > colorData[15:8]) ? 1'b0 : 1'b1)),	// JA[4] = G1
		(((4'd15 - row_counter) > magnData) ? (1'b0) : ((tick_counter > colorData[7:0]) ? 1'b0 : 1'b1)),	// JA[3] = B1
		((row_counter > magnData) ? (1'b0) : ((tick_counter > colorData[23:16]) ? 1'b0 : 1'b1)),			// JA[2] = R2
		((row_counter > magnData) ? (1'b0) : ((tick_counter > colorData[15:8]) ? 1'b0 : 1'b1)),				// JA[1] = G2
		((row_counter > magnData) ? (1'b0) : ((tick_counter > colorData[7:0]) ? 1'b0 : 1'b1))				// JA[0] = B2
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