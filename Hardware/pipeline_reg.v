
module pipeline_reg #(
    parameter DATA_WIDTH = 32
)(
    // CONTROL SIGNALS
    clk,
    en,
    clr,

    // PIPELINE REGISTER I/O
    data_in,
    data_out
);

    // CONTROL SIGNALS
    input clk, en, clr;

    // REGISTER I/O
    input [DATA_WIDTH-1:0] data_in;
    output [DATA_WIDTH-1:0] data_out;

    /* ---- NEGEDGE WRITE PIPELINE REG IMPLEMENTATION ---------------------- */
    genvar i;
    generate
        for (i = 0; i < DATA_WIDTH; i = i + 1) begin: gen_dffe
            dffe_neg dffe_inst(
                .clk(clk),             
                .en(en),
                .clr(clr),  
                .data_in(data_in[i]),
                .data_out(data_out[i])
            );
        end
    endgenerate

endmodule