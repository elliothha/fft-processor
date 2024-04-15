
module divider (
    // CONTROL SIGNALS
    clk,                   // I: 1-bit
    ctrl_DIV,                // I: 1-bit
    stop_DIV,                // I: 1-bit

    // DIVIDER I/O
    data_operandA,           // I: 32-bit dividend
    data_operandB,           // I: 32-bit divisor

    div_result,              // O: 32-bit quotient
    div_exception,           // O: 1-bit
    div_ready                // O: 1-bit
);

    // CONTROL SIGNALS
    input clk, ctrl_DIV, stop_DIV;

    // DIVIDER I/O
    input [31:0] data_operandA, data_operandB;

    output [31:0] div_result;
    output div_exception, div_ready;

    /* ---- RESTORING DIVISION ALGO IMPLEMENTATION --------------------------------------------- */

    // WIRES
    wire ongoing_DIV;
    wire [4:0] counter;
    wire [4:0] make_posA, make_posB;
    wire [31:0] pos_operandA, pos_operandB;
    wire [31:0] original_operandA, original_operandB, dividend, divisor; // latched for full operation

    wire is_DONE;
    wire [31:0] trial_A, restore_A;
    wire [31:0] upper_in, lower_in, upper_out, lower_out;
    wire [63:0] quotient_in, quotient_out;
    wire [63:0] shifted_quotient_reg_out;

    wire [4:0] make_posRes, make_negRes;
    wire [31:0] res, pos_result, neg_result;

    // INIT LOGIC
    register #(
        .DATA_WIDTH(1)
    ) is_ongoing (
        .clk(clk),
        .clr(stop_DIV),
        .en(ctrl_DIV || counter == 5'b11111),
        .data_in(ctrl_DIV),
        .data_out(ongoing_DIV)
    );

    register #(
        .DATA_WIDTH(1)
    ) is_finished (
        .clk(clk),
        .clr(stop_DIV),
        .en(1'b1),
        .data_in(counter == 5'b11111),
        .data_out(is_DONE)
    );

    register #(
        .DATA_WIDTH(32)
    ) store_original_operandA (
        .clk(clk),
        .clr(stop_DIV),
        .en(ctrl_DIV),
        .data_in(data_operandA),
        .data_out(original_operandA)
    );

    register #(  
        .DATA_WIDTH(32)
    ) store_original_operandB (
        .clk(clk),
        .clr(stop_DIV),
        .en(ctrl_DIV),
        .data_in(data_operandB),
        .data_out(original_operandB)
    );

    assign make_posA = (data_operandA[31] == 1'b1) ? 5'b00001 : 5'b00000; // if original signed data operands are negative, need to get twos comp
    assign make_posB = (data_operandB[31] == 1'b1) ? 5'b00001 : 5'b00000; 

    alu positive_operandA_ALU (
        .data_operandA(32'd0),
        .data_operandB(data_operandA),
        .ctrl_ALUopcode(make_posA),
        .data_result(pos_operandA)
    );

    alu positive_operandB_ALU (
        .data_operandA(32'd0),
        .data_operandB(data_operandB),
        .ctrl_ALUopcode(make_posB),
        .data_result(pos_operandB)
    );

    register #(
        .DATA_WIDTH(32)
    ) store_dividend (
        .clk(clk),
        .clr(stop_DIV),
        .en(ctrl_DIV),
        .data_in(pos_operandA),
        .data_out(dividend)
    );

    register #(
        .DATA_WIDTH(32)
    ) store_divisor (
        .clk(clk),
        .clr(stop_DIV),
        .en(ctrl_DIV),
        .data_in(pos_operandB),
        .data_out(divisor)
    );

    counter32_5 iter_counter (
        .clk(clk),
        .clr(stop_DIV || ctrl_DIV),
        .en(ongoing_DIV),
        .counter(counter)
    );

    /*
    LOGIC
    1.) Left shift AQ by 1                    
        [AQ << 1]   
        (shifted_quotient_reg_out = quotient_out << 1)
    2.) Trial subtraction with shifted values 
        [A = A - M] 
        (trial_A = upper_out - Divisor)
    3.) If MSB A is 1, restore A and LSB Q = 0, else don't restore and LSB Q = 1
    4.) Write to register
    */
    register #(
        .DATA_WIDTH(64) // 32-bit upper = remainder (A), 32-bit lower = quotient (Q)
    ) quotient_reg (
        .clk(clk),
        .clr(stop_DIV),
        .en(1'b1),
        .data_in(quotient_in),
        .data_out(quotient_out)
    );

    assign res = quotient_out[31:0]; // result quotient will directly use Q in register, i.e., unshifted
    assign shifted_quotient_reg_out = quotient_out << 1; // left shift AQ by 1
    assign upper_out = shifted_quotient_reg_out[63:32];  // A after the shift
    assign lower_out = shifted_quotient_reg_out[31:0];   // Q after the shift
    assign restore_A = upper_out; // restore_A = A after the shift

    alu trial_sub_ALU (
        .data_operandA(restore_A),
        .data_operandB(divisor),
        .ctrl_ALUopcode(5'b00001),
        .data_result(trial_A) // trial_A = restore_A - divisor [A = A - M]
    );

    assign upper_in = (trial_A[31] == 1'b1) ? restore_A : trial_A; // if MSB A == 1: use restore_A; else if MSB A == 0: use trial_A (don't restore)
    assign lower_in = (trial_A[31] == 1'b1) ? {lower_out[31:1], 1'b0} : {lower_out[31:1], 1'b1}; // if MSB A == 1: LSB Q = 0; else if MSB A == 0: LSB Q = 1 

    assign quotient_in = ctrl_DIV ? {32'd0, pos_operandA} : {upper_in, lower_in}; // init (store dividend) vs main algo loop

    /*
    OUTPUTS
    */
    
    // res already represents the twos-comp version of what's in the Q register after algo finishes, either pos or neg
    assign make_posRes = (res[31] == 1'b1) ? 5'b00001 : 5'b00000; // if res is neg, we subtract or get res's twos-comp; else, we add 0 or just use res
    assign make_negRes = (res[31] == 1'b0) ? 5'b00001 : 5'b00000; // if res is pos, we subtract or get res's twos-comp; else, we add 0 or just use res

    alu positive_result_ALU ( // if res is already pos, do nothing (add), if res is neg, subtract
        .data_operandA(32'd0),
        .data_operandB(res),
        .ctrl_ALUopcode(make_posRes),
        .data_result(pos_result) // pos_result = guaranteed positive twos-comp version of res
    );

    alu negative_result_ALU ( // if res is already neg, do nothing (add), if res is pos, subtract
        .data_operandA(32'd0),
        .data_operandB(res),
        .ctrl_ALUopcode(make_negRes),
        .data_result(neg_result)
    );

    // if the signs of the original dividend and remainder are the same, use pos_result, else use neg_result
    // if you need remainder in the future, it will have the same sign as the dividend
    assign div_result = (original_operandA[31] == original_operandB[31]) ? pos_result : neg_result;
    assign div_ready = is_DONE;
    assign div_exception = (divisor == 32'b0) ? 1'b1 : 1'b0;


endmodule