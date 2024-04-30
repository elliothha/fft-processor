
module visualizer(
    input			sys_clk,	// 100 MHz system clock received from the FPGA

	output[5:0]		JA,			// 6-bit data signal for the LED sent to the FPGA
	output[6:0]		JB			// 7-bit ctrl signal for the LED sent to the FPGA
);

	localparam MHz = 1000000;
	localparam SYSTEM_FREQ = 100*MHz;

    // ---- LED Matrix Testing ----------------------------------------------------------



	// ---- End -------------------------------------------------------------------------

endmodule