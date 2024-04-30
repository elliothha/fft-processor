
module regfile (
	clock,
	ctrl_writeEnable, ctrl_reset, ctrl_writeReg,
	ctrl_readRegA, ctrl_readRegB, data_writeReg,
	data_readRegA, data_readRegB,
	led_output
);

	input clock, ctrl_writeEnable, ctrl_reset;
	input [4:0] ctrl_writeReg, ctrl_readRegA, ctrl_readRegB;
	input [31:0] data_writeReg;

	output [31:0] data_readRegA, data_readRegB;
	output [15:0] led_output;

	/* ---- REGFILE HARDWARE IMPLEMENTATION ---------------------------------------------------- */

	wire [31:0] register_writeEnable;     // One-hot encoded based off of 5-bit ctrl_writeReg address
	wire [31:0] registers[31:0];          // Actual registers of the regfile

	assign register_writeEnable = (ctrl_writeEnable && ctrl_writeReg != 5'd0) << ctrl_writeReg;

	genvar i;
	generate
		for (i = 0; i < 32; i = i + 1) begin: regfile_creation
			register #(
        		.DATA_WIDTH(32)
    		) reg_i (
				.clk(clock),
				.clr(ctrl_reset),
				.en(register_writeEnable[i]),
				.data_in(data_writeReg),  // 32-bit input of a register = data_writeReg
				.data_out(registers[i])   // 32-bit output of a register = registers[i]
			);
		end
	endgenerate

	assign data_readRegA = registers[ctrl_readRegA];
	assign data_readRegB = registers[ctrl_readRegB];

	assign led_output = (ctrl_writeReg == 5'd31) ? data_writeReg[15:0] : 16'd0;

endmodule
