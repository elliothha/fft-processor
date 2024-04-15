
module multiplier (
    // CONTROL SIGNALS
    clk,                   // I: 1-bit clk signal
    ctrl_MULT,               // I: 1-bit signal asserted for 1 cycle (negedge -> posedge) to start mult op
    stop_MULT,               // I: 1-bit signal asserted to clr everything

    // MULTIPLIER I/O
    data_operandA,           // I: 32-bit multiplicand
    data_operandB,           // I: 32-bit multiplier

    mult_result,             // O: 32-bit output
    mult_exception,          // O: 1-bit signal if multiplication overflow error
    mult_ready               // O: 1-bit signal if multiplication has fully finished
);

    // CONTROL SIGNALS
    input clk, ctrl_MULT, stop_MULT; 

    // MULTIPLIER I/O
    input [31:0] data_operandA, data_operandB;

    output [31:0] mult_result;
    output mult_exception, mult_ready;  

    /* ---- MODIFIED BOOTH'S ALGO IMPLEMENTATION ----------------------------------------------- */

    // WIRES
    wire ongoing_MULT, is_DONE, helper;
    wire [2:0] ctrl;
    wire [3:0] counter;
    wire [4:0] ALUopcode;
    wire [31:0] ALUInputA, ALUInputB, ALUOutput;
    wire [31:0] upper, lower;
    wire [31:0] multiplicand, multiplier;
    wire [64:0] product_in, product_out, concatenated, rsa_concat, rsa_same;


    // LOGIC
    register #(
        .DATA_WIDTH(1)
    ) is_ongoing (
        .clk(clk),
        .clr(stop_MULT),
        .en(ctrl_MULT || counter == 4'b1111),
        .data_in(ctrl_MULT),
        .data_out(ongoing_MULT)
    );

    register #(
        .DATA_WIDTH(1)
    ) is_finished (
        .clk(clk),
        .clr(stop_MULT),
        .en(1'b1),
        .data_in(counter == 4'b1111),
        .data_out(is_DONE)
    );

    register #(
        .DATA_WIDTH(32)
    ) store_operandA (
        .clk(clk),
        .clr(stop_MULT),
        .en(ctrl_MULT),
        .data_in(data_operandA),
        .data_out(multiplicand)
    );

    register #(
        .DATA_WIDTH(32)
    ) store_operandB (
        .clk(clk),
        .clr(stop_MULT),
        .en(ctrl_MULT),
        .data_in(data_operandB),
        .data_out(multiplier)
    );

    assign ALUInputB = (ctrl == 3'b011 || ctrl == 3'b100) ? (multiplicand << 1) : multiplicand; // shifts = 011, 100
    assign ALUInputA = product_out[64:33]; // upper 32 bits
    assign ALUopcode = (ctrl == 3'b001 || ctrl == 3'b010 || ctrl == 3'b011) ? 5'b00000 : 5'b00001; // adds = 001, 010, 011

    alu mult_alu(
        .data_operandA(ALUInputA), 
        .data_operandB(ALUInputB), 
        .ctrl_ALUopcode(ALUopcode),
        .data_result(ALUOutput)
        // Unused ports: ctrl_shftamt, isNotEqual, isLessThan, overflow
    );

    // nop = 000, 111
    assign concatenated = {ALUOutput, product_out[32:1], product_out[0]};
    assign rsa_concat = $signed(concatenated) >>> 2;
    assign rsa_same = $signed(product_out) >>> 2;
    assign product_in = ctrl_MULT ? {32'b0, data_operandB, 1'b0} : (
        (ctrl == 3'b000 || ctrl == 3'b111) ? rsa_same : rsa_concat
    );

    register #(
        .DATA_WIDTH(65) // 32-bit upper product, 32-bit lower product, 1-bit helper
    ) product_reg (
        .clk(clk),
        .clr(stop_MULT),
        .en(1'b1),
        .data_in(product_in),
        .data_out(product_out)
    );

    assign upper = product_out[64:33];
    assign lower = product_out[32:1];
    assign helper = product_out[0];
    assign ctrl = product_out[2:0];

    counter16_4 iter_counter (
        .clk(clk),
        .clr(stop_MULT || ctrl_MULT),
        .en(ongoing_MULT),
        .counter(counter)
    );

    assign mult_result = product_out[32:1];
    assign mult_ready = is_DONE;
    assign mult_exception = (
        (product_out[32] == 1'b0 && product_out[64:33] != 32'b0) || 
        (product_out[32] == 1'b1 && product_out[64:33] != 32'b11111111111111111111111111111111) ||
        (multiplicand[31] == 1'b1 && multiplier[31] == 1'b1 && mult_result[31] == 1'b1) // handles case where we need to negate max val multiplicand
    ) && mult_ready;




endmodule