`timescale 1ns / 1ps

module mealy_tb;

    // Testbench signals
    reg clk;
    reg w;
    wire out;
    wire [2:0] data_out;
    wire [2:0] Y;  // For monitoring

    // Instantiate the counter module
    mealy UUT (
        .clk(clk),
        .w(w),
        .out(out)
    );

    assign data_out = UUT.data_out;
    assign Y = UUT.Y;

    initial begin
        // Initialize signals
        clk = 0;

        // Stimulus: Toggle `w` to see effect on the counter
        forever begin
            #10 clk = ~clk;

        end
    end
    
    // Test procedure
    initial begin
        // Initialize signals
        w = 0;
        #15;

        // Stimulus: Toggle `w` to see effect on the counter
        forever begin
            #10 w = ~w;
        end
    end

    // End simulation after a certain time
    initial begin
        #200; // Run the simulation for 200ns
        $finish;
    end

    // Monitor the outputs and clock
    initial begin
        $monitor("clk = %b, w = %b, Present State = %b, Next State = %b, Output = %b", clk, w, data_out, Y, out);
    end

    initial begin
        $dumpfile("mealy.vcd");
        $dumpvars(0, mealy_tb);
    end

endmodule
