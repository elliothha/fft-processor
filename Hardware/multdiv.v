
module multdiv(
	data_operandA, data_operandB, 
	ctrl_MULT, ctrl_DIV, 
	clock, 
	data_result, data_exception, data_resultRDY
);

    // Inputs 
    input [31:0] data_operandA, data_operandB; // 32-bit multiplier, multiplicand SIGNED inputs
    input ctrl_MULT, ctrl_DIV, clock; // ctrls for mult, div, and clock
    
    // Outputs
    output [31:0] data_result; // 32-bit product_out output
    output data_exception, data_resultRDY; 

    // MULT DIV LOGIC

    wire stop_MULT, mult_exception, mult_ready;
	wire stop_DIV, div_exception, div_ready;
	wire [31:0] mult_result;
	wire [31:0] div_result;
	 
	assign stop_MULT = ctrl_DIV;
	assign stop_DIV = ctrl_MULT;
	
    multiplier mult(
        // Inputs
        .clk(clock),
        .ctrl_MULT(ctrl_MULT),
        .stop_MULT(stop_MULT),
        .data_operandA(data_operandA),
        .data_operandB(data_operandB),

        // Outputs
        .mult_result(mult_result),
        .mult_exception(mult_exception),
        .mult_ready(mult_ready)
    );

	divider div(
        // Inputs
        .clk(clock),
        .ctrl_DIV(ctrl_DIV),
        .stop_DIV(stop_DIV),
        .data_operandA(data_operandA),
        .data_operandB(data_operandB),

        // Outputs
        .div_result(div_result),
        .div_exception(div_exception),
        .div_ready(div_ready)
    );
	 
	assign data_resultRDY = mult_ready || div_ready;
	assign data_result = mult_ready ? mult_result : div_result;
	assign data_exception = mult_ready ? mult_exception : div_exception;

endmodule