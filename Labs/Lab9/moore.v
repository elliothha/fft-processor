

module moore(
    // CONTROL SIGNALS
    clk,
    w,
    out
);
   
    input clk, w;
   
    output out;

    /*  --- MOORE MOD-5 COUNTER IMPLEMENTATION -----------------------------  */
    
    wire [2:0] data_out, Y, next;
    wire y0, y1, y2;
    
    assign Y[0] = ((~w && y0) || (w && ~y0));
    assign Y[1] = ((~w && y1) || (y1 && ~y0) || (w && y0 && ~y1));
    assign Y[2] = ((~w && y2) || (~y0 && y2) || (~y1 && y2) || (w && y0 && y1 && ~y2));

    assign data_out = {y2, y1, y0};

    assign out = (data_out == 3'b100) ? 1'b1 : 1'b0;

    dffe_pos y0_state(
        .clk(clk),
        .en(1'b1),
        .clr((data_out == 3'b100 && w)),
        .data_in(Y[0]),
        .data_out(y0)
    );

    dffe_pos y1_state(
        .clk(clk),
        .en(1'b1),
        .clr((data_out == 3'b100 && w)),
        .data_in(Y[1]),
        .data_out(y1)
    );

    dffe_pos y2_state(
        .clk(clk),
        .en(1'b1),
        .clr((data_out == 3'b100 && w)),
        .data_in(Y[2]),
        .data_out(y2)
    );

endmodule