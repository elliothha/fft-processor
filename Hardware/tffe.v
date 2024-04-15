
module tffe (
    // CONTROL SIGNALS
    clk,
    clr,
    en,

    // TFFE I/O
    toggle,
    data_out
);

    // CONTROL SIGNALS
    input wire clk, clr, en;

    // TFFE I/O
    input wire toggle;
    output wire data_out;
    
    wire a1, a2, d;
    
    // Toggle logic: d = t XOR q
    and and1(a1, ~toggle, data_out);
    and and2(a2, toggle, ~data_out);
    or set_input(d, a1, a2); 
    
    // Instantiate the D flip-flop with enable
    dffe_pos dffe(
        .clk(clk),
        .clr(clr),
        .en(en),
        .data_in(d),
        .data_out(data_out)
    );

endmodule