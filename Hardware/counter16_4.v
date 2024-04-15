
module counter16_4 (
    // CONTROL SIGNALS
    clk,
    clr,
    en,

    // COUNTER OUTPUT VALUE
    counter
);
    // CONTROL SIGNALS
    input clk, clr, en;

    // COUNTER OUTPUT VALUE
    output [3:0] counter; // 4 bit output = [Q3 Q2 Q1 Q0]

    /* ---- MOD-16 COUNTER IMPLEMENTATION ------------------------------------------------------ */
    wire t2, t3;
    wire q0, q1, q2, q3;

    tffe tffe0(.data_out(q0), .toggle(1'b1), .clk(clk), .en(en), .clr(clr));

    tffe tffe1(.data_out(q1), .toggle(q0), .clk(clk), .en(en), .clr(clr));

    and and2(t2, q0, q1);
    tffe tffe2(.data_out(q2), .toggle(t2), .clk(clk), .en(en), .clr(clr));

    and and3(t3, q0, q1, q2);
    tffe tffe3(.data_out(q3), .toggle(t3), .clk(clk), .en(en), .clr(clr));

    assign counter[0] = q0;
    assign counter[1] = q1;
    assign counter[2] = q2;
    assign counter[3] = q3;

endmodule