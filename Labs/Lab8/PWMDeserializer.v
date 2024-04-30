`timescale 1ns / 1ps
module PWMDeserializer #(
    parameter
    WAVE_FREQ  = 10,
    PULSE_FREQ = 1000,
    SYS_FREQ   = 100000) (
    input clk,    // System clock = 100 MHz
    input reset,
    input signal, // PWM signal with samples every 1 MHz = every 49th sys clk posedge
    output[6:0] duty_cycle);
    
    localparam WAVE_WINDOW        = SYS_FREQ/WAVE_FREQ; // Duty cycle output = 10,000 cycles
    // localparam SMALL_WAVE_WINDOW  = WAVE_WINDOW/100;    
    // localparam WAVE_HALF          = WAVE_WINDOW >> 1;   
    localparam WAVE_COUNTER_BITS  = $clog2(WAVE_WINDOW) + 1;
    
    reg[WAVE_COUNTER_BITS-1:0] pulseCounter = 0;
    reg[WAVE_COUNTER_BITS-1:0] pulseWidth = 0;
    always @(posedge clk or posedge reset) begin
        if(reset) begin
            pulseCounter <= 0;
            pulseWidth   <= 0;
        end else begin
            if(pulseCounter < WAVE_WINDOW-1) begin
                pulseCounter <= pulseCounter + 1;
                pulseWidth   <= signal ? pulseWidth + 1 : pulseWidth;
            end else begin
                pulseCounter <= 0;
                pulseWidth   <= 0;
            end
        end
    end
    
    reg[WAVE_COUNTER_BITS-1:0] propWidth = 0;
    always @(negedge clk) begin
        if(pulseCounter == WAVE_WINDOW-1)
            propWidth <= pulseWidth;
    end
    
    assign duty_cycle = propWidth/99;
endmodule
