
module register #(
    parameter DATA_WIDTH = 32
)(
    // CONTROL SIGNALS
    clk,                   // I: 1-bit clk signal, writes happen on posedges
    clr,              // I: 1-bit async clear signal, sets reg to 32'b0
    en,        // I: 1-bit write enable signal

    // REGISTER I/O 
    data_in,                 // I: 32-bit register WRITE input
    data_out                 // O: 32-bit register READ output
);

    // CONTROL SIGNALS
    input clk, clr, en;

    // REGISTER I/O
    input [DATA_WIDTH-1:0] data_in;
    output [DATA_WIDTH-1:0] data_out;

    /* ---- POSEDGE WRITE REGISTER IMPLEMENTATION ---------------------------------------------- */
    genvar i;
    generate
        for (i = 0; i < DATA_WIDTH; i = i + 1) begin: gen_dffe
            dffe_pos dffe_inst(
                .clk(clk),            // Common clk, reset, and WE signals between all 32 dffes
                .clr(clr),              
                .en(en),  
                .data_in(data_in[i]),     // ith DFFE takes 1-bit input of data_in
                .data_out(data_out[i])    // ith DFFE takes 1-bit output of data_out
            );
        end
    endgenerate

endmodule