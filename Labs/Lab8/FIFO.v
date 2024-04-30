`timescale 1ns / 1ps
module FIFO #( parameter DATA_WIDTH = 8, ADDRESS_WIDTH = 8, DEPTH = 256, MEMFILE = "") (
    input wire                     clk,
    input wire                     wEn,
    input wire [ADDRESS_WIDTH-1:0] addr,
    input wire [DATA_WIDTH-1:0]    dataIn,
    output wire [DATA_WIDTH-1:0]    dataOut);
    
    reg[DATA_WIDTH-1:0] MemoryArray[0:DEPTH-1];
    
    always @(posedge clk) begin
        if(wEn) begin
            MemoryArray[addr] <= dataIn;
        end
    end

   assign dataOut <= MemoryArray[addr];
endmodule
