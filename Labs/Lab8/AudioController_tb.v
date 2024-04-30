`timescale 1ns / 1ps

module AudioController_tb;

    // Inputs
    reg clk;
    reg micData;
    reg [3:0] switches;
    reg[10:0] FREQs[0:15];

    // Outputs
    wire micClk;
    wire chSel;
    wire audioOut;
    wire audioEn;

    // Instantiate the Unit Under Test (UUT)
    AudioController uut (
        .clk(clk),
        .micData(micData),
        .switches(switches),
        .micClk(micClk),
        .chSel(chSel),
        .audioOut(audioOut),
        .audioEn(audioEn)
    );

    wire toneAudio = uut.toneAudio;
    wire frequency;

    initial begin
        $readmemh("./FREQs.mem", FREQs);
        #10;
        $display("FREQs[0] = %d, FREQs[1] = %d", FREQs[0], FREQs[1]);
    end

    // Clock generation (100MHz)
    initial begin
        clk = 0;
        forever #5 clk = ~clk;  // 100MHz clock, period is 10ns (5ns high, 5ns low)
    end

    // Initialize Inputs and simulate switch changes
    initial begin
        // Initialize Inputs
        micData = 0;
        switches = 0;

        // Wait for global reset
        #100;

        // Change switches to select different frequencies
        switches = 4'b0001;  // Select second frequency
        #200;

        switches = 4'b0010;  // Select third frequency
        #200;

        switches = 4'b0100;  // Select fourth frequency
        #200;

        switches = 4'b1000;  // Select fifth frequency
        #200;

        // End simulation
        $stop;
    end
    
    // Optional: Monitoring changes
    initial begin
        $monitor("Time = %t, clk = %b, toneAudio = %b, switches = %b", $time, clk, toneAudio, switches);
    end

    initial begin
        $dumpfile("AudioController.vcd");
        $dumpvars(0, AudioController_tb);
    end

endmodule