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
    wire lw_WX_stall_rs1, lw_WX_stall_rs2;

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
    wire ALU_MX_bypass_rs1, ALU_WX_bypass_rs1;
    wire ALU_MX_bypass_rs2, ALU_WX_bypass_rs2;

    wire [31:0] DX_N;
    wire [31:0] DX_T;

    wire DX_ALU_overflow;
    wire [4:0] DX_ALU_opcode, DX_ALU_shamt;
    wire [31:0] DX_ALU_operandA, DX_ALU_operandB;
    wire [31:0] DX_ALU_output; // this is raw output of ALU

    //  EXECUTE STAGE output wires
    wire [31:0] XM_ALUVAL_in;     // this is final val saved to XM_reg after checking for exceptions and stuff
    wire [31:0] XM_IR_in;
    wire [95:0] XM_data_in;

    /*  --- MEMORY STAGE --------------------------------------------------  */
    //  X/M reg read values
    //  [95:64] = X/M.ALUVAL; R-type = $rs + $rt, I-type = $rs + N, 
    //  [63:32] = X/M.RDVAL; only used for sw, this is $rd val
    //  [31:0]  = X/M.IR
    wire [95:0] XM_data_out;
    wire [31:0] XM_ALUVAL, XM_RDVAL, XM_IR;

    //  DMEM Logic
    wire DMEM_WM_bypass_wdata; 

    wire [31:0] XM_sw_data;
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
        .en(PC_writeEnable), // [TODO]: maybe change later for disable PC reg?
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

    assign PC_data_in = ctrl_PC ? branch_PC : seq_PC;
    
    //  --- IMEM Logic
    assign address_imem = PC_data_out;
    assign PC_insn = q_imem;

    //  --- FETCH STAGE Output Logic
    assign FD_IR_in = ctrl_PC ? 32'd0 : PC_insn; // insert nop if take_I_branch
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

    alu FD_COMP(
        .data_operandA(FD_RS2VAL), // $rd, or if bex this is $r30
        .data_operandB(FD_RS1VAL), // $rs, or if bex this is $r0
        // Unused Input Ports: ctrl_ALUopcode, ctrl_shiftamt
        // Unused Output Ports: data_result, overflow
        .isNotEqual(rd_NE_rs),
        .isLessThan(rd_LT_rs)
    );

    assign take_I_branch = (
        (FD_IR[31:27] == 5'b00010 || FD_IR[31:27] == 5'b00110) && // is bne or blt
        (rd_NE_rs && rd_LT_rs) // $rd < $rs
    ) ? 1'b1 : 1'b0;
    
    // J branch logic
    assign FD_T = {5'b0, FD_IR[26:0]};

    assign J_PC = (
        FD_IR[31:27] == 5'b00001 ||    // j
        FD_IR[31:27] == 5'b00011 ||    // jal
        (FD_IR[31:27] == 5'b10110 && rd_NE_rs) // bex and $r30 != $r0
    ) ? FD_T : FD_RS2VAL;

    // Overall branch logic
    assign ctrl_PC = (
        FD_IR[31:27] == 5'b00001 ||  // j
        FD_IR[31:27] == 5'b00011 ||  // jal
        FD_IR[31:27] == 5'b00100     // jr
    ) ? 1'b1 : take_I_branch;

    assign branch_PC = (
        FD_IR[31:27] == 5'b00001 ||  // j
        FD_IR[31:27] == 5'b00011 ||  // jal
        FD_IR[31:27] == 5'b00100     // jr
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
    ) ? 5'd30 : (
        (FD_IR[31:27] == 5'd0) ? FD_IR[16:12] : FD_IR[26:22]
    ); // $rt addr if R-type, $rd addr if NOT R-type
	// ctrl_writeEnable, ctrl_writeReg, data_writeReg handled in writeback stage

	assign FD_RS1VAL = data_readRegA;     //  THIS IS $rs val
    assign FD_RS2VAL = data_readRegB;     //  THIS IS $rt val if R-type, $rd val if not

    //  --- DECODE STAGE Output Logic
    assign lw_WX_stall_rs1 = (
        (
            DX_IR[31:27] == 5'b01000 && (   // D/X == lw insn && F/D ==
                FD_IR[31:27] == 5'b00000 || // R-type ALU insn or
                FD_IR[31:27] == 5'b00101 || // addi ALU insn or
                FD_IR[31:27] == 5'b00111 || // sw MEM insn or
                FD_IR[31:27] == 5'b01000    // lw MEM insn
            )
        ) && (
            DX_IR[26:22] == FD_IR[21:17] && // lw $rd == ALU insn/MEM insn $rs (RS1)
            FD_IR[21:17] != 5'd0
        )
    ) ? 1'b1 : 1'b0;
    assign lw_WX_stall_rs2 = (
        (
            DX_IR[31:27] == 5'b01000 && (   // D/X == lw insn && F/D ==
                FD_IR[31:27] == 5'b00000    // R-type ALU insn
            )
        ) && (
            DX_IR[26:22] == FD_IR[16:12] && // D/X lw $rd == F/D ALU $rt only
            FD_IR[16:12] != 5'd0
        )
    ) ? 1'b1 : 1'b0;

    assign DX_IR_in = (
        lw_WX_stall_rs1 || 
        lw_WX_stall_rs2
    ) ? 32'd0 : FD_IR; // insert nop for lw stall
    assign PC_writeEnable = (
        lw_WX_stall_rs1 ||
        lw_WX_stall_rs2
    ) ? 1'b0 : 1'b1;   // disable write to PC reg on lw stall
    assign FD_writeEnable = (
        lw_WX_stall_rs1 ||
        lw_WX_stall_rs2
    ) ? 1'b0 : 1'b1;   // disable write to FD reg on lw stall


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

    //  --- ALU Logic
    assign DX_N = {{15{DX_IR[16]}}, DX_IR[16:0]}; // 32-b sign-extended I-type N
    assign DX_T = {5'b0, DX_IR[26:0]};
    assign DX_ALU_shamt = DX_IR[11:7]; // only used if the insn is a shift insn
    assign DX_ALU_opcode = (DX_IR[31:27] == 5'd0) ? DX_IR[6:2] : 5'd0; // if (R) -> DX.IR.ALUop; if (not R) -> always add
    
    // Bypassing to DX_ALU_operandA
    assign ALU_MX_bypass_rs1 = (
        (
            ( // XM == ALU insn
                XM_IR[31:27] == 5'b00000 || // r-type
                XM_IR[31:27] == 5'b00101    // addi
            ) && 
            ( // DX == ALU insn or MEM insn
                DX_IR[31:27] == 5'b00000 || // r-type
                DX_IR[31:27] == 5'b00101 || // addi
                DX_IR[31:27] == 5'b00111 || // sw
                DX_IR[31:27] == 5'b01000    // lw
            )
        ) && ( // and ALU $rd == ALU/MEM $rs
            XM_IR[26:22] == DX_IR[21:17] && // XM $rd == DX $rs
            DX_IR[21:17] != 5'd0
        )
    ) ? 1'b1 : 1'b0;
    assign ALU_WX_bypass_rs1 = (
        (
            ( // MW == ALU insn or lw
                MW_IR[31:27] == 5'b00000 || // r-type
                MW_IR[31:27] == 5'b00101 || // addi
                MW_IR[31:27] == 5'b01000    // lw
            ) && 
            ( // DX == ALU insn or MEM insn
                DX_IR[31:27] == 5'b00000 || // r-type
                DX_IR[31:27] == 5'b00101 || // addi
                DX_IR[31:27] == 5'b00111 || // sw
                DX_IR[31:27] == 5'b01000    // lw
            )
        ) && ( // and ALU or lw $rd == ALU/MEM $rs
            MW_IR[26:22] == DX_IR[21:17] && // MW $rd == DX $rs
            DX_IR[21:17] != 5'd0
        )
    ) ? 1'b1 : 1'b0;

    assign DX_ALU_operandA = (
        ALU_MX_bypass_rs1
    ) ? XM_ALUVAL : (
        (
            ALU_WX_bypass_rs1
        ) ? MW_writeData : DX_RS1VAL
    );

    // Bypassing to DX_ALU_operandB
    assign ALU_MX_bypass_rs2 = (
        (
            ( // XM == ALU insn
                XM_IR[31:27] == 5'b00000 || // r-type
                XM_IR[31:27] == 5'b00101    // addi
            ) && 
            ( // DX == ALU r-type insn only
                DX_IR[31:27] == 5'b00000    // r-type
            )
        ) && ( // and ALU $rd == ALU $rt
            XM_IR[26:22] == DX_IR[16:12] && // XM $rd == DX $rt
            DX_IR[16:12] != 5'd0
        )
    ) ? 1'b1 : 1'b0;
    assign ALU_WX_bypass_rs2 = (
        (
            ( // MW == ALU insn or lw
                MW_IR[31:27] == 5'b00000 || // r-type
                MW_IR[31:27] == 5'b00101 || // addi
                MW_IR[31:27] == 5'b01000    // lw
            ) && 
            ( // DX == ALU r-type insn only
                DX_IR[31:27] == 5'b00000    // r-type
            )
        ) && ( // and ALU or lw $rd == ALU $rt
            MW_IR[26:22] == DX_IR[16:12] && // MW $rd == DX $rt
            DX_IR[16:12] != 5'd0
        )
    ) ? 1'b1 : 1'b0;

    assign DX_ALU_operandB = (
        DX_IR[31:27] == 5'b00101 || // addi
        DX_IR[31:27] == 5'b00010 || // bne
        DX_IR[31:27] == 5'b00110 || // blt
        DX_IR[31:27] == 5'b00111 || // sw
        DX_IR[31:27] == 5'b01000    // lw
    ) ? DX_N : ( // if I_type, use DX_N for alu_opB no bypassing needed ever
        (        // else, need bypassing for R_type alu
            ALU_MX_bypass_rs2
        ) ? XM_ALUVAL : (
            (
                ALU_WX_bypass_rs2
            ) ? MW_writeData : DX_RS2VAL
        )
    );
    
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
    assign XM_ALUVAL_in = (DX_IR[31:27] == 5'b00011) ? ( // if jal (00011), use PC
        DX_PC
    ) : (
        (DX_IR[31:27] == 5'b10101) ? ( // if setx (10101), use DX_T
            DX_T
        ) : ( // else, check if it is an overflow
            (DX_ALU_overflow) ? (
                (DX_IR[31:27] == 5'b00000 || DX_IR[31:27] == 5'b00101) ? (    // if it was an ALU type insn (r-type or addi) -> (check types) : (set to 0)
                    (DX_IR[31:27] == 5'b00101) ? 32'd2 : (                    // if it was an addi -> (excpt == 2) : (check add, sub, mul, div)
                        (DX_IR[6:2] == 5'b00000) ? 32'd1 : (                  // if it was an add  -> (excpt == 1) : (check sub, mul, div)
                            (DX_IR[6:2] == 5'b00001) ? 32'd3 : (              // if it was a  sub  -> (excpt == 3) : (check mul, div)
                                (DX_IR[6:2] == 5'b00110) ? 32'd4 : (          // if it was a  mul  -> (excpt == 4) : (check div)
                                    (DX_IR[6:2] == 5'b00111) ? 32'd5 : (      // if it was a  duv  -> (excpt == 5) : (keep output from and/or/sll/sra)
                                        DX_ALU_output
                                    )
                                )  
                            )
                        )
                    )
                ) : 32'd0       // if NOT an ALU insn, set XM_ALUVAL_in = 0 to avoid fucking with DMEM
            ) : (
                DX_ALU_output // keep the alu output if not a setx and not an overflow
            )
        )
    );

    assign XM_IR_in = (DX_IR[31:27] == 5'b00011) ? ( // if it's a jal (00011), change $rd <- $31
        {DX_IR[31:27], 5'd31, DX_IR[21:0]}
    ) : (
        (DX_IR[31:27] == 5'b10101) ? ( // if it's a setx (10101), change $rd <- $30
            {DX_IR[31:27], 5'd30, DX_IR[21:0]}
        ) : ( // else, check if it IS an overflow -> (change $rd for the insn to be $r30) : (keep DX_IR the same)
            (DX_ALU_overflow) ? (
                (DX_IR[31:27] == 5'b00101 || (DX_IR[31:27] == 5'b00000 && (
                    DX_IR[6:2] == 5'b00000 ||
                    DX_IR[6:2] == 5'b00001 ||
                    DX_IR[6:2] == 5'b00110 ||
                    DX_IR[6:2] == 5'b00111
                ))) ? // if it was an ALU insn, write to $r30, else nothing ("write" to $r0)
                {DX_IR[31:27], 5'd30, DX_IR[21:0]} : // the excpt IR
                DX_IR
            ) : (
                DX_IR // keep DX_IR if not a setx and not an overflow
            )
        )
    ); 

    assign XM_data_in = {XM_ALUVAL_in, DX_RS2VAL, XM_IR_in};

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
    assign DMEM_WM_bypass_wdata = (
        (
            (
                MW_IR[31:27] == 5'b00000 || // r-type alu
                MW_IR[31:27] == 5'b00101 || // addi alu
                MW_IR[31:27] == 5'b01000    // lw
            ) && (
                XM_IR[31:27] == 5'b00111 // XM is sw only
            )
        ) && (
            MW_IR[26:22] == XM_IR[26:22] && // MW $rd == XM sw $rd
            XM_IR[26:22] != 5'd0
        )
    ) ? 1'b1 : 1'b0;

    assign XM_sw_data = DMEM_WM_bypass_wdata ? MW_writeData : XM_RDVAL;

    //  output [31:0] address_dmem, data;
	//  output wren;
	//  input [31:0] q_dmem;
    assign wren = (XM_IR[31:27] == 5'b00111) ? 1'b1 : 1'b0; // allow wren on sw (00111) insns only
    assign address_dmem = XM_ALUVAL; // $rs + N; for sw -> used to write to DMEM, for lw -> used to save DMEM val to regfile, all else -> not used
    assign data = XM_sw_data; // $rd write data for sw insns

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
    assign ctrl_writeEnable = (
        MW_IR[31:27] == 5'b10101 ||
        MW_IR[31:27] == 5'b00011
    ) ? ( // if setx (10101) or jal (00011), allow writes to $r30 or $r31 respectively
        1'b1
    ) : (
        ( // 1 for ALU insns and lw, 0 all else and also if $rd == $0
            (
                MW_IR[31:27] == 5'b00000 || // allow writes to regfile on r-type insns or
                MW_IR[31:27] == 5'b00101 || // addi insn or
                MW_IR[31:27] == 5'b01000    // lw insn
            ) && // also make sure that we're not writing to register zero (not allowed)
            (
                MW_IR[26:22] != 5'd0
            )
        ) ? 1'b1 : 1'b0
    ); 

    assign MW_writeData = (
        MW_IR[31:27] == 5'b00000 || // use ALU output if r-type insn or
        MW_IR[31:27] == 5'b00101 || // addi insn
        MW_IR[31:27] == 5'b10101 || // setx, this will be T
        MW_IR[31:27] == 5'b00011    // jal, this will be PC + 1
    ) ? MW_ALUVAL : MW_RDVAL;       // else, use lw data
    assign data_writeReg = MW_writeData;

    // THIS IS $rd addr, 
    // if setx it'll be $r30
    // if jal, it'll be $r31
    assign ctrl_writeReg = MW_IR[26:22];

	/*  -------------------------------------------------------------------
     *  --- END OF DLX PROCESSOR IMPLEMENTATION                         ---
     *  -------------------------------------------------------------------  */

endmodule
