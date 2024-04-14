/**
 * READ THIS DESCRIPTION!
 *
 * This is your processor module that will contain the bulk of your code submission. You are to implement
 * a 5-stage pipelined processor in this module, accounting for hazards and implementing bypasses as
 * necessary.
 *
 * Ultimately, your processor will be tested by a master skeleton, so the
 * testbench can see which controls signal you active when. Therefore, there needs to be a way to
 * "inject" imem, dmem, and regfile interfaces from some external controller module. The skeleton
 * file, Wrapper.v, acts as a small wrapper around your processor for this purpose. Refer to Wrapper.v
 * for more details.
 *
 * As a result, this module will NOT contain the RegFile nor the memory modules. Study the inputs 
 * very carefully - the RegFile-related I/Os are merely signals to be sent to the RegFile instantiated
 * in your Wrapper module. This is the same for your memory elements. 
 *
 *
 */
module processor(
    // Control signals
    clock,                          // I: The master clock
    reset,                          // I: A reset signal

    // Imem
    address_imem,                   // O: The address of the data to get from imem
    q_imem,                         // I: The data from imem

    // Dmem
    address_dmem,                   // O: The address of the data to get or put from/to dmem
    data,                           // O: The data to write to dmem
    wren,                           // O: Write enable for dmem
    q_dmem,                         // I: The data from dmem

    // Regfile
    ctrl_writeEnable,               // O: Write enable for RegFile
    ctrl_writeReg,                  // O: Register to write to in RegFile
    ctrl_readRegA,                  // O: Register to read from port A of RegFile
    ctrl_readRegB,                  // O: Register to read from port B of RegFile
    data_writeReg,                  // O: Data to write to for RegFile
    data_readRegA,                  // I: Data from port A of RegFile
    data_readRegB                   // I: Data from port B of RegFile
	 
	);

	// CONTROL SIGNALS
	input clock, reset;
	
	// IMEM (ROM)
    output [31:0] address_imem; // O: PC addr of current insn (only using least 12 bits!)
	input [31:0] q_imem;        // I: 32-bit ISA-encoded insn

	// DMEM (RAM)
	output [31:0] address_dmem, data;
	output wren;
	input [31:0] q_dmem;

	// REGFILE 
	output ctrl_writeEnable;
	output [4:0] ctrl_writeReg, ctrl_readRegA, ctrl_readRegB;
	output [31:0] data_writeReg;
	input [31:0] data_readRegA, data_readRegB;

    /*  -------------------------------------------------------------------
     *  --- WIRES                                                       ---
     *  -------------------------------------------------------------------  */
    
    /*  --- FETCH STAGE ---------------------------------------------------  */
    //  I/O wires for PC reg
    //  [31:0] = word-addressed PC addr = IMEM insn addrs (program exec init @ 32'd0)
    wire [31:0] PC_data_in;  // [31:0] = incoming next PC addr
    wire [31:0] PC_data_out; // [31:0] = outgoing current PC addr, aka current insn addr

    //  Control hazard wires
    wire [31:0] seq_PC;     // seq_PC = PC_data_out + 1

    //  FETCH STAGE output wires
    wire [31:0] PC_insn;    // 32-bit ISA-encoded insn; PC_insn == q_imem
    wire [63:0] FD_data_in; // {seq_PC, PC_insn}

    /*  --- DECODE STAGE --------------------------------------------------  */
    //  F/D reg read values
    //  [63:32] = F/D.PC; the "next" PC relative to current IR's PC
    //  [31:0]  = F/D.IR; the "current" PC's actual insn
    wire [63:0] FD_data_out;
    wire [31:0] FD_PC, FD_IR;

    // Regfile wires
    wire [31:0] FD_RS1VAL;
    wire [31:0] FD_RS2VAL;

    // DECODE STAGE output wires
    wire [95:0] DX_data_in;

    /*  --- EXECUTE STAGE -------------------------------------------------  */
    //  D/X reg read values
    //  [95:64] = D/X.RS1VAL
    //  [63:32] = D/X.RS2VAL
    //  [31:0]  = D/X.IR
    wire [95:0] DX_data_out;
    wire [31:0] DX_RS1VAL, DX_RS2VAL, DX_IR;

    //  ALU Logic
    wire [31:0] I_type_constant;

    wire [4:0] DX_ALU_opcode, DX_ALU_shamt;
    wire [31:0] DX_ALU_operandB;
    wire [31:0] DX_ALU_output;

    //  EXECUTE STAGE output wires
    wire [95:0] XM_data_in;

    /*  --- MEMORY STAGE --------------------------------------------------  */
    //  X/M reg read values
    //  [95:64] = X/M.ALUVAL; R-type = $rs + $rt, I-type = $rs + N, 
    //  [63:32] = X/M.RDVAL; only used for sw, this is $rd val
    //  [31:0]  = X/M.IR
    wire [95:0] XM_data_out;
    wire [31:0] XM_ALUVAL, XM_RDVAL, XM_IR;

    //  DMEM Logic
    wire [31:0] XM_lw_data;

    // MEMORY STAGE output wires
    wire [95:0] MW_data_in;

    /*  --- WRITEBACK STAGE -----------------------------------------------  */
    //  M/W reg read values
    //  [95:64]  = M/W.ALUVAL; R-type = $rs + $rt, I-type = $rs + N, 
    //  [63:32]  = M/W.RDVAL; only used if lw, this is $rd val read from DMEM
    //  [31:0]   = M/W.IR
    wire [95:0] MW_data_out;
    wire [31:0] MW_ALUVAL, MW_RDVAL, MW_IR;

	/*  -------------------------------------------------------------------
     *  --- DLX PROCESSOR IMPLEMENTATION                                ---
     *  -------------------------------------------------------------------  */

    /*  --- FETCH STAGE ---------------------------------------------------  */
    //  --- PC Reg = {PC}
    pipeline_reg #(
        .DATA_WIDTH(32)
    ) PC_reg (  
        .clk(clock),
        .en(1'b1), // [TODO]: maybe change later for disable PC reg?
        .clr(reset),
        .data_in(PC_data_in),
        .data_out(PC_data_out)
    );

    //  --- Control Hazard Logic
    alu incr_PC_ALU( // Purpose: adds 1 to current PC addr to get next sequential insn
        .data_operandA(32'd1), 
        .data_operandB(PC_data_out),
        .ctrl_ALUopcode(5'd0), 
        .data_result(seq_PC)
        // Unused Input Ports: ctrl_shiftamt
        // Unused Output Ports: isNotEqual, isLessThan, overflow
    );

    assign PC_data_in = seq_PC; // [TODO]: change this for branch logic!!!
    
    //  --- IMEM Logic
    assign address_imem = PC_data_out;
    assign PC_insn = q_imem;

    //  --- FETCH STAGE Output Logic
    assign FD_data_in = {seq_PC, PC_insn};

    /*  --- DECODE STAGE --------------------------------------------------  */
    //  --- F/D Reg = {[63:32] F/D.PC, [31:0] F/D.IR}
    pipeline_reg #(
        .DATA_WIDTH(64)
    ) FD_reg (  
        .clk(clock),
        .en(1'b1),
        .clr(reset),
        .data_in(FD_data_in),
        .data_out(FD_data_out)
    );

    assign FD_PC = FD_data_out[63:32];
    assign FD_IR = FD_data_out[31:0];

    //  --- Regfile Read/Write Logic
    //  output ctrl_writeEnable;
	//  output [4:0] ctrl_writeReg, ctrl_readRegA, ctrl_readRegB;
	//  output [31:0] data_writeReg;
	//  input [31:0] data_readRegA, data_readRegB;
    assign ctrl_readRegA = FD_IR[21:17];  //  THIS IS $rs addr
    assign ctrl_readRegB = (FD_IR[31:27] == 5'd0) ? FD_IR[16:12] : FD_IR[26:22]; // $rt addr if R-type, $rd addr if NOT R-type
	// ctrl_writeEnable, ctrl_writeReg, data_writeReg handled in writeback stage

	assign FD_RS1VAL = data_readRegA;     //  THIS IS $rs val
    assign FD_RS2VAL = data_readRegB;     //  THIS IS $rt val if R-type, $rd val if not

    //  --- DECODE STAGE Output Logic
    assign DX_data_in = {FD_RS1VAL, FD_RS2VAL, FD_IR};

    /*  --- EXECUTE STAGE -------------------------------------------------  */
    //  --- D/X Reg = {[95:64] D/X.RS1VAL, [63:32] D/X.RS2VAL, [31:0] D/X.IR}
    pipeline_reg #(
        .DATA_WIDTH(96)
    ) DX_reg (  
        .clk(clock),
        .en(1'b1),
        .clr(reset),
        .data_in(DX_data_in),
        .data_out(DX_data_out)
    );

    assign DX_RS1VAL = DX_data_out[95:64]; // always the $rs val
    assign DX_RS2VAL = DX_data_out[63:32]; // if (R) -> $rt val; if (not R) -> $rd val
    assign DX_IR = DX_data_out[31:0];

    //  --- ALU Logic
    assign I_type_constant = {{15{DX_IR[16]}}, DX_IR[16:0]}; // 32-b sign-extended N
    assign DX_ALU_shamt = DX_IR[11:7]; // only used if the insn is a shift insn
    assign DX_ALU_opcode = (DX_IR[31:27] == 5'd0) ? DX_IR[6:2] : 5'd0; // if (R) -> DX.IR.ALUop; if (not R) -> always add
    assign DX_ALU_operandB = (DX_IR[31:27] == 5'd0) ? DX_RS2VAL : I_type_constant; // if (R) -> use DX_RS2VAL == $rt; if (not R) -> use N

    alu DX_ALU(
        .data_operandA(DX_RS1VAL),        // always $rs val
        .data_operandB(DX_ALU_operandB),  // if (R) -> DX_RS2VAL == $rt; if (not R) -> I_type_constant = N
        .ctrl_ALUopcode(DX_ALU_opcode),   // if (R) -> ALUop; if (not R) -> add
        .ctrl_shiftamt(DX_ALU_shamt),     // only used in (R) shift insns
        .data_result(DX_ALU_output)       // if (R) -> $rs + $rt; if (not R) -> $rs + N
        // Unused Output Ports: isNotEqual, isLessThan, overflow
    );

    //  --- EXECUTE STAGE Output Logic
    assign XM_data_in = {DX_ALU_output, DX_RS2VAL, DX_IR};

    /*  --- MEMORY STAGE --------------------------------------------------  */
    //  --- X/M Reg = {[127:96] X/M.PC, [95:64] X/M.ALUVAL, [63:32] X/M.RDVAL, [31:0] X/M.IR}
    pipeline_reg #(
        .DATA_WIDTH(96)
    ) XM_reg (  
        .clk(clock),
        .en(1'b1),
        .clr(reset),
        .data_in(XM_data_in),
        .data_out(XM_data_out)
    );

    assign XM_ALUVAL = XM_data_out[95:64]; // if (R) -> $rs + rt; if (not R) -> $rs + N
    assign XM_RDVAL = XM_data_out[63:32];  // only used when (I) sw -> $rd val; enforced w/ wren
    assign XM_IR = XM_data_out[31:0];

    //  --- DMEM (RAM) Logic
    //  output [31:0] address_dmem, data;
	//  output wren;
	//  input [31:0] q_dmem;
    assign wren = (XM_IR[31:27] == 5'b00111) ? 1'b1 : 1'b0; // allow wren on sw (00111) insns only
    assign address_dmem = XM_ALUVAL; // $rs + N; for sw -> used to write to DMEM, for lw -> used to save DMEM val to regfile, all else -> not used
    assign data = XM_RDVAL; // $rd write data for sw insns

    assign XM_lw_data = q_dmem; // lw data -> $rd = MEM[$rs + N], if not a lw insn, just never used so whatever's read from DMEM is irrelevant

    //  --- MEMORY STAGE Output Logic
    assign MW_data_in = {XM_ALUVAL, XM_lw_data, XM_IR};

    /*  --- WRITEBACK STAGE -----------------------------------------------  */
    pipeline_reg #(
        .DATA_WIDTH(96)
    ) MW_reg (  
        .clk(clock),
        .en(1'b1),
        .clr(reset),
        .data_in(MW_data_in),
        .data_out(MW_data_out)
    );

    assign MW_ALUVAL = MW_data_out[95:64];
    assign MW_RDVAL = MW_data_out[63:32];
    assign MW_IR = MW_data_out[31:0];

    //  --- Deciding what val to write back to regfile for {ALU insns, lw} logic
    //  if (R or addi) -> use output of ALU, XM_ALUVAL
    //  if (not, aka lw) -> use XM_lw_data
    assign ctrl_writeEnable = ( // 1 for ALU insns and lw, 0 all else and also if $rd == $0
        (
            MW_IR[31:27] == 5'b00000 || // allow writes to regfile on r-type insns or
            MW_IR[31:27] == 5'b00101 || // addi insn or
            MW_IR[31:27] == 5'b01000    // lw insn
        ) && // also make sure that we're not writing to register zero (not allowed)
        (
            MW_IR[26:22] != 5'd0
        )
    ) ? 1'b1 : 1'b0; 
    assign data_writeReg = (
        MW_IR[31:27] == 5'b00000 || // use ALU output if r-type insn or
        MW_IR[31:27] == 5'b00101    // addi insn
    ) ? MW_ALUVAL : MW_RDVAL;       // else, use lw data
    assign ctrl_writeReg = MW_IR[26:22];  //  THIS IS $rd addr

	/*  -------------------------------------------------------------------
     *  --- END OF DLX PROCESSOR IMPLEMENTATION                         ---
     *  -------------------------------------------------------------------  */

endmodule
