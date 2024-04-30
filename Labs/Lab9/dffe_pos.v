
module dffe_pos(
    // CONTROL SIGNALS
    clk,
    en,
    clr,

    // DFFE I/O
    data_in,
    data_out
);
   
    // CONTROL SIGNALS
    input clk, en, clr;
    wire clr;
   
    // DFFE I/O
    input data_in;
    output data_out;

    reg data_out;

    /*  --- POSEDGE WRITE DFFE IMPLEMENTATION -----------------------------  */
    // Intialize data_out to 0
    initial
    begin
        data_out = 1'b0;
    end

    // Set value of data_out on positive edge of the clock or clear
    always @(posedge clk) begin
        // If clear is high, set data_out to 0
        if (clr) begin
            data_out <= 1'b0;
        // If enable is high, set data_out to the value of data_in
        end else if (en) begin
            data_out <= data_in;
        end
    end

endmodule