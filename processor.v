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
    wire PC_writeEnable;
    wire [31:0] PC_data_in;  // [31:0] = incoming next PC addr
    wire [31:0] PC_data_out; // [31:0] = outgoing current PC addr, aka current insn addr

    //  Control hazard wires
    wire [31:0] seq_PC;     // seq_PC = PC_data_out + 1

    //  FETCH STAGE output wires
    wire [31:0] PC_insn;    // 32-bit ISA-encoded insn; PC_insn == q_imem
    wire [31:0] FD_IR_in;
    wire [63:0] FD_data_in; // {seq_PC, PC_insn}

    /*  --- DECODE STAGE --------------------------------------------------  */
    //  F/D reg read values
    //  [63:32] = F/D.PC; the "next" PC relative to current IR's PC
    //  [31:0]  = F/D.IR; the "current" PC's actual insn
    wire FD_writeEnable;
    wire [63:0] FD_data_out;
    wire [31:0] FD_PC, FD_IR;

    // Regfile wires
    wire [31:0] FD_RS1VAL;
    wire [31:0] FD_RS2VAL;

    // Next PC wires
    wire ctrl_PC;
    wire [31:0] branch_PC;

    wire take_I_branch;
    wire rd_NE_rs, rd_LT_rs;
    wire [31:0] FD_N, I_PC;

    wire [31:0] FD_T, J_PC;

    // DECODE STAGE output wires
    wire [31:0] FD_COMP_operandA, FD_COMP_operandB;
    wire insert_stall_rs1, insert_stall_rs2, insert_stall_multicycle;

    wire [31:0] DX_IR_in;
    wire [127:0] DX_data_in;

    /*  --- EXECUTE STAGE -------------------------------------------------  */
    //  D/X reg read values
    //  [95:64] = D/X.RS1VAL
    //  [63:32] = D/X.RS2VAL
    //  [31:0]  = D/X.IR
    wire [127:0] DX_data_out;
    wire [31:0] DX_PC, DX_RS1VAL, DX_RS2VAL, DX_IR;

    //  ALU Logic
    wire [31:0] DX_N;
    wire [31:0] DX_T;

    wire DX_ALU_overflow;
    wire [4:0] DX_ALU_opcode, DX_ALU_shamt;
    wire [31:0] DX_data_operandB;
    wire [31:0] DX_ALU_operandA, DX_ALU_operandB;
    wire [31:0] DX_ALU_output; // this is raw output of ALU

    //  EXECUTE STAGE output wires
    wire [31:0] XM_ALUVAL_in;     // this is final val saved to XM_reg after checking for exceptions and stuff
    wire [31:0] XM_IR_in;
    wire [95:0] XM_data_in;

    /*  --- MULTDIV STAGE -------------------------------------------------  */

    wire ctrl_MULT, ctrl_DIV;
    wire DX_MULTDIV_exception, DX_MULTDIV_dataRDY;
    wire [31:0] DX_MULTDIV_output;

    wire is_finished;
    wire PW_RDY;
    wire [31:0] PW_IR_out, PW_RES_in, PW_IR_in;
    wire [31:0] PW_RES, PW_IR;
    wire [64:0] PW_data_in, PW_data_out; 

    /*  --- MEMORY STAGE --------------------------------------------------  */
    //  X/M reg read values
    //  [95:64] = X/M.ALUVAL; R-type = $rs + $rt, I-type = $rs + N, 
    //  [63:32] = X/M.RDVAL; only used for sw, this is $rd val
    //  [31:0]  = X/M.IR
    wire [95:0] XM_data_out;
    wire [31:0] XM_ALUVAL, XM_RDVAL, XM_IR;

    //  DMEM Logic
    wire [31:0] XM_DMEM_writeData;
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

    // WRITEBACK STAGE output wires
    wire [31:0] MW_writeData;

	/*  -------------------------------------------------------------------
     *  --- DLX PROCESSOR IMPLEMENTATION                                ---
     *  -------------------------------------------------------------------  */

    /*  --- FETCH STAGE ---------------------------------------------------  */
    //  --- PC Reg = {PC}
    pipeline_reg #(
        .DATA_WIDTH(32)
    ) PC_reg (  
        .clk(clock),
        .en(PC_writeEnable),
        .clr(reset),
        .data_in(PC_data_in),
        .data_out(PC_data_out)
    );

    //  --- Control Hazard Logic
    alu incr_PC_ALU(
        .data_operandA(32'd1), 
        .data_operandB(PC_data_out),
        .ctrl_ALUopcode(5'd0), 
        .data_result(seq_PC)
        // Unused Input Ports: ctrl_shiftamt
        // Unused Output Ports: isNotEqual, isLessThan, overflow
    );

    assign PC_data_in = ctrl_PC ? branch_PC : seq_PC;
    
    //  --- IMEM Logic
    assign address_imem = PC_data_out;
    assign PC_insn = q_imem;

    //  --- FETCH STAGE Output Logic
    assign FD_IR_in = ctrl_PC ? 32'd0 : PC_insn; // "flush" the command going into FD.IR w/ a nop if branch is taken
    assign FD_data_in = {seq_PC, FD_IR_in};

    /*  --- DECODE STAGE --------------------------------------------------  */
    //  --- F/D Reg = {[63:32] F/D.PC, [31:0] F/D.IR}
    pipeline_reg #(
        .DATA_WIDTH(64)
    ) FD_reg (  
        .clk(clock),
        .en(FD_writeEnable),
        .clr(reset),
        .data_in(FD_data_in),
        .data_out(FD_data_out)
    );

    assign FD_PC = FD_data_out[63:32];
    assign FD_IR = FD_data_out[31:0];

    //  --- Branch Decoding Logic
    // I branch logic
    assign FD_N = {{15{FD_IR[16]}}, FD_IR[16:0]};

    alu FD_ALU(
        .data_operandA(FD_PC),
        .data_operandB(FD_N), 
        .ctrl_ALUopcode(5'd0),
        .data_result(I_PC)
        // Unused Input Ports: ctrl_shiftamt
        // Unused Output Ports: isNotEqual, isLessThan, overflow
    );

    // Bypassing to FD_COMPA
    assign FD_COMP_operandA = ( // (MD Bypass > WD Bypass > No Bypass (FD_RS2VAL == $rd))
        ( // MD BYPASS 'XM_ALUVAL' TO $rd IF: XM = ALU only | FD = bne, blt, jr, bex
            ( // dependency relations for bne, blt, jr, bex
                (
                    XM_IR[31:27] == 5'b00000 || // ALU only
                    XM_IR[31:27] == 5'b00101    // addi
                ) && (
                    FD_IR[31:27] == 5'b00010 || // bne
                    FD_IR[31:27] == 5'b00110 || // blt
                    FD_IR[31:27] == 5'b00100 || // jr
                    FD_IR[31:27] == 5'b10110    // bex
                )
            ) && ( // check if there's an actual dependency 
                (
                    FD_IR[31:27] == 5'b10110
                ) ? (
                    XM_IR[26:22] == 5'd30           // XM $rd == $r30 for the bex check
                ) : (                               // check all else
                    XM_IR[26:22] == FD_IR[26:22] && // XM $rd == FD bne/blt/jr's $rd
                    FD_IR[26:22] != 5'd0            // FD $rd != 0
                )
            )
        ) 
    ) ? (XM_ALUVAL) : (
        ( // WD BYPASS 'MW_writeData' TO $rd IF: MW = ALU, lw | FD = bne, blt, jr, bex
            ( // dependency relations for bne, blt, jr, bex
                (
                    MW_IR[31:27] == 5'b00000 || // ALU
                    MW_IR[31:27] == 5'b00101 || // addi
                    MW_IR[31:27] == 5'b01000    // lw
                ) && (
                    FD_IR[31:27] == 5'b00010 || // bne
                    FD_IR[31:27] == 5'b00110 || // blt
                    FD_IR[31:27] == 5'b00100 || // jr
                    FD_IR[31:27] == 5'b10110    // bex
                )
            ) && ( // check if there's an actual dependency
                (
                    FD_IR[31:27] == 5'b10110
                ) ? (
                    MW_IR[26:22] == 5'd30           // MW $rd == $r30 for the bex check
                ) : (                               // check all else
                    MW_IR[26:22] == FD_IR[26:22] && // MW $rd == FD bne/blt/jr's $rd
                    FD_IR[26:22] != 5'd0            // FD $rd != 0
                )
            )
        ) ? (MW_writeData) : (FD_RS2VAL)
    );

    // Bypassing to FD_COMPB
    assign FD_COMP_operandB = ( // (MD Bypass > WD Bypass > No Bypass (FD_RS1VAL == $rs))
        ( // MD BYPASS 'XM_ALUVAL' TO $rs IF: XM = ALU only | FD = bne, blt
            ( // dependency relations for bne, blt
                (
                    XM_IR[31:27] == 5'b00000 || // ALU only
                    XM_IR[31:27] == 5'b00101    // addi
                ) && (
                    FD_IR[31:27] == 5'b00010 || // bne
                    FD_IR[31:27] == 5'b00110    // blt
                )
            ) && ( // check if there's an actual dependency 
                XM_IR[26:22] == FD_IR[21:17] && // XM $rd == FD bne/blt's $rs
                FD_IR[21:17] != 5'd0            // FD $rs != 0
            )
        )
    ) ? (XM_ALUVAL) : (
        ( // WD BYPASS 'MW_writeData' TO $rs IF: MW = ALU, lw | FD = bne, blt
            ( // dependency relations for bne, blt
                (
                    MW_IR[31:27] == 5'b00000 || // ALU
                    MW_IR[31:27] == 5'b00101 || // addi
                    MW_IR[31:27] == 5'b01000    // lw
                ) && (
                    FD_IR[31:27] == 5'b00010 || // bne
                    FD_IR[31:27] == 5'b00110    // blt
                )
            ) && ( // check if there's an actual dependency
                MW_IR[26:22] == FD_IR[21:17] && // MW $rd == FD bne/blt's $rs
                FD_IR[21:17] != 5'd0            // FD $rs != 0
            )
        ) ? (MW_writeData) : (FD_RS1VAL)
    );

    alu FD_COMP(
        .data_operandA(FD_COMP_operandA),
        .data_operandB(FD_COMP_operandB),
        // Unused Input Ports: ctrl_ALUopcode, ctrl_shiftamt
        // Unused Output Ports: data_result, overflow
        .isNotEqual(rd_NE_rs),
        .isLessThan(rd_LT_rs)
    );

    assign take_I_branch = (
        (FD_IR[31:27] == 5'b00010 && rd_NE_rs) || // is bne and $rd != $rs
        (FD_IR[31:27] == 5'b00110 && rd_LT_rs)    // is blt and $rd < $rs
    ) ? 1'b1 : 1'b0;
    
    // J branch logic
    assign FD_T = {5'b0, FD_IR[26:0]};

    assign J_PC = (
        FD_IR[31:27] == 5'b00001 ||             // j
        FD_IR[31:27] == 5'b00011 ||             // jal
        (FD_IR[31:27] == 5'b10110 && rd_NE_rs)  // bex and $r30 != $r0
    ) ? FD_T : FD_COMP_operandA; // j, jal, bex are all PC = T; while jr is PC = $rd

    // Overall branch logic
    assign ctrl_PC = (
        FD_IR[31:27] == 5'b00001 ||  // j
        FD_IR[31:27] == 5'b00011 ||  // jal
        FD_IR[31:27] == 5'b00100 ||  // jr
        (FD_IR[31:27] == 5'b10110 && rd_NE_rs) // bex and $r30 != $r0
    ) ? 1'b1 : take_I_branch;

    assign branch_PC = (
        FD_IR[31:27] == 5'b00001 ||  // j
        FD_IR[31:27] == 5'b00011 ||  // jal
        FD_IR[31:27] == 5'b00100 ||  // jr
        (FD_IR[31:27] == 5'b10110 && rd_NE_rs)  // bex and $r30 != $r0
    ) ? J_PC : I_PC;

    //  --- Regfile Read/Write Logic
    //  output ctrl_writeEnable;
	//  output [4:0] ctrl_writeReg, ctrl_readRegA, ctrl_readRegB;
	//  output [31:0] data_writeReg;
	//  input [31:0] data_readRegA, data_readRegB;
    assign ctrl_readRegA = (
        FD_IR[31:27] == 5'b10110 // if bex (10110), use $r0 instead of $rs
    ) ? 5'd0 : FD_IR[21:17];  // THIS IS $rs addr
    
    assign ctrl_readRegB = (
        FD_IR[31:27] == 5'b10110 // if bex (10110), use $r30 instead of either
    ) ? (5'd30) : (
        (FD_IR[31:27] == 5'd0) ? FD_IR[16:12] : FD_IR[26:22]
    ); // $rt addr if R-type, $rd addr if NOT R-type
	// ctrl_writeEnable, ctrl_writeReg, data_writeReg handled in writeback stage

	assign FD_RS1VAL = data_readRegA;     //  THIS IS $rs val
    assign FD_RS2VAL = data_readRegB;     //  THIS IS $rt val if R-type, $rd val if not

    //  --- DECODE STAGE Output Logic
    assign insert_stall_rs1 = (
        ( // RS1 STALL IF: DX = lw only | FD = ALU, sw, lw
            ( // dependency relations for ALU, sw, lw
                (
                    DX_IR[31:27] == 5'b01000    // lw
                ) &&
                (
                    FD_IR[31:27] == 5'b00000 || // r-type alu
                    FD_IR[31:27] == 5'b00101 || // addi
                    FD_IR[31:27] == 5'b00111 || // sw
                    FD_IR[31:27] == 5'b01000    // lw
                )
            ) && ( // check if there's an actual dependency
                DX_IR[26:22] == FD_IR[21:17] && // $rd == $rs
                FD_IR[21:17] != 5'd0            // $rs != 0
            )
        ) || 
        ( // RS1 STALL IF: DX = ALU, lw | FD = bne, blt
            ( // dependency relations for bne, blt
                (
                    DX_IR[31:27] == 5'b00000 || // ALU
                    DX_IR[31:27] == 5'b00101 || // 
                    DX_IR[31:27] == 5'b01000    // lw
                ) &&
                (
                    FD_IR[31:27] == 5'b00010 || // bne
                    FD_IR[31:27] == 5'b00110    // blt
                )
            ) && ( // check if there's an actual dependency
                DX_IR[26:22] == FD_IR[21:17] && // $rd == FD bne/blt's $rs
                FD_IR[21:17] != 5'd0            // $rs != 0
            )
        ) ||
        ( // RS1 STALL IF: XM = lw only | FD = bne, blt
            ( // dependency relations for bne, blt
                (
                    XM_IR[31:27] == 5'b01000
                ) && (
                    FD_IR[31:27] == 5'b00010 || // bne
                    FD_IR[31:27] == 5'b00110    // blt
                )
            ) && ( // check if there's an actual dependency
                XM_IR[26:22] == FD_IR[21:17] && // $rd == $rs
                FD_IR[21:17] != 5'd0            // $rs != 0
            )
        )
    ) ? 1'b1 : 1'b0;

    assign insert_stall_rs2 = (
        ( // RS2 STALL IF: DX = lw only | FD = ALU (r-type only)
            ( // dependency relations for ALU
                (
                    DX_IR[31:27] == 5'b01000    // lw
                ) &&
                (
                    FD_IR[31:27] == 5'b00000    // r-type alu
                )
            ) && ( // check if there's an actual dependency
                DX_IR[26:22] == FD_IR[16:12] && // $rd == $rt
                FD_IR[16:12] != 5'd0            // $rt != 0
            )
        ) || 
        ( // RS2 STALL IF: DX = ALU, lw | FD = bne, blt, jr, bex
            ( // dependency relations for bne, blt, jr, bex
                (
                    DX_IR[31:27] == 5'b00000 || // ALU
                    DX_IR[31:27] == 5'b00101 || // 
                    DX_IR[31:27] == 5'b01000    // lw
                ) &&
                (
                    FD_IR[31:27] == 5'b00010 || // bne
                    FD_IR[31:27] == 5'b00110 || // blt
                    FD_IR[31:27] == 5'b00100 || // jr
                    FD_IR[31:27] == 5'b10110    // bex
                )
            ) && ( // check if there's an actual dependency
                (
                    FD_IR[31:27] == 5'b10110        // always stall once on bex's as long as not a nop
                ) ? (
                    DX_IR != 32'd0                  // stall if not nop
                ) : (                               // else, check for dependency
                    DX_IR[26:22] == FD_IR[26:22] && // DX $rd == FD bne/blt/jr's $rd
                    FD_IR[26:22] != 5'd0            // FD $rd != 0
                )
            )
        ) ||
        ( // RS2 STALL IF: XM = lw only | FD = bne, blt, jr, bex
            ( // dependency relations for bne, blt, jr, bex
                (
                    XM_IR[31:27] == 5'b01000    // lw
                ) && (
                    FD_IR[31:27] == 5'b00010 || // bne
                    FD_IR[31:27] == 5'b00110 || // blt
                    FD_IR[31:27] == 5'b00100 || // jr
                    FD_IR[31:27] == 5'b10110    // bex
                )
            ) && ( // check if there's an actual dependency
                (
                    FD_IR[31:27] == 5'b10110        // for bex's, stall if loading to $r30
                ) ? (
                    XM_IR[26:22] == 5'd30           // dependency is to $r30
                ) : (
                    XM_IR[26:22] == FD_IR[26:22] && // XM $rd == FD bne/blt/jr's $rd
                    FD_IR[26:22] != 5'd0            // FD $rd != 0
                )
            )
        )
    ) ? 1'b1 : 1'b0;

    assign insert_stall_multicycle = (
        PW_IR_out != 32'd0
    );

    assign DX_IR_in = (
        insert_stall_rs1 || 
        insert_stall_rs2 ||
        insert_stall_multicycle
    ) ? 32'd0 : FD_IR; // insert nop for stall

    assign PC_writeEnable = (
        insert_stall_rs1 ||
        insert_stall_rs2 ||
        insert_stall_multicycle
    ) ? 1'b0 : 1'b1;   // disable write to PC reg on stall

    assign FD_writeEnable = (
        insert_stall_rs1 ||
        insert_stall_rs2 ||
        insert_stall_multicycle
    ) ? 1'b0 : 1'b1;   // disable write to FD reg on stall


    assign DX_data_in = {FD_PC, FD_RS1VAL, FD_RS2VAL, DX_IR_in};

    /*  --- EXECUTE STAGE -------------------------------------------------  */
    //  --- D/X Reg = {[95:64] D/X.RS1VAL, [63:32] D/X.RS2VAL, [31:0] D/X.IR}
    pipeline_reg #(
        .DATA_WIDTH(128)
    ) DX_reg (  
        .clk(clock),
        .en(1'b1),
        .clr(reset),
        .data_in(DX_data_in),
        .data_out(DX_data_out)
    );

    assign DX_PC = DX_data_out[127:96];
    assign DX_RS1VAL = DX_data_out[95:64]; // always the $rs val
    assign DX_RS2VAL = DX_data_out[63:32]; // if (R) -> $rt val; if (not R) -> $rd val
    assign DX_IR = DX_data_out[31:0];

    assign ctrl_MULT = DX_IR[31:27] == 5'b0 && DX_IR[6:2] == 5'b00110;
    assign ctrl_DIV = DX_IR[31:27] == 5'b0 && DX_IR[6:2] == 5'b00111;

    //  --- ALU Logic
    assign DX_N = {{15{DX_IR[16]}}, DX_IR[16:0]}; // 32-b sign-extended I-type N
    assign DX_T = {5'b0, DX_IR[26:0]};
    assign DX_ALU_shamt = DX_IR[11:7]; // only used if the insn is a shift insn
    assign DX_ALU_opcode = (DX_IR[31:27] == 5'd0) ? DX_IR[6:2] : 5'd0; // if (R) -> DX.IR.ALUop; if (not R) -> always add
    
    // Bypassing to DX_ALU_operandA
    // (MX Bypass > WX Bypass > No Bypass (DX_RS1VAL))
    assign DX_ALU_operandA = ( // first, check for MX bypasses to $rs
        ( // MX BYPASS 'XM_ALUVAL' TO $rs IF: XM = ALU only | DX = ALU, lw, sw
            ( // dependency relations for alu, mem
                (
                    XM_IR[31:27] == 5'b00000 || // ALU only
                    XM_IR[31:27] == 5'b00101    // addi
                ) && (
                    DX_IR[31:27] == 5'b00000 || // ALU
                    DX_IR[31:27] == 5'b00101 || // addi
                    DX_IR[31:27] == 5'b01000 || // lw
                    DX_IR[31:27] == 5'b00111    // sw
                )
            ) && ( // check if there's an actual dependency 
                XM_IR[26:22] == DX_IR[21:17] && // $rd == $rs
                DX_IR[21:17] != 5'd0            // $rs != 0
            )
        ) 
    ) ? (XM_ALUVAL) : ( // then, check for WX bypasses to $rs
        ( // WX BYPASS 'MW_writeData' TO $rs IF: MW = ALU, lw | DX = ALU, lw, sw
            ( // dependency relations for alu, mem
                (
                    MW_IR[31:27] == 5'b00000 || // ALU
                    MW_IR[31:27] == 5'b00101 || // addi
                    MW_IR[31:27] == 5'b01000    // lw
                ) && (
                    DX_IR[31:27] == 5'b00000 || // ALU
                    DX_IR[31:27] == 5'b00101 || // addi
                    DX_IR[31:27] == 5'b01000 || // lw
                    DX_IR[31:27] == 5'b00111    // sw
                )
            ) && ( // check if there's an actual dependency
                MW_IR[26:22] == DX_IR[21:17] && // $rd == $rs
                DX_IR[21:17] != 5'd0            // $rs != 0
            )
        ) ? (MW_writeData) : (DX_RS1VAL)
        // finally, if no bypasses, just use the $rs value
    );

    // Bypassing to DX_ALU_operandB
    assign DX_data_operandB = ( // first, check if there's a MX bypass possible, if so use 'XM_ALUVAL'
        ( // MX BYPASS 'XM_ALUVAL' TO $rt IF: XM = ALU | DX = ALU (r-type only), sw
            ( // dependency relations for ALU
                (
                    XM_IR[31:27] == 5'b00000 || // ALU only
                    XM_IR[31:27] == 5'b00101    // addi
                ) && (
                    DX_IR[31:27] == 5'b00000 || // ALU
                    DX_IR[31:27] == 5'b00111    // sw
                )
            ) && ( // check if there's an actual dependency 
                XM_IR[26:22] == (DX_IR[31:27] == 5'b00000 ? DX_IR[16:12] : DX_IR[26:22]) && // $rd == $rt if ALI, $rd if sw
                (DX_IR[31:27] == 5'b00000 ? DX_IR[16:12] : DX_IR[26:22]) != 5'd0            // $rt/$rs != 0
            )
        ) 
    ) ? (XM_ALUVAL) : ( // then, check if there's a WX bypass possible, if so use 'MW_writeData'
        ( // WX BYPASS 'MW_writeData' TO $rt IF: MW = ALU, lw | DX = ALU, sw
            ( // dependency relations for ALU
                (
                    MW_IR[31:27] == 5'b00000 || // ALU
                    MW_IR[31:27] == 5'b00101 || // addi
                    MW_IR[31:27] == 5'b01000    // lw
                ) && (
                    DX_IR[31:27] == 5'b00000 || // ALU
                    DX_IR[31:27] == 5'b00111    // sw
                )
            ) && ( // check if there's an actual dependency
                MW_IR[26:22] == (DX_IR[31:27] == 5'b00000 ? DX_IR[16:12] : DX_IR[26:22]) && // $rd == $rt if ALI, $rd if sw
                (DX_IR[31:27] == 5'b00000 ? DX_IR[16:12] : DX_IR[26:22]) != 5'd0            // $rt/$rs != 0
            )
        ) ? (MW_writeData) : (DX_RS2VAL) 
    ); // otherwise, then it's not an I-type ALU insn nor does it have a bypass, aka r-type ALU insn that just uses $rt

    assign DX_ALU_operandB = ( // first, check if an I-type ALU insn, if so no need to bypass just use the constant
        DX_IR[31:27] == 5'b00101 || // addi
        DX_IR[31:27] == 5'b00111 || // sw
        DX_IR[31:27] == 5'b01000    // lw
    ) ? (DX_N) : (DX_data_operandB);
    
    alu DX_ALU(
        .data_operandA(DX_ALU_operandA),        // always $rs val
        .data_operandB(DX_ALU_operandB),  // if (R) -> DX_RS2VAL == $rt; if (not R) -> I_type_constant = N
        .ctrl_ALUopcode(DX_ALU_opcode),   // if (R) -> ALUop; if (not R) -> add
        .ctrl_shiftamt(DX_ALU_shamt),     // only used in (R) shift insns
        .data_result(DX_ALU_output),       // if (R) -> $rs + $rt; if (not R) -> $rs + N
        // Unused Output Ports: isNotEqual, isLessThan, overflow
        .overflow(DX_ALU_overflow)
    );

    //  --- EXECUTE STAGE Output Logic
    // if it IS an overflow -> (assign to exception val) : (just use DX_ALU_output)
    assign XM_ALUVAL_in = ( // if jal (00011), set XM_ALUVAL = PC + 1
        DX_IR[31:27] == 5'b00011
    ) ? (DX_PC) : (
        ( // if setx (10101), set XM_ALUVAL = T
            DX_IR[31:27] == 5'b10101
        ) ? (DX_T) : (
            ( // if it is an overflow and addi, set XM_ALUVAL = 2
                DX_ALU_overflow && 
                DX_IR[31:27] == 5'b00101
            ) ? (32'd2) : (
                ( // if it's an overflow and add, set XM_ALUVAL = 1
                    DX_ALU_overflow &&
                    DX_IR[31:27] == 5'b00000 &&
                    DX_IR[6:2] == 5'b00000
                ) ? (32'd1) : (
                    ( // if it's an overflow and sub, set XM_ALUVAL = 3
                        DX_ALU_overflow &&
                        DX_IR[31:27] == 5'b00000 &&
                        DX_IR[6:2] == 5'b00001
                    )  ? (32'd3) : (
                        ( // else XM_ALUVAL = DX_ALU_Output
                            DX_ALU_output
                        )
                    )
                )
            )
        )
    );

    assign XM_IR_in = ( // if ctrl_MULT or ctrl_DIV, turn into XM_IR into a nop
        ctrl_MULT ||
        ctrl_DIV
    ) ? (32'd0) : (
        ( // if it's a jal (00011), change $rd <- $31, also change opcode to 5'd0 to look like an "ALU" operation for bypassing
            DX_IR[31:27] == 5'b00011
        ) ? ({5'd0, 5'd31, DX_IR[21:0]}) : (
            ( // if it's a setx (10101), change $rd <- $30, and change opcode to 5'd0 to look like an ALU op for bypassing
                DX_IR[31:27] == 5'b10101
            ) ? ({5'd0, 5'd30, DX_IR[21:0]}) : (
                ( // else, check if it IS an overflow -> (change $rd for the insn to be $r30) : (keep DX_IR the same)
                    DX_ALU_overflow
                ) ? (
                    ( // if it was an ALU insn, write to $r30, else keep DX_IR
                        DX_IR[31:27] == 5'b00101 || // is an addi
                        (
                            DX_IR[31:27] == 5'b00000 && // is an r-type and
                            (
                                DX_IR[6:2] == 5'b00000 || // is an add
                                DX_IR[6:2] == 5'b00001    // is a sub
                            )
                        )
                    ) ? ({DX_IR[31:27], 5'd30, DX_IR[21:0]}) : (DX_IR)
                ) : (DX_IR) // keep DX_IR if not a setx and not an overflow
            )
        )
    );

    assign XM_data_in = {XM_ALUVAL_in, DX_data_operandB, XM_IR_in};

    /*  --- MULTDIV STAGE -------------------------------------------------  */

    register #(
        .DATA_WIDTH(32)
    ) PW_IR_reg (  
        .clk(clock),
        .en((ctrl_MULT || ctrl_DIV)),
        .clr(reset || is_finished),
        .data_in(DX_IR),
        .data_out(PW_IR_out)
    );

    multdiv DX_MULTDIV(
        .data_operandA(DX_ALU_operandA), 
        .data_operandB(DX_ALU_operandB), 
        .ctrl_MULT(ctrl_MULT), 
        .ctrl_DIV(ctrl_DIV), 
        .clock(clock), 
        .data_result(DX_MULTDIV_output), 
        .data_exception(DX_MULTDIV_exception), 
        .data_resultRDY(DX_MULTDIV_dataRDY)
    );

    assign PW_RES_in = (
        DX_MULTDIV_exception
    ) ? (
        PW_IR_out[6:2] == 5'b00110 ? 32'd4 : 32'd5
    ) : (DX_MULTDIV_output);

    assign PW_IR_in = (
        DX_MULTDIV_exception
    ) ? ({5'd0, 5'd30, PW_IR_out[21:0]}) : (PW_IR_out);

    assign PW_data_in = {DX_MULTDIV_dataRDY, PW_RES_in, PW_IR_in};

    //  --- P/W Reg = {[63:32] P/W.RES, [31:0] P/W.IR}
    pipeline_reg #(
        .DATA_WIDTH(65)
    ) PW_reg (  
        .clk(clock),
        .en(DX_MULTDIV_dataRDY),
        .clr(reset || is_finished),
        .data_in(PW_data_in),
        .data_out(PW_data_out)
    );

    assign PW_RDY = PW_data_out[64];
    assign PW_RES = PW_data_out[63:32];
    assign PW_IR = PW_data_out[31:0];

    assign is_finished = (
        MW_IR == PW_IR &&
        MW_IR != 32'd0
    );
    
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

    assign XM_ALUVAL = (PW_RDY) ? (PW_RES) : (XM_data_out[95:64]); // if (R) -> $rs + rt; if (not R) -> $rs + N
    assign XM_RDVAL = XM_data_out[63:32];  // only used when (I) sw -> $rd val; enforced w/ wren
    assign XM_IR = (PW_RDY) ? (PW_IR) : (XM_data_out[31:0]);

    //  --- DMEM (RAM) Logic
    // Bypassing to DMEM write data for sw's
    assign XM_DMEM_writeData = ( // first, check for MW bypasses to $rd
        ( // MW BYPASS 'MW_writeData' TO $rd IF: MW = ALU, lw | XM = sw
            ( // dependency relations for sw
                (
                    MW_IR[31:27] == 5'b00000 || // ALU only
                    MW_IR[31:27] == 5'b00101 || // addi
                    MW_IR[31:27] == 5'b01000    // lw
                ) && (
                    XM_IR[31:27] == 5'b00111    // sw
                )
            ) && ( // check if there's an actual dependency 
                MW_IR[26:22] == XM_IR[26:22] && // MW $rd == XM sw's $rd
                XM_IR[26:22] != 5'd0            // XM sw's $rd != 0
            )
        ) 
    ) ? (MW_writeData) : (XM_RDVAL);

    //  output [31:0] address_dmem, data;
	//  output wren;
	//  input [31:0] q_dmem;
    assign wren = (XM_IR[31:27] == 5'b00111) ? 1'b1 : 1'b0; // allow wren on sw (00111) insns only
    assign address_dmem = XM_ALUVAL; // $rs + N; for sw -> used to write to DMEM, for lw -> used to save DMEM val to regfile, all else -> not used
    assign data = XM_DMEM_writeData; // $rd write data for sw insns

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
            MW_IR[31:27] == 5'b00000 || // allow writes to regfile on r-type insns/jal/setx or
            MW_IR[31:27] == 5'b00101 || // addi insn or
            MW_IR[31:27] == 5'b01000    // lw insn
        ) && // also make sure that we're not writing to register zero (not allowed)
        (
            MW_IR[26:22] != 5'd0
        )
    ) ? (1'b1) : (1'b0);

    assign MW_writeData = (
        (

        ) ? () : (
            MW_IR[31:27] == 5'b00000 || // use ALU output if r-type insn/jal/setx
            MW_IR[31:27] == 5'b00101    // addi insn
        ) ? (MW_ALUVAL) : (MW_RDVAL)
    ); // else, use lw data

    assign data_writeReg = MW_writeData;

    // THIS IS $rd addr, 
    // if setx it'll be $r30
    // if jal, it'll be $r31
    assign ctrl_writeReg = MW_IR[26:22];

	/*  -------------------------------------------------------------------
     *  --- END OF DLX PROCESSOR IMPLEMENTATION                         ---
     *  -------------------------------------------------------------------  */

endmodule
